import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/models/model_descriptor.dart';
import 'package:vitalis_app/models/model_verification_phase.dart';
import 'package:vitalis_app/models/runtime_capabilities.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/services/model_startup_inspector.dart';
import 'package:vitalis_app/services/runtime_capabilities_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real split GGUF restores with acknowledged probe cleanup and subsequent inference',
    () async {
      final clock = Stopwatch()..start();
      void phase(String name) => print(
        'SPLIT_NATIVE_PHASE: $name elapsed_ms=${clock.elapsedMilliseconds}',
      );

      addTearDown(() => phase('test_teardown_begin'));
      final canonicalPath = Platform.environment['VITALIS_TEST_MODEL'];
      final receiptPath = Platform.environment['VITALIS_SPLIT_TEST_FIXTURE'];
      expect(
        canonicalPath,
        isNotEmpty,
        reason: 'VITALIS_TEST_MODEL is mandatory',
      );
      expect(
        receiptPath,
        isNotEmpty,
        reason: 'VITALIS_SPLIT_TEST_FIXTURE is mandatory',
      );
      final canonical = File(canonicalPath!);
      expect(await canonical.length(), BundledModelManifest.byteSize);
      expect(await _hash(canonical), BundledModelManifest.sha256);
      phase('canonical_verified');
      final receiptFile = File(receiptPath!);
      final receipt = jsonDecode(await receiptFile.readAsString()) as Map;
      final lockFile = File(
        'third_party/llm_llamacpp/native/llama_cpp.lock.json',
      );
      final lock = jsonDecode(await lockFile.readAsString()) as Map;
      final source = receipt['source'] as Map;
      final native = receipt['native'] as Map;
      expect(receipt['formatVersion'], 1);
      expect(source['modelId'], BundledModelManifest.id);
      expect(source['sha256'], BundledModelManifest.sha256);
      expect(source['repository'], BundledModelManifest.repository);
      expect(source['revision'], BundledModelManifest.revision);
      expect(native['commit'], lock['commit']);
      expect(native['archiveSha256'], lock['archiveSha256']);
      expect(native['sourceLockSha256'], await _hash(lockFile));
      expect('${native['toolSha256']}', matches(RegExp(r'^[a-f0-9]{64}$')));
      final artifacts = (receipt['files'] as List).cast<Map>();
      expect(artifacts.length, greaterThan(1));
      final files = <File>[];
      var totalBytes = 0;
      for (final (index, artifact) in artifacts.indexed) {
        final name = artifact['name']! as String;
        expect(p.basename(name), name);
        expect(name, matches(RegExp(r'^fixture-\d{5}-of-\d{5}\.gguf$')));
        expect(artifact['shardIndex'], index);
        expect(artifact['shardCount'], artifacts.length);
        final file = File(p.join(receiptFile.parent.path, name));
        expect(await file.length(), artifact['byteSize']);
        expect(await _hash(file), artifact['sha256']);
        final metadata = await GgufMetadata.fromFile(file.path);
        expect(metadata.get<int>('split.no'), index);
        expect(metadata.get<int>('split.count'), artifacts.length);
        phase('shard_${index}_verified');
        totalBytes += artifact['byteSize']! as int;
        files.add(file);
      }
      phase('fixture_verified');
      final sandbox = await Directory.systemTemp.createTemp(
        'vitalis_native_split_',
      );
      final documents = await Directory(
        p.join(sandbox.path, 'documents'),
      ).create();
      final storage = DatabaseHelper.instance;
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.setDatabasesPath(sandbox.path);
      LlamaCppChatRepository? owner;
      ModelRegistryService? registry;
      addTearDown(() async {
        // Failure to acknowledge native cleanup intentionally prevents deletion.
        await owner?.close();
        await registry?.close();
        await storage.close();
        await sandbox.delete(recursive: true);
      });
      const id = 'disposable-real-split-fixture';
      await storage.upsertModel({
        'id': id,
        'display_name': 'Disposable real split fixture',
        'source': 'local_fixture',
        'local_path': p.join(
          documents.path,
          'missing',
          artifacts.first['name']! as String,
        ),
        'sha256': artifacts.first['sha256'],
        'byte_size': totalBytes,
        'compatibility_status': 'missing_file',
        'installation_state': 'installed',
      });
      await storage.replaceModelFiles(id, [
        for (final artifact in artifacts)
          {
            'file_name': artifact['name'],
            'sha256': artifact['sha256'],
            'byte_size': artifact['byteSize'],
            'shard_index': artifact['shardIndex'],
            'shard_count': artifact['shardCount'],
            'local_path': p.join(
              documents.path,
              'missing',
              artifact['name']! as String,
            ),
          },
      ]);
      final stamp = DateTime.utc(2026, 10, 15).toIso8601String();
      final chat = await storage.insertChat({
        'title': 'Disposable preserved chat',
        'created_at': stamp,
        'updated_at': stamp,
      });
      await storage.assignModelForChat(chat, id);
      final beforeSettings = await storage.getModelSettings(chat);
      final phases = <ModelVerificationPhase>[];
      registry = ModelRegistryService(
        database: storage,
        documentsDirectory: () async => documents,
        allowedRoots: () async => [Directory(p.join(documents.path, 'models'))],
        checkProbeSafety: () {},
        capabilitiesProvider: _HostCapabilities(),
        restoreSetPicker: () async => [
          for (final file in files.reversed)
            ImportedModelFile(
              name: 'arbitrary-${files.indexOf(file)}.gguf',
              size: await file.length(),
              readStream: file.openRead(),
            ),
        ],
      );
      phase('registry_restore_begin');
      final restored = await registry.restoreMissingFile(
        id,
        onPhase: (value) {
          phases.add(value);
          phase('restore_${value.name}');
        },
      );
      phase('registry_restore_completed');
      expect(restored, isNotNull);
      expect(restored!.isInstalled, isTrue);
      expect(restored.id, id);
      expect(registry.requiresProbeRecovery, isFalse);
      expect(phases, containsAllInOrder(ModelVerificationPhase.values));
      expect(await storage.getModelSettings(chat), beforeSettings);
      final restoredFiles = await storage.getModelFiles(id);
      expect(restoredFiles.length, artifacts.length);
      expect(
        restoredFiles.map((row) => row['shard_index']),
        List.generate(artifacts.length, (index) => index),
      );
      final inspector = ModelStartupInspector(
        findModel: (modelId) async =>
            ModelDescriptor.fromMap((await storage.getModel(modelId))!),
        modelFiles: storage.getModelFiles,
      );
      phase('readiness_inspection_begin');
      expect(await inspector.inspect(id), StartupModelReadiness.ready);
      phase('restored_and_ready');
      owner = LlamaCppChatRepository.withModelPath(
        restored.localPath!,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      var completions = 0;
      final text = StringBuffer();
      await for (final chunk in owner.streamChatWithGenerationOptions(
        id,
        messages: [
          LLMMessage(role: LLMRole.user, content: 'Give a short greeting.'),
        ],
        generationOptions: const GenerationOptions(
          temperature: 0,
          maxTokens: 32,
        ),
      )) {
        text.write(chunk.message?.content ?? '');
        if (chunk.done == true) completions++;
      }
      expect(completions, 1);
      expect(text.toString().trim(), isNotEmpty);
      expect(owner.lastMetrics?.generatedTokens, greaterThan(0));
      expect(owner.lastMetrics?.completionReason, isNot('error'));
      await owner.close();
      await registry.close();
      expect(await _hash(canonical), BundledModelManifest.sha256);
      phase('followup_and_cleanup_complete');
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

Future<String> _hash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

final class _HostCapabilities implements RuntimeCapabilitiesProvider {
  @override
  Future<RuntimeCapabilities> snapshot() async => const RuntimeCapabilities(
    logicalProcessors: 4,
    performanceProcessors: 2,
    deviceFingerprint: 'host-split-fixture',
    abis: ['x86_64'],
    packagedBackends: {'cpu'},
    availableMemoryBytes: 4 * 1024 * 1024 * 1024,
    thermalStatus: null,
    lowMemory: null,
  );
}
