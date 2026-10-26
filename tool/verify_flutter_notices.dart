import 'dart:convert';
import 'dart:io';

/// Checks the inference dependencies implicated by OC-214, not all licenses.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    throw ArgumentError('Expected APK and AAB paths.');
  }
  final root = File.fromUri(Platform.script).parent.parent;
  final config = File('${root.path}/.dart_tool/package_config.json');
  final packages =
      (jsonDecode(await config.readAsString()) as Map)['packages'] as List;
  final licenses = <String>[];
  for (final name in ['llm_core', 'llm_llamacpp']) {
    final package = packages.cast<Map>().singleWhere((p) => p['name'] == name);
    final uri = config.uri.resolve(package['rootUri'] as String);
    final directory = Directory.fromUri(uri);
    final license = File('${directory.path}/LICENSE');
    if (!license.existsSync()) {
      throw StateError('Required inference source license unavailable: $name');
    }
    licenses.addAll([name, license.path]);
  }
  final javaHome = Platform.environment['JAVA_HOME'];
  if (javaHome == null) throw StateError('Pinned JAVA_HOME is required.');
  for (var index = 0; index < arguments.length; index++) {
    final process = await Process.start(
      '$javaHome/bin/java${Platform.isWindows ? '.exe' : ''}',
      [
        '${root.path}/tool/VerifyFlutterNotices.java',
        arguments[index],
        index == 0 ? 'apk' : 'aab',
        ...licenses,
      ],
      mode: ProcessStartMode.inheritStdio,
    );
    final code = await process.exitCode;
    if (code != 0) {
      exitCode = code;
      return;
    }
  }
}
