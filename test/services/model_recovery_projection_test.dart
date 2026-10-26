import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/database/database_helper.dart';

void main() {
  late Directory sandbox;
  final storage = DatabaseHelper.instance;
  late Map<String, Object?> original;
  late int artifactId;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    sandbox = await Directory.systemTemp.createTemp(
      'vitalis_recovery_projection_',
    );
    await databaseFactory.setDatabasesPath(sandbox.path);
  });
  setUp(() async {
    await storage.close();
    final file = File(p.join(sandbox.path, 'vitalis.db'));
    if (await file.exists()) await file.delete();
    await storage.upsertModel({
      'id': 'disposable',
      'display_name': 'Disposable',
      'source': 'huggingface',
      'local_path': 'missing.gguf',
      'sha256': 'fixture-hash',
      'byte_size': 12,
      'compatibility_status': 'unvalidated',
      'installation_state': 'installed',
    });
    await storage.replaceModelFiles('disposable', [
      {
        'file_name': 'weights.gguf',
        'local_path': 'missing.gguf',
        'sha256': 'fixture-hash',
        'byte_size': 12,
        'shard_index': 0,
        'shard_count': 1,
        'etag': 'immutable',
      },
    ]);
    original = Map<String, Object?>.from(
      (await storage.getModel('disposable'))!,
    );
    artifactId =
        (await storage.getModelFiles('disposable')).single['id'] as int;
  });
  tearDownAll(() async {
    await storage.close();
    await sandbox.delete(recursive: true);
  });

  Future<void> restore() => storage.restoreModelInstallation(
    {
      ...original,
      'local_path': 'restored.gguf',
      'compatibility_status': 'compatible',
    },
    expectedPath: 'missing.gguf',
    expectedHash: 'fixture-hash',
    artifactId: artifactId,
  );

  test(
    'recovery projection updates both paths without replacing artifact identity',
    () async {
      await restore();
      expect(
        (await storage.getModel('disposable'))!['local_path'],
        'restored.gguf',
      );
      final artifact = (await storage.getModelFiles('disposable')).single;
      expect(artifact['local_path'], 'restored.gguf');
      expect(artifact['id'], artifactId);
      expect(artifact['etag'], 'immutable');
      expect(artifact['file_name'], 'weights.gguf');
    },
  );

  for (final field in ['local_path', 'sha256']) {
    test('stale recovery cannot overwrite changed model $field', () async {
      await storage.upsertModel({...original, field: 'new-identity'});
      final before = await storage.getModel('disposable');
      final artifacts = await storage.getModelFiles('disposable');
      await expectLater(restore(), throwsStateError);
      expect(await storage.getModel('disposable'), before);
      expect(await storage.getModelFiles('disposable'), artifacts);
    });
  }

  for (final change in <String, Object?>{
    'sha256': 'different-hash',
    'shard_count': 2,
    'shard_index': 1,
    'local_path': 'new-artifact.gguf',
    'byte_size': 24,
  }.entries) {
    test('stale recovery rejects changed artifact ${change.key}', () async {
      final database = await storage.database;
      await database.update(
        'model_files',
        {change.key: change.value},
        where: 'id = ?',
        whereArgs: [artifactId],
      );
      final artifacts = await storage.getModelFiles('disposable');
      await expectLater(restore(), throwsStateError);
      expect(await storage.getModel('disposable'), original);
      expect(await storage.getModelFiles('disposable'), artifacts);
    });
  }

  test(
    'artifact write failure rolls back the preceding model projection',
    () async {
      final database = await storage.database;
      final artifacts = await storage.getModelFiles('disposable');
      await database.execute(
        '''CREATE TRIGGER reject_recovery BEFORE UPDATE ON model_files
      BEGIN SELECT RAISE(ABORT, 'Injected artifact write failure'); END''',
      );
      await expectLater(restore(), throwsA(isA<DatabaseException>()));
      expect(await storage.getModel('disposable'), original);
      expect(await storage.getModelFiles('disposable'), artifacts);
    },
  );

  test(
    'hash-verified legacy identity may acquire previously unknown byte size',
    () async {
      await storage.replaceModelFiles('disposable', []);
      await storage.upsertModel({...original, 'byte_size': null});
      await storage.restoreModelInstallation(
        {...original, 'local_path': 'restored.gguf'},
        expectedPath: 'missing.gguf',
        expectedHash: 'fixture-hash',
        artifactId: null,
      );
      final model = (await storage.getModel('disposable'))!;
      expect(model['local_path'], 'restored.gguf');
      expect(model['byte_size'], 12);
      expect(await storage.getModelFiles('disposable'), isEmpty);
    },
  );
}
