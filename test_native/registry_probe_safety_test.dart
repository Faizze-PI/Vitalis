import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/models/runtime_capabilities.dart';
import 'package:vitalis_app/models/runtime_profile.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/services/runtime_capabilities_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  for (final duringPreparation in [false, true]) {
    test(
      'registry health revocation preserves records (preparation: $duringPreparation)',
      () async {
        final path = Platform.environment['VITALIS_TEST_MODEL'];
        expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
        final fixture = File(path!);
        expect(await fixture.length(), BundledModelManifest.byteSize);
        expect(
          (await sha256.bind(fixture.openRead()).first).toString(),
          BundledModelManifest.sha256,
        );
        final sandbox = await Directory.systemTemp.createTemp('probe-safety-');
        final storage = DatabaseHelper.instance;
        await storage.close();
        await databaseFactory.setDatabasesPath(sandbox.path);
        final health = StreamController<bool>.broadcast(sync: true);
        var safe = true;
        var interrupt = true;
        final probes = <_ObservedProbe>[];
        final registry = ModelRegistryService(
          checkProbeSafety: () {
            if (!safe) throw ModelProbeSafetyStop();
          },
          probeSafetyChanges: health.stream,
          capabilitiesProvider: _HostCapabilities(),
          probeFactory: ({required modelPath, required profile}) {
            final probe = _ObservedProbe(
              modelPath,
              profile,
              () {
                if (!interrupt) return;
                safe = false;
                health.add(false);
              },
              revokeDuringPreparation: interrupt && duringPreparation,
            );
            probes.add(probe);
            return probe;
          },
        );
        addTearDown(() async {
          if (registry.requiresProbeRecovery)
            await registry.recoverProbeCleanup();
          await registry.close();
          await health.close();
          await storage.close();
          await sandbox.delete(recursive: true);
        });
        await storage.upsertModel({
          'id': BundledModelManifest.id,
          'display_name': 'Preserved safety fixture',
          'source': 'fixture',
          'local_path': fixture.path,
          'sha256': BundledModelManifest.sha256,
          'byte_size': BundledModelManifest.byteSize,
          'compatibility_status': 'unvalidated',
          'installation_state': 'pending_validation',
        });
        final database = await storage.database;
        final chatId = await storage.insertChat({
          'title': 'Disposable safety fixture',
          'created_at': '2026-10-18T00:00:00Z',
          'updated_at': '2026-10-18T00:00:00Z',
        });
        await database.insert('model_settings', {
          'chat_id': chatId,
          'model_id': BundledModelManifest.id,
        });
        final beforeModel = await storage.getModel(BundledModelManifest.id);
        final beforeChat = await database.query('chats');
        final beforeSettings = await database.query('model_settings');
        await expectLater(
          registry.verifyInstallation(BundledModelManifest.id),
          throwsA(isA<ModelProbeSafetyStop>()),
        );
        final interrupted = probes.single;
        expect(interrupted.observedNativeText, !duringPreparation);
        expect(interrupted.observedNativePreparation, duringPreparation);
        expect(interrupted.nativeWorkAtRevocation, isTrue);
        expect(interrupted.closeAcknowledged, isTrue);
        expect(interrupted.operationSnapshot.hasNativeWork, isFalse);
        expect(interrupted.operationSnapshot.hasRetainedContext, isFalse);
        expect(registry.requiresProbeRecovery, isFalse);
        expect(await storage.getModel(BundledModelManifest.id), beforeModel);
        expect(await database.query('chats'), beforeChat);
        expect(await database.query('model_settings'), beforeSettings);
        safe = true;
        interrupt = false;
        final recovered = await registry.verifyInstallation(
          BundledModelManifest.id,
        );
        expect(recovered.isInstalled, isTrue);
        expect(recovered.sha256, BundledModelManifest.sha256);
        expect(probes, hasLength(2));
        expect(probes.last.lastMetrics?.generatedTokens, greaterThan(0));
        expect(probes.last.closeAcknowledged, isTrue);
        expect(await database.query('chats'), beforeChat);
        expect(await database.query('model_settings'), beforeSettings);
        expect(await fixture.length(), BundledModelManifest.byteSize);
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}

final class _ObservedProbe extends LlamaCppChatRepository {
  _ObservedProbe(
    String path,
    RuntimeProfile profile,
    this.revoke, {
    this.revokeDuringPreparation = false,
  }) : super.withModelPath(
         path,
         contextSize: profile.contextSize,
         batchSize: profile.batchSize,
         threads: profile.generationThreads,
         promptThreads: profile.promptThreads,
         nGpuLayers: profile.gpuLayers,
         supportsThinkingControl: true,
       );
  final void Function() revoke;
  final bool revokeDuringPreparation;
  bool observedNativeText = false;
  bool observedNativePreparation = false;
  bool nativeWorkAtRevocation = false;
  bool closeAcknowledged = false;

  @override
  Future<void> prepare({RuntimeOperationKind? kind}) async {
    final preparing = super.prepare(kind: kind);
    if (revokeDuringPreparation) {
      // Observe rejection immediately; do not leave cancellation errors unhandled.
      final settled = preparing.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      );
      try {
        final clock = Stopwatch()..start();
        while (!operationSnapshot.cancellationHandleAvailable &&
            clock.elapsed < const Duration(seconds: 30)) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(operationSnapshot.initializationPending, isTrue);
        expect(operationSnapshot.cancellationHandleAvailable, isTrue);
        observedNativePreparation = true;
        nativeWorkAtRevocation = operationSnapshot.hasNativeWork;
        revoke();
      } finally {
        await settled;
      }
    }
    await preparing;
  }

  @override
  Stream<LLMChunk> streamChatWithGenerationOptions(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    LLMChatOptions? options,
    GenerationOptions? generationOptions,
  }) async* {
    await for (final chunk in super.streamChatWithGenerationOptions(
      model,
      messages: messages,
      think: think,
      tools: tools,
      extra: extra,
      options: options,
      generationOptions: generationOptions,
    )) {
      if (!observedNativeText &&
          chunk.done != true &&
          (chunk.message?.content ?? '').trim().isNotEmpty) {
        observedNativeText = true;
        nativeWorkAtRevocation = operationSnapshot.hasNativeWork;
        revoke();
      }
      yield chunk;
    }
  }

  @override
  Future<void> close() async {
    await super.close();
    closeAcknowledged = true;
  }
}

final class _HostCapabilities implements RuntimeCapabilitiesProvider {
  @override
  Future<RuntimeCapabilities> snapshot() async => const RuntimeCapabilities(
    logicalProcessors: 2,
    performanceProcessors: 1,
    deviceFingerprint: 'native-probe-safety-fixture',
    abis: ['x86_64'],
    packagedBackends: {'cpu'},
    availableMemoryBytes: 4 * 1024 * 1024 * 1024,
    thermalStatus: null,
    lowMemory: null,
  );
}
