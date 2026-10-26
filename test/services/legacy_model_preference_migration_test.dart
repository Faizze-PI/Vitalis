import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/services/legacy_model_preference_migration.dart';
import 'package:vitalis_app/services/startup_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    databaseDirectory = await Directory.systemTemp.createTemp(
      'vitalis-migration-db-',
    );
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
  });
  setUp(() async {
    await DatabaseHelper.instance.close();
    await databaseFactory.deleteDatabase(
      '${databaseDirectory.path}/vitalis.db',
    );
  });
  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    await databaseDirectory.delete(recursive: true);
  });

  Future<GgufMetadata> metadata(String path) async => GgufMetadata(
    path: path,
    version: 3,
    tensorCount: 1,
    metadataKvCount: 4,
    metadata: {
      'general.architecture': 'qwen2',
      'tokenizer.ggml.model': 'bpe',
      'tokenizer.chat_template': '{{ enable_thinking }}',
      'qwen2.context_length': 8192,
    },
  );

  test('does nothing when no legacy model path exists', () async {
    SharedPreferences.setMockInitialValues(const {});

    expect(await LegacyModelPreferenceMigration().run(), isFalse);
  });

  test('retains legacy preferences when the file cannot be verified', () async {
    final directory = await Directory.systemTemp.createTemp(
      'vitalis-legacy-model-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final invalid = File('${directory.path}/old-model.gguf');
    await invalid.writeAsBytes(List<int>.filled(1024 * 1024, 0));
    SharedPreferences.setMockInitialValues({
      'model_downloaded': true,
      'model_file_path': invalid.path,
      'model_file_sha256': 'not-a-valid-hash',
    });

    await expectLater(
      LegacyModelPreferenceMigration().run(),
      throwsA(
        isA<LegacyMigrationFailure>().having(
          (error) => error.code,
          'code',
          LegacyMigrationFailureCode.invalidHeader,
        ),
      ),
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('model_downloaded'), isTrue);
    expect(preferences.getString('model_file_path'), invalid.path);
    expect(preferences.getString('model_file_sha256'), 'not-a-valid-hash');
  });

  for (final recordedHash in [false, true]) {
    test(
      'unrecognized content cannot claim bundled identity (hash: $recordedHash)',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'vitalis-identity-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/Qwen3.5-0.8B-Q4_K_M.gguf');
        final bytes = List<int>.filled(1024 * 1024, 0);
        bytes.setRange(0, 4, 'GGUF'.codeUnits);
        await file.writeAsBytes(bytes);
        final digest = sha256.convert(bytes).toString();
        SharedPreferences.setMockInitialValues({
          'model_downloaded': true,
          'model_file_path': file.path,
          if (recordedHash) 'model_file_sha256': digest,
        });
        final db = await DatabaseHelper.instance.database;
        await db.insert('chats', {
          'id': 1,
          'title': 'Preserved',
          'created_at': '2026-01-01',
          'updated_at': '2026-01-01',
        });
        await db.insert('model_settings', {
          'chat_id': 1,
          'model_id': 'unavailable-original',
        });
        final beforeSettings = await db.query('model_settings');
        final bundledBefore = await DatabaseHelper.instance.getModel(
          BundledModelManifest.id,
        );
        expect(
          await LegacyModelPreferenceMigration(metadataReader: metadata).run(),
          isTrue,
        );
        final models = (await DatabaseHelper.instance.getModels())
            .where((row) => row['id'] != BundledModelManifest.id)
            .toList();
        expect(models, hasLength(1));
        expect(models.single['id'], 'local-${digest.substring(0, 16)}');
        expect(models.single['repository'], isNull);
        expect(models.single['revision'], isNull);
        expect(models.single['parameter_count'], isNull);
        expect(models.single['installation_state'], 'pending_validation');
        expect(models.single['supports_thinking'], 0);
        expect(
          await DatabaseHelper.instance.getModel(BundledModelManifest.id),
          bundledBefore,
        );
        expect(await db.query('model_settings'), beforeSettings);
        expect(await file.readAsBytes(), bytes);
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getString('model_file_path'), isNull);
        expect(preferences.getBool('model_downloaded'), isNull);
        expect(preferences.getString('model_file_sha256'), isNull);
        expect(
          await LegacyModelPreferenceMigration(metadataReader: metadata).run(),
          isFalse,
        );
      },
    );
  }

  test(
    'cleanup interruption reuses committed identity and preserves assignments',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'vitalis-reentry-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/legacy.gguf');
      final bytes = List<int>.filled(1024 * 1024, 0)
        ..setRange(0, 4, 'GGUF'.codeUnits);
      await file.writeAsBytes(bytes);
      SharedPreferences.setMockInitialValues({
        'model_file_path': file.path,
        'model_downloaded': true,
      });
      final migration = LegacyModelPreferenceMigration(
        metadataReader: metadata,
        removePreference: (prefs, key) async =>
            key == 'model_file_path' ? false : prefs.remove(key),
      );
      await expectLater(
        migration.run(),
        throwsA(
          isA<LegacyMigrationFailure>().having(
            (failure) => failure.code,
            'code',
            LegacyMigrationFailureCode.preferenceCleanupFailed,
          ),
        ),
      );
      final before = await DatabaseHelper.instance.getModels();
      expect(before, hasLength(2));
      expect(
        (await SharedPreferences.getInstance()).getString('model_file_path'),
        file.path,
      );
      expect(
        await LegacyModelPreferenceMigration(metadataReader: metadata).run(),
        isTrue,
      );
      expect(await DatabaseHelper.instance.getModels(), before);
      expect(await file.readAsBytes(), bytes);
    },
  );

  test(
    'database insertion failure retains file and restart preferences',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'vitalis-rollback-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/legacy.gguf');
      final bytes = List<int>.filled(1024 * 1024, 0)
        ..setRange(0, 4, 'GGUF'.codeUnits);
      await file.writeAsBytes(bytes);
      SharedPreferences.setMockInitialValues({
        'model_file_path': file.path,
        'model_downloaded': true,
      });
      final db = await DatabaseHelper.instance.database;
      await db.execute(
        "CREATE TRIGGER fail_migration BEFORE INSERT ON models BEGIN SELECT RAISE(ABORT, 'fixture'); END",
      );
      await expectLater(
        LegacyModelPreferenceMigration(metadataReader: metadata).run(),
        throwsA(isA<DatabaseException>()),
      );
      expect(await DatabaseHelper.instance.getModels(), hasLength(1));
      expect(
        (await SharedPreferences.getInstance()).getString('model_file_path'),
        file.path,
      );
      expect(await file.readAsBytes(), bytes);
      await db.execute('DROP TRIGGER fail_migration');
      expect(
        await LegacyModelPreferenceMigration(metadataReader: metadata).run(),
        isTrue,
      );
    },
  );

  test('recorded digest mismatch preserves all legacy preferences', () async {
    final directory = await Directory.systemTemp.createTemp('vitalis-digest-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/private-model.gguf');
    final bytes = List<int>.filled(1024 * 1024, 0);
    bytes.setRange(0, 4, 'GGUF'.codeUnits);
    await file.writeAsBytes(bytes);
    SharedPreferences.setMockInitialValues({
      'model_downloaded': true,
      'model_file_path': file.path,
      'model_file_sha256': 'previous-digest',
    });
    await expectLater(
      LegacyModelPreferenceMigration().run(),
      throwsA(
        isA<LegacyMigrationFailure>()
            .having(
              (error) => error.code,
              'code',
              LegacyMigrationFailureCode.recordedHashMismatch,
            )
            .having(
              (error) => error.toString(),
              'redacted diagnostic',
              isNot(contains(file.path)),
            ),
      ),
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('model_file_sha256'), 'previous-digest');
    expect(preferences.getString('model_file_path'), file.path);
    expect(preferences.getBool('model_downloaded'), isTrue);
    expect(await file.readAsBytes(), bytes);
  });

  for (final conflict in [false, true]) {
    test(
      'existing registry identity is protected (conflict: $conflict)',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'vitalis-existing-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/legacy.gguf');
        final bytes = List<int>.filled(1024 * 1024, 0)
          ..setRange(0, 4, 'GGUF'.codeUnits);
        await file.writeAsBytes(bytes);
        final hash = sha256.convert(bytes).toString();
        final id = 'local-${hash.substring(0, 16)}';
        final db = await DatabaseHelper.instance.database;
        await db.insert('models', {
          'id': id,
          'display_name': 'Keep user name',
          'source': 'imported',
          'compatibility_status': 'compatible',
          'installation_state': 'installed',
          'local_path': file.path,
          'sha256': conflict ? 'different-content' : hash,
        });
        final before = await DatabaseHelper.instance.getModel(id);
        SharedPreferences.setMockInitialValues({'model_file_path': file.path});
        final result = LegacyModelPreferenceMigration(
          metadataReader: metadata,
        ).run();
        if (conflict) {
          await expectLater(
            result,
            throwsA(
              isA<LegacyMigrationFailure>().having(
                (error) => error.code,
                'code',
                LegacyMigrationFailureCode.identityConflict,
              ),
            ),
          );
          expect(
            (await SharedPreferences.getInstance()).getString(
              'model_file_path',
            ),
            file.path,
          );
        } else {
          expect(await result, isTrue);
        }
        expect(await DatabaseHelper.instance.getModel(id), before);
        expect(await file.readAsBytes(), bytes);
      },
    );
  }

  test(
    'missing legacy file prevents startup readiness without clearing preferences',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'vitalis-missing-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/missing.gguf';
      SharedPreferences.setMockInitialValues({'model_file_path': path});
      var safetyCalls = 0;
      final startup = StartupCoordinator(
        openDatabase: () async {},
        loadLogger: () async {},
        migrateLegacyPreferences: () async {
          await LegacyModelPreferenceMigration().run();
        },
        initializeSafety: () async {
          safetyCalls++;
        },
      );
      addTearDown(startup.dispose);
      await startup.start();
      expect(startup.state, StartupState.failed);
      expect(startup.canEnterApp, isFalse);
      expect(safetyCalls, 0);
      expect(startup.failure, isNot(contains(path)));
      expect(
        (await SharedPreferences.getInstance()).getString('model_file_path'),
        path,
      );
    },
  );
}
