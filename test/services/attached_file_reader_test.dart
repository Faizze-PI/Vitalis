import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/local_file_workspace.dart';
import 'package:vitalis_app/services/attached_file_reader.dart';

void main() {
  late Directory root;
  late LocalFileWorkspace store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vitalis-file-context-');
    store = LocalFileWorkspace(
      root: () async => root,
      availableBytes: () async => 10000000,
    );
  });
  tearDown(() async => root.delete(recursive: true));
  Future<WorkspaceFile> add(String name, String text) {
    final bytes = utf8.encode(text);
    return store.import(
      name: name,
      expectedBytes: bytes.length,
      source: Stream.value(bytes),
    );
  }

  test(
    'reads exact multilingual text and CSV without changing files',
    () async {
      final a = await add('note.txt', 'Local fact: நன்றி 😊'),
          b = await add('data.csv', 'name,value\na,42\n');
      final reader = AttachedFileReader(workspace: store);
      final result = await reader.read([a, b]);
      expect(result.map((f) => f.name), ['note.txt', 'data.csv']);
      expect(result.first.text, 'Local fact: நன்றி 😊');
      expect(result.last.text, 'name,value\na,42\n');
      expect(await store.list(), hasLength(2));
    },
  );
  test('rejects images instead of injecting their bytes as text', () async {
    final file = await add('image.png', 'not text input');
    await expectLater(
      AttachedFileReader(workspace: store).read([file]),
      throwsA(isA<FileAttachmentReadError>()),
    );
  });
  test(
    'hash drift cannot silently change selected conversation context',
    () async {
      final file = await add('note.txt', 'original');
      await store.withFile(file.id, (f) => f.writeAsString('modified'));
      await expectLater(
        AttachedFileReader(workspace: store).read([file]),
        throwsA(isA<FileAttachmentReadError>()),
      );
      expect(await store.list(), isNotEmpty);
    },
  );
  test(
    'processing limit rejects without truncating or deleting full stored file',
    () async {
      final file = await add('large.txt', 'a' * 1025);
      await expectLater(
        AttachedFileReader(workspace: store, maxBytes: 1024).read([file]),
        throwsA(isA<FileAttachmentReadError>()),
      );
      expect((await store.list()).single.bytes, 1025);
    },
  );
}
