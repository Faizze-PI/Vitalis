import 'dart:convert';
import 'dart:io';

/// Verifies the package-to-library contract used by generated FFI bindings.
void verifyNativeAssetManifest(Object? manifest) {
  if (manifest is! Map || jsonEncode(manifest['format-version']) != '[1,0,0]') {
    throw const FormatException('Unsupported Native Assets manifest schema');
  }
  final platforms = manifest['native-assets'];
  final assets = platforms is Map ? platforms['android_arm64'] : null;
  if (assets is! Map) {
    throw const FormatException('Missing Android arm64 native assets');
  }
  // HC-069: These names are the packaged ABI contract, not user configuration.
  const expected = {
    'package:llm_llamacpp/llama.dart': 'libllama.so',
    'package:llm_llamacpp/native/libggml.so': 'libggml.so',
    'package:llm_llamacpp/native/libggml-base.so': 'libggml-base.so',
    'package:llm_llamacpp/native/libggml-cpu.so': 'libggml-cpu.so',
  };
  for (final entry in expected.entries) {
    final value = assets[entry.key];
    if (value is! List ||
        value.length != 2 ||
        value[0] != 'absolute' ||
        value[1] != entry.value) {
      throw const FormatException('Required native binding mapping is invalid');
    }
  }
  if (assets.keys.any(
    (key) => key is! String || key.contains('package:llm_llamacpp/package:'),
  )) {
    throw const FormatException('Invalid native asset identity');
  }
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2 || !['apk', 'aab'].contains(arguments[1])) {
    throw ArgumentError('Expected archive path and apk|aab');
  }
  final javaHome = Platform.environment['JAVA_HOME'];
  if (javaHome == null) throw StateError('Pinned JAVA_HOME is required');
  final java = '$javaHome/bin/java${Platform.isWindows ? '.exe' : ''}';
  final result = await Process.run(java, [
    File.fromUri(
      Platform.script.resolve('VerifyAndroidNativeInventory.java'),
    ).path,
    '--manifest',
    ...arguments,
  ]);
  if (result.exitCode != 0) {
    throw StateError('Native Assets manifest extraction failed');
  }
  verifyNativeAssetManifest(jsonDecode(result.stdout as String));
  stdout.writeln('Canonical native asset bindings verified: ${arguments[1]}');
}
