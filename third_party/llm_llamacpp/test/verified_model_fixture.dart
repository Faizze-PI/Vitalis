import 'dart:io';

import 'package:crypto/crypto.dart';

/// Test-only authority supplied by the application's manifest-exporting runner.
/// Never derive expected authority from the file being verified.
Future<String> verifiedModelFixture({Map<String, String>? environment}) async {
  final values = environment ?? Platform.environment;
  final path = values['VITALIS_TEST_MODEL'];
  if (path == null || path.isEmpty) {
    throw StateError('nativeFixturePathRequired');
  }
  final expected = values['VITALIS_TEST_MODEL_SHA256'];
  if (expected == null || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expected)) {
    throw StateError('nativeFixturePublisherHashRequired');
  }
  late String actual;
  try {
    actual = (await sha256.bind(File(path).openRead()).first).toString();
  } on FileSystemException {
    throw StateError('nativeFixtureUnreadable');
  }
  if (actual != expected.toLowerCase()) {
    throw StateError('nativeFixtureHashMismatch');
  }
  return path;
}
