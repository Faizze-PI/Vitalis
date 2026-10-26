import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/validate_flutter_version.dart';

void main() {
  String? validate(String value) =>
      validateFlutterVersion(value, '3.44.7', '3.12.2');

  test('accepts compact and pretty machine JSON in any key order', () {
    final versions = {
      'dartSdkVersion': '3.12.2 (stable) (Tue Jun 9 2026)',
      'frameworkVersion': '3.44.7',
    };
    expect(validate(jsonEncode(versions)), isNull);
    expect(
      validate(const JsonEncoder.withIndent('  ').convert(versions)),
      isNull,
    );
    versions['dartSdkVersion'] = '3.12.2';
    expect(validate(jsonEncode(versions)), isNull);
  });

  test('rejects malformed and missing version data', () {
    for (final value in ['not JSON', '[]', 'null', '{}']) {
      expect(validate(value), isNotNull, reason: value);
    }
  });

  test('rejects wrong SDKs, prefix matches, prereleases and wrong types', () {
    for (final dart in ['3.12.20', '3.12.2-beta', '3.12.2 unexpected', 3122]) {
      expect(
        validate(
          jsonEncode({'frameworkVersion': '3.44.7', 'dartSdkVersion': dart}),
        ),
        isNotNull,
        reason: '$dart',
      );
    }
    expect(
      validate(
        jsonEncode({'frameworkVersion': '3.44.70', 'dartSdkVersion': '3.12.2'}),
      ),
      isNotNull,
    );
  });
}
