import 'dart:convert';
import 'dart:io';

import 'verify_gate_environment.dart' show canonicalDirectory;

/// Checks Flutter's effective selection without changing global configuration.
List<String> verifyFlutterSelection(
  String configuration,
  Map<String, String> environment,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(configuration);
  } on FormatException {
    return ['Flutter configuration is not valid JSON.'];
  }
  if (decoded is! Map<String, dynamic>) {
    return ['Flutter configuration must be an object.'];
  }
  final failures = <String>[];
  for (final entry in {
    'jdk-dir': 'JAVA_HOME',
    'android-sdk': 'ANDROID_HOME',
  }.entries) {
    final selected = decoded[entry.key];
    final expected = environment[entry.value];
    if (selected is! String || selected.isEmpty || expected == null) {
      failures.add('Flutter ${entry.key} or ${entry.value} is missing.');
      continue;
    }
    try {
      if (canonicalDirectory(selected) != canonicalDirectory(expected)) {
        failures.add(
          'Flutter ${entry.key} conflicts with ${entry.value}; '
          'inspect Flutter configuration before building.',
        );
      }
    } on FileSystemException {
      failures.add('Flutter ${entry.key} must select an existing directory.');
    }
  }
  return failures;
}

Future<void> main() async {
  final failures = verifyFlutterSelection(
    await stdin.transform(utf8.decoder).join(),
    Platform.environment,
  );
  if (failures.isNotEmpty) {
    for (final failure in failures) {
      stderr.writeln(failure);
    }
    exitCode = 2;
    return;
  }
  stdout.writeln('Flutter effective JDK/SDK selection passed.');
}
