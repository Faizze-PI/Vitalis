import 'dart:convert';
import 'dart:io';

bool sameDirectoryPath(String first, String second) {
  String normalize(String value) {
    final uri = Directory(value).absolute.uri.normalizePath().toString();
    return Platform.isWindows ? uri.toLowerCase() : uri;
  }

  return normalize(first) == normalize(second);
}

String canonicalDirectory(String path) {
  final result = Directory(path).resolveSymbolicLinksSync();
  return Platform.isWindows ? result.toLowerCase() : result;
}

/// Reject escapes through '..', junctions or symlinks, even before the cache
/// directory exists. No deletion or relocation is performed by this check.
bool withinWorkspace(String root, String path) {
  if (path.split(RegExp(r'[\\/]')).contains('..')) return false;
  var directory = Directory.fromUri(
    Directory(path).absolute.uri.normalizePath(),
  );
  if (directory.existsSync() &&
      canonicalDirectory(directory.path) == canonicalDirectory(root)) {
    return false;
  }
  while (!directory.existsSync()) {
    final parent = directory.parent;
    if (parent.path == directory.path) return false;
    directory = parent;
  }
  final resolvedRoot = canonicalDirectory(root);
  final resolvedParent = canonicalDirectory(directory.path);
  return resolvedParent == resolvedRoot ||
      resolvedParent.startsWith('$resolvedRoot${Platform.pathSeparator}');
}

List<String> verifyEnvironment(
  Map<String, dynamic> policy,
  String root,
  Map<String, String> environment,
  String localProperties,
) {
  final failures = <String>[];
  for (final entry in {
    'PUB_CACHE': 'VITALIS_PUB_CACHE',
    'GRADLE_USER_HOME': 'VITALIS_GRADLE_CACHE',
  }.entries) {
    final selected = environment[entry.key];
    if (selected == null || !withinWorkspace(root, selected)) {
      failures.add('${entry.key} must be inside this checkout.');
    }
    final override = environment[entry.value];
    if (override != null &&
        (selected == null ||
            !withinWorkspace(root, override) ||
            !sameDirectoryPath(selected, override))) {
      failures.add('${entry.value} conflicts with ${entry.key}.');
    }
  }
  final sdk = environment['ANDROID_HOME'];
  if (sdk == null || !Directory(sdk).existsSync()) {
    failures.add('ANDROID_HOME must explicitly select an installed SDK.');
    return failures;
  }
  final selectedSdk = canonicalDirectory(sdk);
  final secondary = environment['ANDROID_SDK_ROOT'];
  if (secondary != null &&
      (!Directory(secondary).existsSync() ||
          canonicalDirectory(secondary) != selectedSdk)) {
    failures.add('ANDROID_SDK_ROOT conflicts with ANDROID_HOME.');
  }
  final local = RegExp(r'^sdk\.dir=(.+)$', multiLine: true)
      .firstMatch(localProperties)?[1]
      ?.trim()
      .replaceAll(r'\\', r'\')
      .replaceAll(r'\:', ':');
  if (local != null &&
      (!Directory(local).existsSync() ||
          canonicalDirectory(local) != selectedSdk)) {
    failures.add(
      'android/local.properties sdk.dir conflicts with ANDROID_HOME.',
    );
  }
  if (!File(
    '$sdk/platforms/android-${policy['compileSdk']}/android.jar',
  ).existsSync()) {
    failures.add('Required compile SDK platform is missing.');
  }
  final ndk = File('$sdk/ndk/${policy['ndk']}/source.properties');
  if (!ndk.existsSync() ||
      !RegExp(
        '^Pkg.Revision\\s*=\\s*${RegExp.escape(policy['ndk'] as String)}\\s*\$',
        multiLine: true,
      ).hasMatch(ndk.readAsStringSync())) {
    failures.add('Required NDK is missing or has a different revision.');
  }
  return failures;
}

void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    if (arguments.length != 3 || arguments.first != '--same-directory') {
      exitCode = 2;
      return;
    }
    exitCode = sameDirectoryPath(arguments[1], arguments[2]) ? 0 : 2;
    return;
  }
  final root = File.fromUri(Platform.script).parent.parent.path;
  final policy =
      jsonDecode(File('$root/tool/toolchain_policy.json').readAsStringSync())
          as Map<String, dynamic>;
  final local = File('$root/android/local.properties');
  final failures = verifyEnvironment(
    policy,
    root,
    Platform.environment,
    local.existsSync() ? local.readAsStringSync() : '',
  );
  if (failures.isNotEmpty) {
    failures.forEach(stderr.writeln);
    exitCode = 2;
  } else {
    stdout.writeln('Installed SDK/NDK and cache configuration passed.');
  }
}
