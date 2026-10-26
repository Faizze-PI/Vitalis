import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/runtime_capabilities.dart';
import 'package:vitalis_app/models/runtime_profile.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/services/runtime_profile_store.dart';

void main() {
  late Directory sandbox;
  late Directory controlledRoot;
  late _RecordingProfileStore profiles;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    sandbox = Directory.systemTemp.createTempSync('vitalis_registry_test_');
    controlledRoot = Directory(p.join(sandbox.path, 'models'))
      ..createSync(recursive: true);
    await databaseFactory.setDatabasesPath(sandbox.path);
  });

  setUp(() async {
    await DatabaseHelper.instance.close();
    final databaseFile = File(p.join(sandbox.path, 'vitalis.db'));
    if (await databaseFile.exists()) await databaseFile.delete();
    profiles = _RecordingProfileStore();
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test(
    'uninstall deletes only the selected controlled file and retains row',
    () async {
      final modelFile = File(p.join(controlledRoot.path, 'selected.gguf'));
      await modelFile.writeAsBytes([1, 2, 3]);
      await DatabaseHelper.instance.upsertModel({
        'id': 'selected',
        'display_name': 'Selected',
        'local_path': modelFile.path,
        'source': 'local_import',
        'sha256': 'model-hash',
        'byte_size': 3,
        'compatibility_status': 'compatible',
        'installation_state': 'installed',
      });
      final registry = ModelRegistryService(
        profileStore: profiles,
        allowedRoots: () async => [controlledRoot],
      );

      await registry.uninstall('selected');

      expect(await modelFile.exists(), isFalse);
      final retained = (await DatabaseHelper.instance.getModel('selected'))!;
      expect(retained['installation_state'], 'not_installed');
      expect(profiles.invalidatedHashes, ['model-hash']);
    },
  );

  test(
    'uninstall refuses a registered path outside controlled storage',
    () async {
      final outside = File(p.join(sandbox.path, 'outside.gguf'));
      await outside.writeAsBytes([1, 2, 3]);
      await DatabaseHelper.instance.upsertModel({
        'id': 'outside',
        'display_name': 'Outside',
        'local_path': outside.path,
        'source': 'local_import',
        'sha256': 'outside-hash',
        'byte_size': 3,
        'compatibility_status': 'compatible',
        'installation_state': 'installed',
      });
      final registry = ModelRegistryService(
        profileStore: profiles,
        allowedRoots: () async => [controlledRoot],
      );

      await expectLater(registry.uninstall('outside'), throwsStateError);

      expect(await outside.exists(), isTrue);
      expect(
        (await DatabaseHelper.instance.getModel(
          'outside',
        ))!['installation_state'],
        'installed',
      );
    },
  );
}

class _RecordingProfileStore implements RuntimeProfileStore {
  @override
  Future<bool> writeIfCurrent(
    RuntimeProfileKey key,
    RuntimeProfile profile, {
    required bool Function() isCurrent,
    String? fallbackReason,
  }) async => isCurrent();
  final List<String> invalidatedHashes = [];

  @override
  Future<void> invalidate(RuntimeProfileKey key) async {}

  @override
  Future<void> invalidateModel(String modelSha256) async {
    invalidatedHashes.add(modelSha256);
  }

  @override
  Future<StoredRuntimeProfile?> read(RuntimeProfileKey key) async => null;

  @override
  Future<void> write(
    RuntimeProfileKey key,
    RuntimeProfile profile, {
    String? fallbackReason,
  }) async {}
}
