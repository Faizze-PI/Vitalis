import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.gradle.testing.jacoco.plugins.JacocoTaskExtension
import org.gradle.testing.jacoco.tasks.JacocoReport

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    jacoco
}

jacoco {
    toolVersion = "0.8.13"
}

tasks.withType<Test>().configureEach {
    extensions.configure<JacocoTaskExtension> {
        isIncludeNoLocationClasses = true
        includes = listOf("com/vitalis/vitalis_app/transfer/*")
    }
}

tasks.register<JacocoReport>("transferCoverageReport") {
    dependsOn("testDebugUnitTest")
    executionData(layout.buildDirectory.file("jacoco/testDebugUnitTest.exec"))
    classDirectories.setFrom(fileTree(
        layout.buildDirectory.dir("intermediates/javac/debug/compileDebugJavaWithJavac/classes")
    ) {
        include("com/vitalis/vitalis_app/transfer/**")
    })
    sourceDirectories.setFrom(files("src/main/java"))
    reports {
        xml.required.set(true)
        html.required.set(true)
    }
    doFirst {
        require(executionData.files.all { it.isFile && it.length() > 0L }) {
            "Transfer coverage execution data is missing or empty."
        }
        require(!classDirectories.isEmpty) { "Transfer coverage classes are missing." }
    }
}

val coverageGateClasses = layout.buildDirectory.dir("tool/transfer-coverage-gate")
val compileCoverageGate = tasks.register<JavaCompile>("compileTransferCoverageGate") {
    source(rootProject.file("../tool/TransferCoverageGate.java"),
        rootProject.file("../tool/TransferCoverageGateTest.java"))
    classpath = files()
    destinationDirectory.set(coverageGateClasses)
    sourceCompatibility = "17"
    targetCompatibility = "17"
}
val coverageGateSelfTest = tasks.register<JavaExec>("transferCoverageGateSelfTest") {
    dependsOn(compileCoverageGate)
    classpath = files(coverageGateClasses)
    mainClass.set("TransferCoverageGateTest")
}
tasks.register<JavaExec>("transferCoverageVerify") {
    dependsOn("transferCoverageReport", coverageGateSelfTest)
    classpath = files(coverageGateClasses)
    mainClass.set("TransferCoverageGate")
    args(layout.buildDirectory.file("reports/jacoco/transferCoverageReport/transferCoverageReport.xml")
        .get().asFile.absolutePath)
    doFirst {
        val execution = layout.buildDirectory.file("jacoco/testDebugUnitTest.exec").get().asFile
        val report = layout.buildDirectory.file(
            "reports/jacoco/transferCoverageReport/transferCoverageReport.xml").get().asFile
        require(execution.isFile && execution.length() > 0L && report.isFile
            && report.lastModified() >= execution.lastModified()) {
            "Fresh transfer coverage execution data and XML are required."
        }
    }
}

android {
    namespace = "com.vitalis.vitalis_app"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    lint {
        // Flutter regenerates this ignored machine-local file with Windows
        // drive syntax that Android lint misclassifies as an app resource.
        disable += "PropertyEscape"
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.vitalis.vitalis_app"
        minSdk = 28
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    packaging {
        jniLibs {
            // HC-062: preserve extracted-library loading; AGP owns the manifest flag.
            useLegacyPackaging = true
            // Android production is intentionally arm64-only. Some transitive
            // JNI packages publish emulator/32-bit payloads even when the app
            // NDK filter is arm64; exclude those payloads at packaging time.
            excludes += setOf(
                "lib/armeabi-v7a/**",
                "lib/armeabi/**",
                "lib/x86/**",
                "lib/x86_64/**"
            )
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    val workManagerVersion = "2.12.0"
    @Suppress("UNCHECKED_CAST")
    val androidTestVersions = rootProject.extra["vitalisAndroidTestVersions"] as Map<String, String>
    val runnerVersion = androidTestVersions.getValue("androidx.test:runner")
    val junitExtensionVersion = androidTestVersions.getValue("androidx.test.ext:junit")
    constraints {
        // Instrumentation resolves consistently with the app's debug graph,
        // including Flutter integration_test's older transitive test libraries.
        debugImplementation("androidx.test:runner:$runnerVersion")
        debugImplementation("androidx.test.ext:junit:$junitExtensionVersion")
    }
    implementation("androidx.work:work-runtime:$workManagerVersion")
    // WorkManager's Java API exposes ListenableFuture. Flutter's dependency
    // graph selects Guava's empty conflict-avoidance marker, so provide the
    // Android Guava implementation explicitly for the host Java sources.
    implementation("com.google.guava:guava:33.7.2-android")
    testImplementation("junit:junit:4.13.2")
    testImplementation("androidx.test:core:1.7.0")
    testImplementation("androidx.work:work-testing:$workManagerVersion")
    testImplementation("org.robolectric:robolectric:4.17")
    androidTestImplementation("androidx.test:runner:$runnerVersion")
    androidTestImplementation("androidx.test.ext:junit:$junitExtensionVersion")
    androidTestImplementation("androidx.work:work-testing:$workManagerVersion")
}
