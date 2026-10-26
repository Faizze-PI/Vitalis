import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/models/model_descriptor.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/services/model_startup_inspector.dart';

void main() {
  late Directory directory;
  late File primary;
  late String hash;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('vitalis_startup_model_');
    primary = File('${directory.path}/model.gguf');
    await primary.writeAsBytes([71, 71, 85, 70, 1, 2]);
    hash = (await sha256.bind(primary.openRead()).first).toString();
  });
  tearDown(() => directory.delete(recursive: true));

  ModelDescriptor descriptor({
    String id = 'selected',
    String status = 'compatible',
    String? expectedHash,
    int? size,
  }) => ModelDescriptor(
    id: id,
    displayName: 'Fixture',
    source: 'fixture',
    compatibilityStatus: status,
    installationState: 'installed',
    localPath: primary.path,
    sha256: expectedHash ?? hash,
    byteSize: size,
  );

  ModelStartupInspector inspector(
    ModelDescriptor? model, {
    List<Map<String, dynamic>> records = const [],
  }) => ModelStartupInspector(
    findModel: (id) async {
      expect(id, model?.id ?? 'selected');
      return model;
    },
    modelFiles: (_) async => records,
  );

  test(
    'verified selected record matches streamed bytes without mutation',
    () async {
      final model = descriptor(size: 6);
      final before = model.toMap();
      expect(
        await inspector(model).inspect(model.id),
        StartupModelReadiness.ready,
      );
      expect(model.toMap(), before);
      expect(await primary.readAsBytes(), [71, 71, 85, 70, 1, 2]);
    },
  );
  test('missing selected identity never selects another model', () async {
    expect(
      await inspector(null).inspect('selected'),
      StartupModelReadiness.missing,
    );
  });
  test('missing file is distinguished from corruption', () async {
    final model = descriptor();
    await primary.delete();
    expect(
      await inspector(model).inspect(model.id),
      StartupModelReadiness.missing,
    );
  });
  test(
    'pending compatibility cannot become ready through hash alone',
    () async {
      final model = descriptor(status: 'pending_validation');
      expect(
        await inspector(model).inspect(model.id),
        StartupModelReadiness.unknown,
      );
    },
  );
  test('hash and size mismatches remain non-destructive', () async {
    for (final model in [
      descriptor(expectedHash: BundledModelManifest.sha256),
      descriptor(size: 7),
    ]) {
      expect(
        await inspector(model).inspect(model.id),
        StartupModelReadiness.invalid,
      );
    }
    expect(await primary.exists(), isTrue);
  });
  test('bundled identity requires publisher authority', () async {
    final model = descriptor(id: BundledModelManifest.id);
    expect(
      await inspector(model).inspect(model.id),
      StartupModelReadiness.invalid,
    );
  });
  test('malformed stored hash is unknown, not file corruption', () async {
    final model = descriptor(expectedHash: 'bad');
    expect(
      await inspector(model).inspect(model.id),
      StartupModelReadiness.unknown,
    );
  });
  test('registry exception remains unknown without raw diagnostics', () async {
    final subject = ModelStartupInspector(
      findModel: (_) async => throw StateError('private fixture path'),
      modelFiles: (_) async => [],
    );
    expect(await subject.inspect('selected'), StartupModelReadiness.unknown);
  });
  test('incomplete shard set cannot become ready', () async {
    final model = descriptor();
    final rows = [
      {
        'local_path': primary.path,
        'sha256': hash,
        'shard_index': 1,
        'shard_count': 2,
      },
    ];
    expect(
      await inspector(model, records: rows).inspect(model.id),
      StartupModelReadiness.unknown,
    );
  });

  test('file-record hash cannot replace selected primary hash', () async {
    final model = descriptor(expectedHash: BundledModelManifest.sha256);
    final rows = [
      {'local_path': primary.path, 'sha256': hash},
    ];
    expect(
      await inspector(model, records: rows).inspect(model.id),
      isNot(StartupModelReadiness.ready),
    );
  });

  test('single-file I/O failure remains typed unknown', () async {
    final model = descriptor();
    final subject = ModelStartupInspector(
      findModel: (_) async => model,
      modelFiles: (_) async => [],
      files: _UnreadableFiles(),
    );
    expect(await subject.inspect(model.id), StartupModelReadiness.unknown);
  });

  test('primary file rows cannot bypass selected model size', () async {
    final model = descriptor(size: 7);
    final rows = [
      {'local_path': primary.path, 'sha256': hash, 'byte_size': 6},
    ];
    expect(
      await inspector(model, records: rows).inspect(model.id),
      isNot(StartupModelReadiness.ready),
    );
  });

  test('complete split set validates every shard without activating', () async {
    final secondary = File('${directory.path}/second.gguf');
    await secondary.writeAsBytes([71, 71, 85, 70, 3]);
    final secondaryHash = (await sha256.bind(secondary.openRead()).first)
        .toString();
    final rows = [
      {
        'local_path': primary.path,
        'sha256': hash,
        'byte_size': 6,
        'shard_index': 1,
        'shard_count': 2,
      },
      {
        'local_path': secondary.path,
        'sha256': secondaryHash,
        'byte_size': 5,
        'shard_index': 2,
        'shard_count': 2,
      },
    ];
    final model = descriptor(size: 11);
    expect(
      await inspector(model, records: rows).inspect(model.id),
      StartupModelReadiness.ready,
    );
    await secondary.writeAsBytes([0]);
    expect(
      await inspector(model, records: rows).inspect(model.id),
      StartupModelReadiness.invalid,
    );
    await secondary.delete();
    expect(
      await inspector(model, records: rows).inspect(model.id),
      StartupModelReadiness.missing,
    );
    expect(await primary.exists(), isTrue);
  });

  for (final base in [0, 1]) {
    test(
      'complete split readiness uses total budget and index base $base',
      () async {
        final secondary = File('${directory.path}/secondary.gguf');
        await secondary.writeAsBytes([71, 71, 85, 70, 3]);
        final rows = [
          {
            'local_path': primary.path,
            'sha256': hash,
            'byte_size': 6,
            'shard_index': base,
            'shard_count': 2,
          },
          {
            'local_path': secondary.path,
            'sha256': (await sha256.bind(secondary.openRead()).first)
                .toString(),
            'byte_size': 5,
            'shard_index': base + 1,
            'shard_count': 2,
          },
        ];
        expect(
          await inspector(
            descriptor(size: 11),
            records: rows,
          ).inspect('selected'),
          StartupModelReadiness.ready,
        );
        expect(
          await inspector(
            descriptor(size: 6),
            records: rows,
          ).inspect('selected'),
          StartupModelReadiness.unknown,
        );
      },
    );
  }

  for (final fault in [
    'duplicatePath',
    'duplicateIndex',
    'missingIndex',
    'zeroIndex',
    'highIndex',
    'wrongCount',
    'missingPath',
    'missingHash',
  ]) {
    test('malformed split record stays blocked: $fault', () async {
      final secondary = File('${directory.path}/second.gguf');
      await secondary.writeAsBytes(await primary.readAsBytes());
      final second = <String, dynamic>{
        'local_path': secondary.path,
        'sha256': hash,
        'byte_size': 6,
        'shard_index': 2,
        'shard_count': 2,
      };
      expect(
        await inspector(
          descriptor(size: 12),
          records: [
            {
              'local_path': primary.path,
              'sha256': hash,
              'byte_size': 6,
              'shard_index': 1,
              'shard_count': 2,
            },
            Map<String, dynamic>.from(second),
          ],
        ).inspect('selected'),
        StartupModelReadiness.ready,
      );
      switch (fault) {
        case 'duplicatePath':
          second['local_path'] = primary.path;
        case 'duplicateIndex':
          second['shard_index'] = 1;
        case 'missingIndex':
          second.remove('shard_index');
        case 'zeroIndex':
          second['shard_index'] = 0;
        case 'highIndex':
          second['shard_index'] = 3;
        case 'wrongCount':
          second['shard_count'] = 3;
        case 'missingPath':
          second.remove('local_path');
        case 'missingHash':
          second.remove('sha256');
      }
      final model = descriptor(size: 12);
      final rows = [
        <String, dynamic>{
          'local_path': primary.path,
          'sha256': hash,
          'byte_size': 6,
          'shard_index': 1,
          'shard_count': 2,
        },
        second,
      ];
      expect(
        await inspector(model, records: rows).inspect(model.id),
        isNot(StartupModelReadiness.ready),
      );
      expect(await primary.exists(), isTrue);
      expect(await secondary.exists(), isTrue);
    });
  }

  test('unrelated file set cannot replace selected primary', () async {
    final other = File('${directory.path}/other.gguf');
    await other.writeAsBytes(await primary.readAsBytes());
    final model = descriptor();
    final rows = [
      {'local_path': other.path, 'sha256': hash},
    ];
    expect(
      await inspector(model, records: rows).inspect(model.id),
      StartupModelReadiness.unknown,
    );
  });
}

final class _UnreadableFiles implements StartupModelFiles {
  @override
  Future<bool> exists(String path) async => true;
  @override
  Future<int> size(String path) async => 6;
  @override
  Future<String> digest(String path) async =>
      throw const FileSystemException('unavailable');
}
