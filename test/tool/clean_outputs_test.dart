import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/verify_clean_outputs.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('vitalis clean '));
  tearDown(() => root.deleteSync(recursive: true));

  test('clean checkout passes without deleting retained source or cache', () {
    File('${root.path}/pubspec.lock').writeAsStringSync('retained');
    Directory('${root.path}/.gate-cache').createSync();
    expect(remainingCleanOutputs(root), isEmpty);
    expect(File('${root.path}/pubspec.lock').readAsStringSync(), 'retained');
  });

  for (final name in [
    'build',
    '.dart_tool',
    '.flutter-plugins',
    '.flutter-plugins-dependencies',
  ]) {
    test('leftover $name rejects clean success without deleting it', () {
      final file = File('${root.path}/$name')..writeAsStringSync('leftover');
      expect(remainingCleanOutputs(root), contains(name));
      expect(file.readAsStringSync(), 'leftover');
    });
  }
}
