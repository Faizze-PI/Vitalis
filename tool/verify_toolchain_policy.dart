import 'dart:convert';
import 'dart:io';

Future<List<String>> verifyGradleBootstrap(
  Map<String, dynamic> policy,
  File jar,
  File checker,
) async {
  final expected = policy['gradleWrapperSha256'];
  if (expected is! String || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expected)) {
    return ['Gradle bootstrap publisher SHA-256 authority is invalid.'];
  }
  final javaHome = Platform.environment['JAVA_HOME'];
  if (javaHome == null || javaHome.isEmpty) {
    return ['JAVA_HOME must explicitly select the pinned JDK.'];
  }
  if (!jar.existsSync() || !checker.existsSync()) {
    return ['Gradle bootstrap or its identity checker is missing.'];
  }
  final java = File('$javaHome/bin/java${Platform.isWindows ? '.exe' : ''}');
  if (!java.existsSync()) return ['Selected JDK executable is missing.'];
  final result = await Process.run(java.path, [
    checker.absolute.path,
    expected,
    jar.absolute.path,
  ]);
  return result.exitCode == 0
      ? []
      : ['Gradle bootstrap publisher identity verification failed.'];
}

/// Checks the effective declarations maintained in this repository. Installed
/// SDK validation and artifact inspection are separate gates.
List<String> verifyAndroidDeclarations(
  Map<String, dynamic> policy,
  String gradle,
  String wrapper,
) {
  final failures = <String>[];
  for (final key in ['sourceCompatibility', 'targetCompatibility']) {
    final values = RegExp(
      '^\\s*$key\\s*=\\s*JavaVersion.VERSION_(\\d+)\\s*\$',
      multiLine: true,
    ).allMatches(gradle).map((match) => match[1]).toList();
    if (values.length != 1 || values.single != '${policy['javaBytecode']}') {
      failures.add('$key differs from Java bytecode policy.');
    }
  }
  final kotlinTargets = RegExp(
    r'jvmTarget\.set\(JvmTarget\.JVM_(\d+)\)',
  ).allMatches(gradle).map((match) => match[1]).toList();
  if (kotlinTargets.length != 1 ||
      kotlinTargets.single != '${policy['javaBytecode']}') {
    failures.add('Kotlin bytecode target differs from Java bytecode policy.');
  }
  for (final key in ['compileSdk', 'targetSdk', 'minSdk']) {
    final values = RegExp(
      '^\\s*$key\\s*=\\s*(\\d+)\\s*\$',
      multiLine: true,
    ).allMatches(gradle).map((match) => match[1]).toList();
    if (values.length != 1 || values.single != '${policy[key]}') {
      failures.add('$key must equal ${policy[key]} exactly once.');
    }
  }
  final ndks = RegExp(
    r'^\s*ndkVersion\s*=\s*"([^"]+)"\s*$',
    multiLine: true,
  ).allMatches(gradle).map((match) => match[1]).toList();
  if (ndks.length != 1 || ndks.single != policy['ndk']) {
    failures.add('NDK declaration differs from toolchain policy.');
  }
  final abis = RegExp(
    r'abiFilters\s*\+=\s*listOf\(([^)]*)\)',
  ).allMatches(gradle).map((match) => match[1]!.trim()).toList();
  if (abis.length != 1 || abis.single != '"${policy['androidAbi']}"') {
    failures.add('Android ABI declaration must contain only the policy ABI.');
  }
  final urls = RegExp(
    r'^distributionUrl=(.+)$',
    multiLine: true,
  ).allMatches(wrapper).map((match) => match[1]!.trim()).toList();
  final expected =
      'https\\://services.gradle.org/distributions/gradle-${policy['gradle']}-bin.zip';
  if (urls.length != 1 || urls.single != expected) {
    failures.add('Gradle wrapper differs from toolchain policy.');
  }
  final expectedHash = policy['gradleDistributionSha256'];
  final hashes = RegExp(
    r'^distributionSha256Sum=(.*)$',
    multiLine: true,
  ).allMatches(wrapper).map((match) => match[1]!.trim()).toList();
  if (expectedHash is! String ||
      !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expectedHash) ||
      hashes.length != 1 ||
      hashes.single.toLowerCase() != expectedHash.toLowerCase()) {
    failures.add('Gradle distribution checksum differs from publisher policy.');
  }
  final timeout = policy['gradleNetworkTimeoutMillis'];
  final timeouts = RegExp(
    r'^networkTimeout=(.*)$',
    multiLine: true,
  ).allMatches(wrapper).map((match) => match[1]!.trim()).toList();
  if (timeout is! int ||
      timeout <= 0 ||
      timeouts.length != 1 ||
      timeouts.single != '$timeout') {
    failures.add(
      'Gradle network timeout differs from bounded transport policy.',
    );
  }
  return failures;
}

Future<void> main(List<String> arguments) async {
  final root = File.fromUri(Platform.script).parent.parent;
  final policy =
      jsonDecode(
            await File(
              '${root.path}/tool/toolchain_policy.json',
            ).readAsString(),
          )
          as Map<String, dynamic>;
  if (arguments.length == 2 && arguments.first == '--value') {
    if (!policy.containsKey(arguments[1])) {
      stderr.writeln('Unknown toolchain policy key.');
      exitCode = 2;
      return;
    }
    stdout.writeln(policy[arguments[1]]);
    return;
  }
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: verify_toolchain_policy.dart [--value key]');
    exitCode = 2;
    return;
  }
  final failures = verifyAndroidDeclarations(
    policy,
    await File('${root.path}/android/app/build.gradle.kts').readAsString(),
    await File(
      '${root.path}/android/gradle/wrapper/gradle-wrapper.properties',
    ).readAsString(),
  );
  failures.addAll(
    await verifyGradleBootstrap(
      policy,
      File('${root.path}/android/gradle/wrapper/gradle-wrapper.jar'),
      File('${root.path}/tool/VerifyGradleBootstrap.java'),
    ),
  );
  if (failures.isNotEmpty) {
    failures.forEach(stderr.writeln);
    exitCode = 1;
  } else {
    stdout.writeln('Android declarations match toolchain policy.');
  }
}
