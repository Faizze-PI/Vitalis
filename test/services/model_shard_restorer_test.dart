import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/database/model_installation_journal.dart';
import 'package:vitalis_app/models/model_installation.dart';
import 'package:vitalis_app/services/model_registry_service.dart';

import '../support/shard_restore_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ShardRestoreFixture fixture;
  setUp(() async {
    fixture = ShardRestoreFixture();
    await fixture.initialize();
  });
  tearDown(() => fixture.destroy());

  test(
    'a durable download owner rejects restoration before the picker opens',
    () async {
      final journal = ModelInstallationJournal(
        database: () => fixture.storage.database,
      );
      await journal.begin(
        operationId: 'download-owner',
        modelId: 'fixture',
        jobId: 'download-job',
        shards: [
          for (final row in fixture.beforeFiles)
            InstallationShard(
              index: row['shard_index']! as int,
              count: 2,
              fileName: row['file_name']! as String,
              byteSize: row['byte_size']! as int,
              expectedSha256: row['sha256']! as String,
              hashAuthority: ModelHashAuthority.localIdentity,
              stagingPath: p.join(
                fixture.documents.path,
                'staging-${row['id']}',
              ),
              finalPath: p.join(fixture.documents.path, 'final-${row['id']}'),
            ),
        ],
      );
      final service = fixture.registry();
      addTearDown(service.close);
      await expectLater(
        service.restoreMissingFile('fixture'),
        throwsA(isA<ModelStorageBusy>()),
      );
      expect(fixture.picks, 0);
      expect(fixture.probes, 0);
      expect(await fixture.storage.getModel('fixture'), fixture.beforeModel);
    },
  );

  test(
    'failed native validation retains staged bytes and retry does not repick',
    () async {
      fixture.failProbe = true;
      final service = fixture.registry();
      await expectLater(
        service.restoreMissingFile('fixture'),
        throwsStateError,
      );
      await service.close();
      expect(await fixture.storage.getModel('fixture'), fixture.beforeModel);
      expect(
        await fixture.storage.getModelFiles('fixture'),
        fixture.beforeFiles,
      );
      fixture.failProbe = false;
      final retry = fixture.registry(
        picker: () async => throw StateError('must not repick'),
      );
      addTearDown(retry.close);
      expect((await retry.restoreMissingFile('fixture'))?.isInstalled, isTrue);
      expect(fixture.picks, 1);
      expect(fixture.probes, 2);
      expect(
        await fixture.storage.getModelSettings(fixture.chatId),
        fixture.beforeSettings,
      );
    },
  );

  test(
    'registry restores complete split bytes in arbitrary selection order',
    () async {
      final service = fixture.registry(
        picker: () async => fixture.picked(reverse: true),
      );
      addTearDown(service.close);
      final restored = await service.restoreMissingFile('fixture');
      expect(restored?.id, 'fixture');
      expect(restored?.isInstalled, isTrue);
      expect(fixture.probes, 1);
      expect(fixture.closes, 1);
      expect(
        await fixture.storage.getModelSettings(fixture.chatId),
        fixture.beforeSettings,
      );
      final files = await fixture.storage.getModelFiles('fixture');
      expect(files.map((f) => f['shard_index']), [0, 1]);
      expect(files.map((f) => f['etag']), [
        'original-entity-0',
        'original-entity-1',
      ]);
      for (var index = 0; index < files.length; index++) {
        expect(
          await File(files[index]['local_path']! as String).readAsBytes(),
          fixture.payloads[index],
        );
      }
    },
  );

  test(
    'legacy one-based records normalize only after complete validated recovery',
    () async {
      for (final row in fixture.beforeFiles) {
        await (await fixture.storage.database).update(
          'model_files',
          {'shard_index': (row['shard_index']! as int) + 1},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      final service = fixture.registry();
      addTearDown(service.close);
      await service.restoreMissingFile('fixture');
      expect(
        (await fixture.storage.getModelFiles(
          'fixture',
        )).map((f) => f['shard_index']),
        [0, 1],
      );
    },
  );

  test(
    'cancelled selection and incomplete sets leave records untouched',
    () async {
      final cancelled = fixture.registry(picker: () async => null);
      expect(await cancelled.restoreMissingFile('fixture'), isNull);
      await cancelled.close();
      final incomplete = fixture.registry(
        picker: () async => [fixture.picked().first],
      );
      await expectLater(
        incomplete.restoreMissingFile('fixture'),
        throwsA(isA<ModelIdentityMismatch>()),
      );
      await incomplete.close();
      expect(fixture.probes, 0);
      expect(await fixture.storage.getModel('fixture'), fixture.beforeModel);
      expect(
        await fixture.storage.getModelFiles('fixture'),
        fixture.beforeFiles,
      );
    },
  );

  test(
    'wrong bytes retain valid partial staging and correct retry succeeds',
    () async {
      final service = fixture.registry(
        picker: () async => [
          fixture.picked().first,
          ImportedModelFile(
            name: 'wrong.gguf',
            size: fixture.payloads.last.length,
            readStream: Stream.value(
              List.filled(fixture.payloads.last.length, 0),
            ),
          ),
        ],
      );
      await expectLater(
        service.restoreMissingFile('fixture'),
        throwsA(isA<ModelIdentityMismatch>()),
      );
      await service.close();
      expect(fixture.probes, 0);
      expect(await fixture.storage.getModel('fixture'), fixture.beforeModel);
      final journal = ModelInstallationJournal(
        database: () => fixture.storage.database,
      );
      final pending = (await journal.pending()).single;
      expect(
        await File(pending.shards.first['staging_path']! as String).exists(),
        isTrue,
      );
      final retry = fixture.registry();
      addTearDown(retry.close);
      expect((await retry.restoreMissingFile('fixture'))?.isInstalled, isTrue);
      expect(await journal.pending(), isEmpty);
    },
  );

  test(
    'native close acknowledgement precedes installation projection',
    () async {
      fixture.closeGate = Completer<void>();
      final service = fixture.registry();
      final operation = service.restoreMissingFile('fixture');
      await fixture.closeStarted.future;
      expect(await fixture.storage.getModel('fixture'), fixture.beforeModel);
      expect(
        await fixture.storage.getModelFiles('fixture'),
        fixture.beforeFiles,
      );
      fixture.closeGate!.complete();
      expect((await operation)?.isInstalled, isTrue);
      await service.close();
    },
  );

  test(
    'failed projection resumes after reopen without repicking or reprobe',
    () async {
      await (await fixture.storage.database).execute('''
      CREATE TRIGGER reject_fixture BEFORE INSERT ON model_files
      BEGIN SELECT RAISE(ABORT, 'fixture failure'); END
    ''');
      final service = fixture.registry();
      await expectLater(
        service.restoreMissingFile('fixture'),
        throwsA(isA<DatabaseException>()),
      );
      await service.close();
      expect(await fixture.storage.getModel('fixture'), fixture.beforeModel);
      final journal = ModelInstallationJournal(
        database: () => fixture.storage.database,
      );
      expect(
        (await journal.pending()).single.phase,
        InstallationPhase.projecting,
      );
      await (await fixture.storage.database).execute(
        'DROP TRIGGER reject_fixture',
      );
      await fixture.storage.close();
      final retry = fixture.registry(
        picker: () async => throw StateError('must not repick'),
      );
      addTearDown(retry.close);
      expect((await retry.restoreMissingFile('fixture'))?.isInstalled, isTrue);
      expect(fixture.probes, 1);
      expect(fixture.picks, 1);
    },
  );

  test(
    'present primary does not prevent recovery of missing secondary shard',
    () async {
      final primary = File(fixture.beforeModel['local_path']! as String);
      await primary.parent.create(recursive: true);
      await primary.writeAsBytes(fixture.payloads.first);
      final service = fixture.registry();
      addTearDown(service.close);
      expect(
        (await service.restoreMissingFile('fixture'))?.isInstalled,
        isTrue,
      );
      expect(await primary.readAsBytes(), fixture.payloads.first);
      expect(p.basename(fixture.probedPaths.single), fixture.fileName(0));
    },
  );
}
