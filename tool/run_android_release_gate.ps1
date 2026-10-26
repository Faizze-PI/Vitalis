param()

$ErrorActionPreference = 'Stop'
$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$FlutterRoot = if ($env:VITALIS_FLUTTER_SDK) { $env:VITALIS_FLUTTER_SDK } else { Join-Path $RepositoryRoot '.fvm\flutter_sdk' }
$Dart = Join-Path $FlutterRoot 'bin\cache\dart-sdk\bin\dart.exe'
if (-not $env:VITALIS_GENERATION_TOKEN) {
    & $Dart (Join-Path $PSScriptRoot 'generation_lock.dart') -- `
        (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $PSCommandPath
    exit $LASTEXITCODE
}
& $Dart (Join-Path $PSScriptRoot 'generation_lock.dart') --verify
if ($LASTEXITCODE -ne 0) { throw 'Checkout ownership verification failed.' }
& (Join-Path $PSScriptRoot 'TestReleaseAbiCollection.ps1')

try {
    & (Join-Path $PSScriptRoot 'run_gate.ps1') build apk --release --target-platform android-arm64
    if ($LASTEXITCODE -ne 0) { throw 'Unsigned release APK build failed.' }

    $Registrant = Join-Path $RepositoryRoot 'android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java'
    if ((Get-Content -LiteralPath $Registrant -Raw) -match 'integration_test') {
        throw 'Release registrant contains the development-only integration_test plugin.'
    }

    $env:GRADLE_USER_HOME = if ($env:VITALIS_GRADLE_CACHE) {
        $env:VITALIS_GRADLE_CACHE
    } else {
        Join-Path $RepositoryRoot '.gate-cache\gradle'
    }
    & (Join-Path $RepositoryRoot 'android\gradlew.bat') -p (Join-Path $RepositoryRoot 'android') lintRelease
    if ($LASTEXITCODE -ne 0) { throw 'Release lint failed.' }

    & (Join-Path $PSScriptRoot 'run_gate.ps1') build appbundle --release --target-platform android-arm64
    if ($LASTEXITCODE -ne 0) { throw 'Unsigned release AAB build failed.' }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Apk = Join-Path $RepositoryRoot 'build\app\outputs\flutter-apk\app-release.apk'
    $Aab = Join-Path $RepositoryRoot 'build\app\outputs\bundle\release\app-release.aab'
    foreach ($Artifact in @($Apk, $Aab)) {
        if (-not (Test-Path -LiteralPath $Artifact)) { throw "Missing artifact: $Artifact" }
        $Archive = [IO.Compression.ZipFile]::OpenRead($Artifact)
        try {
            $Names = @($Archive.Entries.FullName)
            if ($Names -match '(^|/)([^/]+\.gguf|[^/]+\.(jks|keystore)|key\.properties)$') {
                throw "Prohibited payload in $Artifact"
            }
            if ($Artifact -eq $Apk) {
                $NativeAbis = @($Names |
                    Where-Object { $_ -match '^lib/[^/]+/[^/]+\.so$' } |
                    ForEach-Object { ($_ -split '/')[1] } |
                    Sort-Object -Unique)
                if (@($NativeAbis).Count -ne 1 -or $NativeAbis[0] -ne 'arm64-v8a') {
                    throw "Release APK ABI set is not exactly arm64-v8a: $NativeAbis"
                }
                foreach ($Library in @('libllama.so', 'libggml.so', 'libggml-base.so', 'libggml-cpu.so')) {
                    if (-not ($Names -contains "lib/arm64-v8a/$Library")) {
                        throw "Missing required release native library: $Library"
                    }
                }
            }
        } finally {
            $Archive.Dispose()
        }
    }

    $VerifierClasses = Join-Path $RepositoryRoot 'build\tool\unsigned-artifacts'
    New-Item -ItemType Directory -Force $VerifierClasses | Out-Null
    & (Join-Path $env:JAVA_HOME 'bin\javac.exe') -d $VerifierClasses `
        (Join-Path $PSScriptRoot 'VerifyUnsignedArtifacts.java') `
        (Join-Path $PSScriptRoot 'VerifyUnsignedArtifactsTest.java') `
        (Join-Path $PSScriptRoot 'VerifyAndroidNativeInventory.java') `
        (Join-Path $PSScriptRoot 'VerifyAndroidNativeInventoryTest.java') `
        (Join-Path $PSScriptRoot 'VerifyFlutterNotices.java') `
        (Join-Path $PSScriptRoot 'VerifyFlutterNoticesTest.java')
    if ($LASTEXITCODE -ne 0) { throw 'Unsigned archive verifier compilation failed.' }
    & (Join-Path $env:JAVA_HOME 'bin\java.exe') -cp $VerifierClasses VerifyUnsignedArtifactsTest
    if ($LASTEXITCODE -ne 0) { throw 'Unsigned archive verifier self-test failed.' }
    & (Join-Path $env:JAVA_HOME 'bin\java.exe') -cp $VerifierClasses VerifyUnsignedArtifacts $Apk $Aab
    if ($LASTEXITCODE -ne 0) { throw 'Unsigned release archive verification failed.' }
    & (Join-Path $env:JAVA_HOME 'bin\java.exe') -cp $VerifierClasses VerifyAndroidNativeInventoryTest
    if ($LASTEXITCODE -ne 0) { throw 'Native inventory verifier self-test failed.' }
    & (Join-Path $env:JAVA_HOME 'bin\java.exe') -cp $VerifierClasses VerifyAndroidNativeInventory $Apk $Aab
    if ($LASTEXITCODE -ne 0) { throw 'Release native inventory verification failed.' }
    & $Dart (Join-Path $PSScriptRoot 'verify_native_asset_manifest.dart') $Apk apk
    if ($LASTEXITCODE -ne 0) { throw 'APK native asset binding verification failed.' }
    & $Dart (Join-Path $PSScriptRoot 'verify_native_asset_manifest.dart') $Aab aab
    if ($LASTEXITCODE -ne 0) { throw 'AAB native asset binding verification failed.' }
    & (Join-Path $env:JAVA_HOME 'bin\java.exe') -cp $VerifierClasses VerifyFlutterNoticesTest
    if ($LASTEXITCODE -ne 0) { throw 'Flutter notices verifier self-test failed.' }
    & $Dart (Join-Path $PSScriptRoot 'verify_flutter_notices.dart') $Apk $Aab
    if ($LASTEXITCODE -ne 0) { throw 'Required inference dependency notices verification failed.' }

    Get-FileHash $Apk, $Aab -Algorithm SHA256 |
        Select-Object Path, Hash
} finally {
    # The outer generation-lock process releases only after this script exits.
}
