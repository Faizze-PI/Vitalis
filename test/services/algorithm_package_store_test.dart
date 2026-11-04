import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/algorithm_package_store.dart';

void main() {
  late Directory root;
  late AlgorithmPackageStore store;
  final model = utf8.encode('controlled model fixture');
  Map<String, Object> task({String file = 'model.onnx', String? hash}) => {
    'schema_version': 1,
    'runtime': 'onnx',
    'name': 'My algorithm',
    'description': 'CSV prediction',
    'model': {'file': file, 'sha256': hash ?? sha256.convert(model).toString()},
    'input': {
      'name': 'features',
      'kind': 'csv',
      'dtype': 'float32',
      'shape': [1, 2],
      'header': true,
    },
    'outputs': ['prediction'],
  };
  Future<File> zip(
    Map<String, Object> t, {
    String name = 'model.onnx',
    bool extra = false,
  }) async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('task.json', jsonEncode(t)))
      ..addFile(ArchiveFile(name, model.length, model));
    if (extra) archive.addFile(ArchiveFile('extra.py', 1, [1]));
    final f = File('${root.path}/source.zip');
    await f.writeAsBytes(ZipEncoder().encode(archive));
    return f;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('algorithm-package-');
    store = AlgorithmPackageStore(
      root: () async => Directory('${root.path}/packages'),
      availableBytes: () async => 10000000,
    );
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test(
    'installs one validated package atomically and restores after restart',
    () async {
      final source = await zip(task());
      final before = await source.readAsBytes();
      final result = await store.install(
        source,
        maxModelBytes: 1000,
        maxInputElements: 100,
      );
      expect(result.spec.name, 'My algorithm');
      expect(result.description, 'CSV prediction');
      expect(await store.withModel(result.id, (f) => f.readAsBytes()), model);
      final reopened = AlgorithmPackageStore(
        root: () async => Directory('${root.path}/packages'),
        availableBytes: () async => 10000000,
      );
      expect((await reopened.list()).single.id, result.id);
      expect(await source.readAsBytes(), before);
      expect(
        (await store.install(
          source,
          maxModelBytes: 1000,
          maxInputElements: 100,
        )).id,
        result.id,
      );
    },
  );
  for (final fault in ['traversal', 'extra', 'hash', 'model_budget', 'disk']) {
    test('rejects $fault without replacing an installed package', () async {
      final first = await store.install(
        await zip(task()),
        maxModelBytes: 1000,
        maxInputElements: 100,
      );
      final bad = await zip(
        task(hash: fault == 'hash' ? '0' * 64 : null),
        name: fault == 'traversal' ? '../model.onnx' : 'model.onnx',
        extra: fault == 'extra',
      );
      final installer = fault == 'disk'
          ? AlgorithmPackageStore(
              root: () async => Directory('${root.path}/other'),
              availableBytes: () async => 0,
            )
          : store;
      // Change source identity for budget/disk so this is not a duplicate import.
      if (fault == 'model_budget' || fault == 'disk')
        await bad.writeAsBytes(
          ZipEncoder().encode(
            Archive()
              ..addFile(
                ArchiveFile.string(
                  'task.json',
                  jsonEncode(task()..['description'] = 'another'),
                ),
              )
              ..addFile(ArchiveFile('model.onnx', model.length, model)),
          ),
        );
      await expectLater(
        installer.install(
          bad,
          maxModelBytes: fault == 'model_budget' ? 1 : 1000,
          maxInputElements: 100,
        ),
        throwsA(isA<AlgorithmPackageError>()),
      );
      expect((await store.list()).single.id, first.id);
      expect(await store.withModel(first.id, (f) => f.readAsBytes()), model);
    });
  }
  test('active model lease prevents package removal', () async {
    final item = await store.install(
      await zip(task()),
      maxModelBytes: 1000,
      maxInputElements: 100,
    );
    await store.withModel(item.id, (_) async {
      await expectLater(
        store.remove(item.id),
        throwsA(isA<AlgorithmPackageError>()),
      );
    });
    await store.remove(item.id);
    expect(await store.list(), isEmpty);
  });
  test(
    'removal intent excludes a new reader during asynchronous path checks',
    () async {
      final directory = Directory('${root.path}/race');
      var pauseNext = false;
      final entered = Completer<void>(), release = Completer<void>();
      final racing = AlgorithmPackageStore(
        root: () async {
          if (pauseNext) {
            pauseNext = false;
            entered.complete();
            await release.future;
          }
          return directory;
        },
        availableBytes: () async => 10000000,
      );
      final item = await racing.install(
        await zip(task()),
        maxModelBytes: 1000,
        maxInputElements: 100,
      );
      pauseNext = true;
      final removal = racing.remove(item.id);
      await entered.future;
      try {
        await expectLater(
          racing.withModel(item.id, (_) async => true),
          throwsA(isA<AlgorithmPackageError>()),
        );
      } finally {
        release.complete();
        await removal;
      }
    },
  );
  test('damaged CRC and truncated ZIP never become installed', () async {
    final source = await zip(task());
    final good = await source.readAsBytes();
    for (final truncated in [false, true]) {
      final bytes = List<int>.from(good);
      if (truncated) {
        bytes.removeRange(bytes.length - 12, bytes.length);
      } else {
        final at = List.generate(bytes.length - 4, (i) => i).firstWhere(
          (i) =>
              bytes[i] == 0x50 &&
              bytes[i + 1] == 0x4b &&
              bytes[i + 2] == 1 &&
              bytes[i + 3] == 2,
        );
        bytes[at + 16] ^= 1;
      }
      await source.writeAsBytes(bytes);
      await expectLater(
        store.install(source, maxModelBytes: 1000, maxInputElements: 100),
        throwsA(isA<AlgorithmPackageError>()),
      );
      expect(await store.list(), isEmpty);
    }
  });
  test('duplicate names are rejected before decoding content', () async {
    final source = await zip(task(file: 'aaaa.onnx'), name: 'aaaa.onnx');
    final bytes = await source.readAsBytes();
    final old = utf8.encode('aaaa.onnx'), next = utf8.encode('task.json');
    for (var i = 0; i <= bytes.length - old.length; i++) {
      if (List.generate(
        old.length,
        (n) => bytes[i + n] == old[n],
      ).every((v) => v))
        bytes.setRange(i, i + old.length, next);
    }
    await source.writeAsBytes(bytes);
    await expectLater(
      store.install(source, maxModelBytes: 1000, maxInputElements: 100),
      throwsA(isA<AlgorithmPackageError>()),
    );
    expect(await store.list(), isEmpty);
  });

  test(
    'non-file model entries cannot be leased as executable weights',
    () async {
      final item = await store.install(
        await zip(task()),
        maxModelBytes: 1000,
        maxInputElements: 100,
      );
      final path = '${root.path}/packages/${item.id}/model.blob';
      await File(path).delete();
      await Directory(path).create();
      await expectLater(
        store.withModel(item.id, (f) => f.readAsBytes()),
        throwsA(isA<AlgorithmPackageError>()),
      );
    },
  );
}
