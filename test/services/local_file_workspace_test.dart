import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/local_file_workspace.dart';

void main() {
  late Directory root;
  late LocalFileWorkspace workspace;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vitalis-input-test-');
    workspace = LocalFileWorkspace(
      root: () async => root,
      availableBytes: () async => 100000,
    );
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'active input readers prevent removal until their work settles',
    () async {
      final item = await workspace.import(
        name: 'x',
        expectedBytes: 1,
        source: Stream.value([7]),
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      final reading = workspace.withFile(item.id, (file) async {
        entered.complete();
        await release.future;
        return file.length();
      });
      await entered.future;
      await expectLater(
        workspace.remove(item.id),
        throwsA(isA<WorkspaceImportException>()),
      );
      release.complete();
      expect(await reading, 1);
      await workspace.remove(item.id);
      expect(await workspace.list(), isEmpty);
    },
  );

  test('copies any file type, streams hash and restores metadata', () async {
    final item = await workspace.import(
      name: '../../sample.csv',
      expectedBytes: 4,
      source: Stream.value([49, 44, 50, 10]),
    );
    expect(item.name, 'sample.csv');
    expect(item.bytes, 4);
    expect(item.sha256.length, 64);
    expect((await workspace.list()).single.id, item.id);
    expect(await (await workspace.file(item.id)).readAsString(), '1,2\n');
  });
  for (final bytes in [2, 5]) {
    test('rejects incorrect stream length $bytes without installing', () async {
      await expectLater(
        workspace.import(
          name: 'x.bin',
          expectedBytes: 4,
          source: Stream.value(List.filled(bytes, 0)),
        ),
        throwsA(isA<WorkspaceImportException>()),
      );
      expect(await workspace.list(), isEmpty);
      expect(await root.list().toList(), isEmpty);
    });
  }
  test('storage shortage fails before reading source', () async {
    workspace = LocalFileWorkspace(
      root: () async => root,
      availableBytes: () async => 0,
    );
    var read = false;
    Stream<List<int>> source() async* {
      read = true;
      yield [1];
    }

    await expectLater(
      workspace.import(name: 'x', expectedBytes: 1, source: source()),
      throwsA(isA<WorkspaceImportException>()),
    );
    expect(read, isFalse);
  });
  test('failed source does not alter a previously imported file', () async {
    final old = await workspace.import(
      name: 'old.bin',
      expectedBytes: 1,
      source: Stream.value([7]),
    );
    await expectLater(
      workspace.import(
        name: 'new.bin',
        expectedBytes: 1,
        source: Stream.error(StateError('read failed')),
      ),
      throwsA(isA<WorkspaceImportException>()),
    );
    expect((await workspace.list()).single.id, old.id);
    expect(await (await workspace.file(old.id)).readAsBytes(), [7]);
  });
  test('remove deletes only the requested controlled copy', () async {
    final a = await workspace.import(
      name: 'a',
      expectedBytes: 1,
      source: Stream.value([1]),
    );
    final b = await workspace.import(
      name: 'b',
      expectedBytes: 1,
      source: Stream.value([2]),
    );
    await workspace.remove(a.id);
    expect((await workspace.list()).single.id, b.id);
    await expectLater(workspace.remove('../outside'), throwsArgumentError);
  });
  test(
    'identity collision never cleans up the existing imported file',
    () async {
      workspace = LocalFileWorkspace(
        root: () async => root,
        availableBytes: () async => 100000,
        nextIdentity: () => 'a' * 32,
      );
      final first = await workspace.import(
        name: 'first',
        expectedBytes: 1,
        source: Stream.value([7]),
      );
      await expectLater(
        workspace.import(
          name: 'second',
          expectedBytes: 1,
          source: Stream.value([9]),
        ),
        throwsA(isA<WorkspaceImportException>()),
      );
      expect(await (await workspace.file(first.id)).readAsBytes(), [7]);
    },
  );
}
