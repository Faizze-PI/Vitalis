import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_flutter_selection.dart';

void main() {
  late Directory sandbox;
  late Map<String, String> environment;
  late Map<String, String> configuration;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('flutter selection ');
    final jdk = Directory('${sandbox.path}/selected jdk')..createSync();
    final sdk = Directory('${sandbox.path}/selected sdk')..createSync();
    environment = {'JAVA_HOME': jdk.path, 'ANDROID_HOME': sdk.path};
    configuration = {'jdk-dir': jdk.path, 'android-sdk': sdk.path};
  });
  tearDown(() => sandbox.deleteSync(recursive: true));

  test('accepts matching effective selections with spaces', () {
    expect(
      verifyFlutterSelection(jsonEncode(configuration), environment),
      isEmpty,
    );
  });
  for (final key in ['jdk-dir', 'android-sdk']) {
    test('rejects effective $key override despite correct environment', () {
      configuration[key] = sandbox.path;
      expect(
        verifyFlutterSelection(jsonEncode(configuration), environment),
        isNotEmpty,
      );
    });
    test('rejects missing effective $key', () {
      configuration.remove(key);
      expect(
        verifyFlutterSelection(jsonEncode(configuration), environment),
        isNotEmpty,
      );
    });
  }
  test('rejects malformed or non-object configuration', () {
    for (final value in ['invalid', '[]', 'null']) {
      expect(verifyFlutterSelection(value, environment), isNotEmpty);
    }
  });
  test('rejects nonexistent selected directory', () {
    configuration['jdk-dir'] = '${sandbox.path}/missing';
    expect(
      verifyFlutterSelection(jsonEncode(configuration), environment),
      isNotEmpty,
    );
  });
}
