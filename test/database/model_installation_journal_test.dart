import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/constants/app_constants.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/database/model_installation_journal.dart';
import 'package:vitalis_app/models/model_descriptor.dart';
import 'package:vitalis_app/models/model_installation.dart';

void main() {
  final storage = DatabaseHelper.instance;
  final firstHash = 'a' * 64;
  final secondHash = 'b' * 64;
  late Directory sandbox;
  late ModelInstallationJournal journal;
  late Map<String, dynamic> before;
  late List<InstallationShard> shards;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    sandbox = await Directory.systemTemp.createTemp('vitalis_journal_store_');
    await databaseFactory.setDatabasesPath(sandbox.path);
  });
  setUp(() async {
    await storage.close();
    await databaseFactory.deleteDatabase(
      p.join(sandbox.path, AppConstants.databaseName),
    );
    await storage.upsertModel({
      'id': 'fixture',
      'display_name': 'Disposable split model',
      'source': 'huggingface',
      'local_path': 'old-primary.gguf',
      'sha256': firstHash,
      'byte_size': 24,
      'repository': 'publisher/fixture',
      'revision': 'immutable',
      'compatibility_status': 'compatible',
      'installation_state': 'installed',
    });
    before = (await storage.getModel('fixture'))!;
    journal = ModelInstallationJournal(
      database: () => storage.database,
      clock: () => DateTime.utc(2026, 10, 15),
    );
    shards = [
      for (var index = 0; index < 2; index++)
        InstallationShard(
          index: index,
          count: 2,
          fileName: 'model-$index.gguf',
          byteSize: 12,
          stagingPath: 'job-staging/model-$index.part',
          finalPath: 'job-final/model-$index.gguf',
          expectedSha256: index == 0 ? firstHash : secondHash,
          hashAuthority: ModelHashAuthority.publisherSha256,
          entityTag: 'immutable-entity-$index',
        ),
    ];
  });
  tearDownAll(() async {
    await storage.close();
    await sandbox.delete(recursive: true);
  });

  Future<InstallationSnapshot> begin() => journal.begin(
    operationId: 'operation',
    modelId: 'fixture',
    shards: shards,
    jobId: 'job',
  );
  ModelDescriptor validated() => ModelDescriptor.fromMap({
    ...before,
    'local_path': shards.first.finalPath,
  });
  Future<InstallationSnapshot> prepareProjection() async {
    var state = await begin();
    state = await journal.startValidation(state.operationId, state.revision);
    for (final shard in shards) {
      state = await journal.validateShard(
        state.operationId,
        state.revision,
        index: shard.index,
        byteSize: shard.byteSize,
        sha256: shard.expectedSha256!,
      );
    }
    state = await journal.ready(state.operationId, state.revision, validated());
    state = await journal.startProjection(state.operationId, state.revision);
    for (final shard in shards) {
      state = await journal.markMoved(
        state.operationId,
        state.revision,
        shard.index,
      );
    }
    return state;
  }

  test(
    'intent persists across reopening without changing installed model',
    () async {
      final state = await begin();
      expect(state.phase, InstallationPhase.staging);
      expect(await storage.getModel('fixture'), before);
      await storage.close();
      final restored = await journal.read(state.operationId);
      expect(restored.row, state.row);
      expect(restored.shards, state.shards);
      expect((await journal.pending()).single.operationId, state.operationId);
      expect(() => restored.row['phase'] = 'installed', throwsUnsupportedError);
      expect(() => restored.shards.first['moved'] = 1, throwsUnsupportedError);
    },
  );

  test('duplicate owners and stale state revisions are rejected', () async {
    final state = await begin();
    await expectLater(begin(), throwsA(isA<InstallationConflict>()));
    await expectLater(
      journal.begin(
        operationId: 'competitor',
        modelId: 'fixture',
        shards: shards,
      ),
      throwsA(isA<InstallationConflict>()),
    );
    await journal.startValidation(state.operationId, state.revision);
    await expectLater(
      journal.startValidation(state.operationId, state.revision),
      throwsA(isA<InstallationConflict>()),
    );
    expect(await storage.getModel('fixture'), before);
  });

  test('wrong hash or size cannot validate or activate a shard set', () async {
    var state = await begin();
    state = await journal.startValidation(state.operationId, state.revision);
    for (final size in [11, 12]) {
      await expectLater(
        journal.validateShard(
          state.operationId,
          state.revision,
          index: 0,
          byteSize: size,
          sha256: secondHash,
        ),
        throwsA(isA<InstallationConflict>()),
      );
    }
    await expectLater(
      journal.ready(state.operationId, state.revision, validated()),
      throwsA(isA<InstallationConflict>()),
    );
    expect((await journal.read(state.operationId)).revision, state.revision);
    expect(await storage.getModel('fixture'), before);
  });

  test(
    'complete projection atomically installs all shards and retains hash authority',
    () async {
      final state = await prepareProjection();
      expect(await storage.getModel('fixture'), before);
      final installed = await journal.commit(state.operationId, state.revision);
      expect(installed.phase, InstallationPhase.installed);
      expect(await journal.pending(), isEmpty);
      expect(
        (await storage.getModel('fixture'))!['local_path'],
        shards.first.finalPath,
      );
      final files = await storage.getModelFiles('fixture');
      expect(files.map((f) => f['local_path']), shards.map((s) => s.finalPath));
      expect(installed.shards.first['expected_sha256'], firstHash);
      expect(installed.shards.first['actual_sha256'], firstHash);
      expect(installed.shards.first['hash_authority'], 'publisherSha256');
      expect(files.map((f) => f['etag']), [
        'immutable-entity-0',
        'immutable-entity-1',
      ]);
    },
  );

  test('stale installed identity blocks projection', () async {
    final state = await prepareProjection();
    await storage.upsertModel({...before, 'local_path': 'newer-owner.gguf'});
    await expectLater(
      journal.commit(state.operationId, state.revision),
      throwsA(isA<InstallationConflict>()),
    );
    expect(
      (await storage.getModel('fixture'))!['local_path'],
      'newer-owner.gguf',
    );
    expect(
      (await journal.read(state.operationId)).phase,
      InstallationPhase.projecting,
    );
  });

  test(
    'artifact-write failure rolls back model and journal projection',
    () async {
      final state = await prepareProjection();
      final db = await storage.database;
      await db.execute(
        '''CREATE TRIGGER reject_fixture BEFORE INSERT ON model_files
      BEGIN SELECT RAISE(ABORT, 'fixture failure'); END''',
      );
      await expectLater(
        journal.commit(state.operationId, state.revision),
        throwsA(isA<DatabaseException>()),
      );
      expect(await storage.getModel('fixture'), before);
      expect(await storage.getModelFiles('fixture'), isEmpty);
      expect((await journal.read(state.operationId)).revision, state.revision);
      await db.execute('DROP TRIGGER reject_fixture');
      expect(
        (await journal.commit(state.operationId, state.revision)).phase,
        InstallationPhase.installed,
      );
    },
  );

  test('missing shard records cannot be mistaken for a complete set', () async {
    final state = await begin();
    await (await storage.database).delete(
      'model_installation_shards',
      where: 'operation_id = ? AND shard_index = ?',
      whereArgs: [state.operationId, 1],
    );
    await expectLater(
      journal.read(state.operationId),
      throwsA(isA<InstallationConflict>()),
    );
    expect(await storage.getModel('fixture'), before);
  });

  test(
    'stale artifact changes block projection even when model row is unchanged',
    () async {
      final state = await prepareProjection();
      await storage.replaceModelFiles('fixture', [
        {
          'file_name': 'newer-owner.gguf',
          'local_path': 'newer-owner.gguf',
          'byte_size': 24,
          'sha256': firstHash,
          'etag': 'newer-entity',
          'shard_index': 0,
          'shard_count': 1,
        },
      ]);
      final newerFiles = await storage.getModelFiles('fixture');
      await expectLater(
        journal.commit(state.operationId, state.revision),
        throwsA(isA<InstallationConflict>()),
      );
      expect(await storage.getModel('fixture'), before);
      expect(await storage.getModelFiles('fixture'), newerFiles);
    },
  );
}
