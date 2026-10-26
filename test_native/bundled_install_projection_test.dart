import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/models/runtime_capabilities.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/services/runtime_capabilities_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real bundled install preserves its old record on projection failure and retries',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      final fixture = File(path!);
      expect(await fixture.length(), BundledModelManifest.byteSize);
      expect(
        (await sha256.bind(fixture.openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final sandbox = await Directory.systemTemp.createTemp(
        'vitalis_bundled_projection_',
      );
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final storage = DatabaseHelper.instance;
      await storage.close();
      await databaseFactory.setDatabasesPath(sandbox.path);
      final registry = ModelRegistryService(
        checkProbeSafety: () {},
        capabilitiesProvider: _Capabilities(),
      );
      addTearDown(() async {
        await registry.close();
        await storage.close();
        await sandbox.delete(recursive: true);
      });
      await storage.upsertModel({
        'id': BundledModelManifest.id,
        'display_name': 'Preserved fixture record',
        'source': 'fixture',
        'local_path': fixture.path,
        'sha256': BundledModelManifest.sha256,
        'byte_size': BundledModelManifest.byteSize,
        'compatibility_status': 'unvalidated',
        'installation_state': 'pending_validation',
      });
      final before = await storage.getModel(BundledModelManifest.id);
      final database = await storage.database;
      await database.execute(
        '''CREATE TRIGGER reject_bundled_projection BEFORE UPDATE ON models
      WHEN NEW.compatibility_status = 'compatible'
      BEGIN SELECT RAISE(ABORT, 'Injected projection failure'); END''',
      );
      await expectLater(
        registry.installBundledModel(fixture.path),
        throwsA(isA<DatabaseException>()),
      );
      expect(await storage.getModel(BundledModelManifest.id), before);
      expect(registry.requiresProbeRecovery, isFalse);
      expect(await fixture.length(), BundledModelManifest.byteSize);
      await database.execute('DROP TRIGGER reject_bundled_projection');
      final installed = await registry.installBundledModel(fixture.path);
      expect(installed.isInstalled, isTrue);
      expect(installed.sha256, BundledModelManifest.sha256);
      expect(
        (await storage.getModel(
          BundledModelManifest.id,
        ))!['compatibility_status'],
        'compatible',
      );
      expect(
        (await sha256.bind(fixture.openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

final class _Capabilities implements RuntimeCapabilitiesProvider {
  @override
  Future<RuntimeCapabilities> snapshot() async => const RuntimeCapabilities(
    logicalProcessors: 4,
    performanceProcessors: 2,
    deviceFingerprint: 'host-fixture',
    abis: ['x86_64'],
    packagedBackends: {'cpu'},
    availableMemoryBytes: 4 * 1024 * 1024 * 1024,
    thermalStatus: null,
    lowMemory: null,
  );
}
