import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/native_runtime_bridge.dart';
import 'package:llm_llamacpp/src/loader/loader.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/constants/app_constants.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/database/model_installation_journal.dart';
import 'package:vitalis_app/models/model_descriptor.dart';
import 'package:vitalis_app/models/model_installation.dart';
import 'package:vitalis_app/services/model_installation_promoter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = DatabaseHelper.instance;
  late Directory sandbox;
  late Directory root;
  late ModelInstallationJournal journal;
  late InstallationSnapshot ready;
  late List<InstallationShard> shards;
  late Map<String, dynamic> original;
  final contents = [
    [1, 2, 3, 4],
    [5, 6, 7, 8],
  ];
  final leased = <String>[];

  Future<void> testLease(
    Iterable<String> paths,
    Future<void> Function() action,
  ) async {
    leased.addAll(paths);
    await action();
  }

  ModelInstallationPromoter promoter({
    InstallationFileMove? move,
    InstallationFileLease? lease,
  }) => ModelInstallationPromoter(
    journal: journal,
    roots: () async => [root],
    move: move,
    withFileLease: lease ?? testLease,
  );

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    sandbox = await Directory.systemTemp.createTemp('vitalis_promoter_');
    await databaseFactory.setDatabasesPath(sandbox.path);
  });
  setUp(() async {
    await storage.close();
    await databaseFactory.deleteDatabase(
      p.join(sandbox.path, AppConstants.databaseName),
    );
    root = await sandbox.createTemp('owned-');
    final staging = await Directory(p.join(root.path, 'staging')).create();
    final finalDirectory = await Directory(p.join(root.path, 'final')).create();
    shards = [
      for (var i = 0; i < contents.length; i++)
        InstallationShard(
          index: i,
          count: contents.length,
          fileName: 'model-$i.gguf',
          byteSize: contents[i].length,
          stagingPath: p.join(staging.path, 'model-$i.part'),
          finalPath: p.join(finalDirectory.path, 'model-$i.gguf'),
          expectedSha256: sha256.convert(contents[i]).toString(),
          hashAuthority: ModelHashAuthority.publisherSha256,
        ),
    ];
    for (final shard in shards) {
      await File(
        shard.stagingPath,
      ).writeAsBytes(contents[shard.index], flush: true);
    }
    await storage.upsertModel({
      'id': 'fixture',
      'display_name': 'Disposable',
      'source': 'local_import',
      'local_path': 'preserved-old.gguf',
      'sha256': shards.first.expectedSha256,
      'byte_size': 8,
      'compatibility_status': 'compatible',
      'installation_state': 'installed',
    });
    original = (await storage.getModel('fixture'))!;
    journal = ModelInstallationJournal(database: () => storage.database);
    var state = await journal.begin(
      operationId: 'op',
      modelId: 'fixture',
      shards: shards,
    );
    state = await journal.startValidation('op', state.revision);
    for (final shard in shards) {
      state = await journal.validateShard(
        'op',
        state.revision,
        index: shard.index,
        byteSize: shard.byteSize,
        sha256: shard.expectedSha256!,
      );
    }
    ready = await journal.ready(
      'op',
      state.revision,
      ModelDescriptor.fromMap({
        ...original,
        'local_path': shards.first.finalPath,
      }),
    );
    leased.clear();
  });
  tearDownAll(() async {
    await storage.close();
    await sandbox.delete(recursive: true);
  });

  test(
    'production native file lease blocks a live reader then permits promotion',
    () async {
      final bridge = NativeRuntimeBridge(loadLlamaLibrary());
      final lease = bridge.acquireModelRead(
        modelPath: LlamaCppChatRepository.modelFileIdentity(
          shards.first.stagingPath,
        ),
      );
      expect(lease.address, isNot(0));
      final nativePromoter = ModelInstallationPromoter(
        journal: journal,
        roots: () async => [root],
      );
      try {
        await expectLater(
          nativePromoter.promote('op'),
          throwsA(isA<InferenceRuntimeBusy>()),
        );
        expect((await journal.read('op')).revision, ready.revision);
        expect(await File(shards.first.stagingPath).exists(), isTrue);
        expect(await storage.getModel('fixture'), original);
      } finally {
        bridge.releaseModelAccess(lease);
      }
      expect(
        (await nativePromoter.promote('op')).phase,
        InstallationPhase.installed,
      );
    },
  );

  test('unvalidated operation cannot start file promotion', () async {
    await (await storage.database).update(
      'model_installation_journal',
      {'phase': 'validating'},
      where: 'operation_id = ?',
      whereArgs: ['op'],
    );
    await expectLater(
      promoter().promote('op'),
      throwsA(isA<InstallationConflict>()),
    );
    expect(leased, isEmpty);
    expect(await storage.getModel('fixture'), original);
  });

  test('validates and promotes all files before atomic activation', () async {
    final installed = await promoter().promote(ready.operationId);
    expect(installed.phase, InstallationPhase.installed);
    expect(leased.toSet(), {
      for (final shard in shards) ...[shard.stagingPath, shard.finalPath],
    });
    for (final shard in shards) {
      expect(await File(shard.finalPath).readAsBytes(), contents[shard.index]);
      expect(await File(shard.stagingPath).exists(), isFalse);
    }
    expect(
      (await storage.getModel('fixture'))!['local_path'],
      shards.first.finalPath,
    );
    expect((await promoter().promote('op')).revision, installed.revision);
  });

  test('restart recovers rename before journal acknowledgement', () async {
    var moves = 0;
    await expectLater(
      promoter(
        move: (source, destination) async {
          await source.rename(destination.path);
          if (++moves == 1) throw InstallationPromotionInterrupted();
        },
      ).promote('op'),
      throwsA(isA<InstallationPromotionInterrupted>()),
    );
    expect(await storage.getModel('fixture'), original);
    expect((await journal.read('op')).shards.first['moved'], 0);
    await storage.close();
    final installed = await promoter().promote('op');
    expect(installed.phase, InstallationPhase.installed);
    expect(await storage.getModelFiles('fixture'), hasLength(2));
  });

  test(
    'different existing destination is preserved with all staging files',
    () async {
      await File(shards.last.finalPath).writeAsBytes([9, 9, 9, 9]);
      await expectLater(
        promoter().promote('op'),
        throwsA(
          isA<InstallationFileFailure>().having(
            (e) => e.code,
            'code',
            InstallationFileFailureCode.integrity,
          ),
        ),
      );
      expect(await File(shards.last.finalPath).readAsBytes(), [9, 9, 9, 9]);
      expect(await File(shards.first.stagingPath).exists(), isTrue);
      expect(
        (await journal.read('op')).phase,
        InstallationPhase.readyToInstall,
      );
      expect(await storage.getModel('fixture'), original);
    },
  );

  test('missing or changed staging cannot activate partial sets', () async {
    await File(shards.last.stagingPath).delete();
    await expectLater(
      promoter().promote('op'),
      throwsA(
        isA<InstallationFileFailure>().having(
          (e) => e.code,
          'code',
          InstallationFileFailureCode.missing,
        ),
      ),
    );
    expect(await File(shards.first.stagingPath).exists(), isTrue);
    expect(await storage.getModel('fixture'), original);
  });

  test(
    'busy native lease does not move files or advance the journal',
    () async {
      await expectLater(
        promoter(
          lease: (_, _) async => throw InferenceRuntimeBusy(),
        ).promote('op'),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      expect((await journal.read('op')).revision, ready.revision);
      expect(await File(shards.first.stagingPath).exists(), isTrue);
    },
  );

  test(
    'stop after first move retains recoverable projection without activation',
    () async {
      var stopped = false;
      await expectLater(
        promoter(
          move: (source, destination) async {
            await source.rename(destination.path);
            stopped = true;
          },
        ).promote('op', canContinue: () => !stopped),
        throwsA(isA<InstallationPromotionInterrupted>()),
      );
      expect((await journal.read('op')).shards.first['moved'], 1);
      expect(await storage.getModel('fixture'), original);
      expect(
        (await promoter().promote('op')).phase,
        InstallationPhase.installed,
      );
    },
  );

  test(
    'outside-root journal path is rejected before acquiring a lease',
    () async {
      final outside = File(p.join(sandbox.path, 'unrelated.gguf'));
      await outside.writeAsBytes([9, 8, 7]);
      await (await storage.database).update(
        'model_installation_shards',
        {'final_path': outside.path},
        where: 'operation_id = ? AND shard_index = ?',
        whereArgs: ['op', 1],
      );
      await expectLater(
        promoter().promote('op'),
        throwsA(
          isA<InstallationFileFailure>().having(
            (e) => e.code,
            'code',
            InstallationFileFailureCode.boundary,
          ),
        ),
      );
      expect(leased, isEmpty);
      expect(await outside.readAsBytes(), [9, 8, 7]);
      expect(await storage.getModel('fixture'), original);
    },
  );

  test(
    'path changes while acquiring ownership cannot escape the lease',
    () async {
      await expectLater(
        promoter(
          lease: (paths, action) async {
            await (await storage.database).update(
              'model_installation_shards',
              {'final_path': p.join(root.path, 'final', 'changed-owner.gguf')},
              where: 'operation_id = ? AND shard_index = ?',
              whereArgs: ['op', 1],
            );
            await action();
          },
        ).promote('op'),
        throwsA(isA<InstallationConflict>()),
      );
      expect(await File(shards.first.stagingPath).exists(), isTrue);
      expect(await storage.getModel('fixture'), original);
    },
  );

  test('changed same-size bytes cannot reuse previous validation', () async {
    await File(shards.last.stagingPath).writeAsBytes([0, 0, 0, 0]);
    await expectLater(
      promoter().promote('op'),
      throwsA(
        isA<InstallationFileFailure>().having(
          (e) => e.code,
          'code',
          InstallationFileFailureCode.integrity,
        ),
      ),
    );
    expect(await File(shards.first.stagingPath).exists(), isTrue);
    expect(await storage.getModel('fixture'), original);
  });

  test(
    'filesystem errors expose no private path and retain recovery intent',
    () async {
      await expectLater(
        promoter(
          move: (_, _) async {
            throw const FileSystemException(
              'private detail',
              'private-model-path',
            );
          },
        ).promote('op'),
        throwsA(
          isA<InstallationFileFailure>()
              .having((e) => e.code, 'code', InstallationFileFailureCode.io)
              .having(
                (e) => e.toString().contains('private'),
                'redacted',
                isFalse,
              ),
        ),
      );
      expect((await journal.read('op')).phase, InstallationPhase.projecting);
      expect(await storage.getModel('fixture'), original);
    },
  );
}
