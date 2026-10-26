import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/models/runtime_capabilities.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/runtime_profile.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';
import 'package:vitalis_app/services/model_warmup_service.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/services/runtime_capabilities_provider.dart';

/// Explicit host gate, not a conditional fixture skip in the root suite.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'verified bundled fixture passes actual registry inference probe',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      final fixture = File(path!);
      expect(await fixture.exists(), isTrue);
      expect(
        (await sha256.bind(fixture.openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final sandbox = await Directory.systemTemp.createTemp(
        'vitalis-native-registry-',
      );
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.setDatabasesPath(sandbox.path);
      addTearDown(() async {
        await DatabaseHelper.instance.close();
        await sandbox.delete(recursive: true);
      });
      await DatabaseHelper.instance.upsertModel({
        'id': BundledModelManifest.id,
        'display_name': BundledModelManifest.displayName,
        'source': 'fixture',
        'local_path': fixture.path,
        'sha256': BundledModelManifest.sha256,
        'byte_size': await fixture.length(),
        'compatibility_status': 'unvalidated',
        'installation_state': 'pending_validation',
      });
      final registry = ModelRegistryService(
        checkProbeSafety: () =>
            expect(fixture.lengthSync(), BundledModelManifest.byteSize),
        capabilitiesProvider: _HostCapabilities(),
        allowedRoots: () async => [sandbox],
      );
      final model = await registry.installBundledModel(fixture.path);
      expect(model.isInstalled, isTrue);
      expect(model.compatibilityStatus, 'compatible');
      expect(await fixture.exists(), isTrue);
      final owner = LlamaCppChatRepository.withModelPath(
        fixture.path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      final competitor = LlamaCppChatRepository.withModelPath(fixture.path);
      final unrelated = File('${sandbox.path}/unrelated.gguf');
      await unrelated.writeAsString('GGUF disposable fixture');
      await DatabaseHelper.instance.upsertModel({
        'id': 'unrelated',
        'display_name': 'Disposable',
        'source': 'fixture',
        'local_path': unrelated.path,
        'compatibility_status': 'compatible',
        'installation_state': 'installed',
      });
      await owner.withExclusiveSession(() async {
        try {
          await owner.prepare();
          var checked = false;
          await for (final chunk in owner.streamChatWithGenerationOptions(
            'fixture',
            messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
            generationOptions: const GenerationOptions(maxTokens: 32),
          )) {
            if (!checked && chunk.done != true) {
              checked = true;
              await registry.uninstall('unrelated');
              expect(await unrelated.exists(), isFalse);
              await expectLater(
                registry.uninstall(BundledModelManifest.id),
                throwsA(isA<InferenceRuntimeBusy>()),
              );
              expect(await fixture.exists(), isTrue);
              await expectLater(competitor.prepare(), throwsStateError);
              await expectLater(
                competitor.cancelActiveInference(),
                throwsStateError,
              );
              await expectLater(
                competitor.unloadPersistentModel(),
                throwsStateError,
              );
              await expectLater(
                competitor.withExclusiveSession(() async {}),
                throwsStateError,
              );
              competitor.dispose();
            }
          }
          expect(checked, isTrue);
          expect(owner.lastMetrics?.generatedTokens, greaterThan(0));
          expect(owner.lastMetrics?.completionReason, isNot('cancelled'));
        } finally {
          await owner.unloadPersistentModel();
        }
      });
      // Ordinary chat requests need ownership too, not only probe leases.
      await owner.prepare();
      await expectLater(
        registry.uninstall(BundledModelManifest.id),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      expect(
        (await registry.findById(BundledModelManifest.id))?.isInstalled,
        isTrue,
      );
      final gapCompetitor = LlamaCppChatRepository.withModelPath(fixture.path);
      await expectLater(
        gapCompetitor.withExclusiveSession(() async {}),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      await expectLater(
        gapCompetitor.prepare(),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      await expectLater(
        gapCompetitor.unloadPersistentModel(),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      await gapCompetitor.close();
      var checkedOrdinaryRequest = false;
      await for (final chunk in owner.streamChatWithGenerationOptions(
        'fixture',
        messages: [LLMMessage(role: LLMRole.user, content: 'Count to ten.')],
        generationOptions: const GenerationOptions(maxTokens: 32),
      )) {
        if (!checkedOrdinaryRequest && chunk.done != true) {
          checkedOrdinaryRequest = true;
          await expectLater(
            competitor.cancelActiveInference(),
            throwsA(isA<InferenceRuntimeBusy>()),
          );
          await expectLater(
            competitor.unloadPersistentModel(),
            throwsA(isA<InferenceRuntimeBusy>()),
          );
          competitor.dispose();
        }
      }
      expect(checkedOrdinaryRequest, isTrue);
      expect(owner.lastMetrics?.completionReason, isNot('cancelled'));
      await owner.unloadPersistentModel();
      await owner.close();
      final closing = LlamaCppChatRepository.withModelPath(
        fixture.path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      await closing.prepare();
      Future<void>? shutdown;
      var visibleChunks = 0;
      await for (final chunk in closing.streamChatWithGenerationOptions(
        'fixture',
        messages: [LLMMessage(role: LLMRole.user, content: 'Count to fifty.')],
        generationOptions: const GenerationOptions(maxTokens: 128),
      )) {
        expect(chunk.done, isNot(true));
        visibleChunks++;
        shutdown ??= closing.close();
      }
      expect(visibleChunks, 1);
      expect(shutdown, isNotNull);
      await shutdown;
      expect(closing.cleanupFailed, isFalse);
      await expectLater(
        closing.prepare(),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );

      final service = ModelWarmupService(
        sentinel: _SafeHostSentinel(),
        modelRegistry: registry,
        capabilitiesProvider: _HostCapabilities(),
      );
      const profile = RuntimeProfile(
        contextSize: 2048,
        reservedOutputTokens: 128,
        generationThreads: 2,
        promptThreads: 2,
        batchSize: 128,
        gpuLayers: 0,
        thinkingMode: ThinkingMode.off,
      );
      final serviceRepository = await service.ensureProfile(
        profile,
        modelId: BundledModelManifest.id,
      );
      Future<void>? serviceShutdown;
      var serviceChunks = 0;
      try {
        await for (final chunk
            in serviceRepository.streamChatWithGenerationOptions(
              'fixture',
              messages: [
                LLMMessage(role: LLMRole.user, content: 'Count to fifty.'),
              ],
              generationOptions: const GenerationOptions(maxTokens: 128),
            )) {
          expect(chunk.done, isNot(true));
          serviceChunks++;
          serviceShutdown ??= service.close();
          expect(identical(service.close(), serviceShutdown), isTrue);
        }
        expect(serviceChunks, 1);
        expect(serviceShutdown, isNotNull);
        await serviceShutdown;
        expect(service.requiresRecovery, isFalse);
        expect(service.repository, isNull);
      } finally {
        await service.close();
      }
      final nextOwner = LlamaCppChatRepository.withModelPath(
        fixture.path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      try {
        await nextOwner.prepare();
        await for (final _ in nextOwner.streamChatWithGenerationOptions(
          'fixture',
          messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
          generationOptions: const GenerationOptions(maxTokens: 8),
        )) {}
        expect(nextOwner.lastMetrics?.generatedTokens, greaterThan(0));
      } finally {
        await nextOwner.close();
      }
      final missingPath = '${sandbox.path}/missing-original.gguf';
      await DatabaseHelper.instance.upsertModel({
        'id': 'restoration-fixture',
        'display_name': 'Disposable restoration fixture',
        'source': 'fixture',
        'local_path': missingPath,
        'sha256': BundledModelManifest.sha256,
        'byte_size': await fixture.length(),
        'compatibility_status': 'verification_failed',
        'installation_state': 'verification_failed',
      });
      final restoration = ModelRegistryService(
        checkProbeSafety: () =>
            expect(fixture.lengthSync(), BundledModelManifest.byteSize),
        capabilitiesProvider: _HostCapabilities(),
        documentsDirectory: () async => sandbox,
        importPicker: () async => ImportedModelFile(
          name: BundledModelManifest.fileName,
          size: await fixture.length(),
          readStream: fixture.openRead(),
        ),
      );
      try {
        final restored = await restoration.restoreMissingFile(
          'restoration-fixture',
        );
        expect(restored?.id, 'restoration-fixture');
        expect(restored?.compatibilityStatus, 'compatible');
        expect(restored?.isInstalled, isTrue);
        expect(restored?.localPath, isNot(missingPath));
        expect(
          (await sha256.bind(File(restored!.localPath!).openRead()).first)
              .toString(),
          BundledModelManifest.sha256,
        );
        expect(await fixture.exists(), isTrue);
        expect(
          (await registry.findById(BundledModelManifest.id))?.localPath,
          fixture.path,
        );
      } finally {
        await restoration.close();
        await registry.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

final class _SafeHostSentinel implements HardwareSentinelService {
  @override
  bool isSafeForHeavyOperation() => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _HostCapabilities implements RuntimeCapabilitiesProvider {
  @override
  Future<RuntimeCapabilities> snapshot() async => const RuntimeCapabilities(
    logicalProcessors: 4,
    performanceProcessors: 2,
    deviceFingerprint: 'host-test-fixture',
    abis: ['x86_64'],
    packagedBackends: {'cpu'},
    availableMemoryBytes: 4 * 1024 * 1024 * 1024,
    thermalStatus: null,
    lowMemory: null,
  );
}
