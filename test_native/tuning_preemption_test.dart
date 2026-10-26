import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/models/model_descriptor.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/providers/generation_provider.dart';
import 'package:vitalis_app/services/chat_state_controller.dart';
import 'package:vitalis_app/models/runtime_capabilities.dart';
import 'package:vitalis_app/models/runtime_profile.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/services/model_warmup_service.dart';
import 'package:vitalis_app/services/runtime_capabilities_provider.dart';
import 'package:vitalis_app/services/runtime_profile_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cold inference has request identity and Stop waits for helper readiness',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final repository = LlamaCppChatRepository.withModelPath(
        path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      addTearDown(repository.close);

      final events = <LLMChunk>[];
      final done = Completer<void>();
      final first = repository
          .streamChatWithGenerationOptions(
            'cold-start-cancel',
            messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
            generationOptions: const GenerationOptions(maxTokens: 32),
          )
          .listen(
            events.add,
            onError: done.completeError,
            onDone: () => done.complete(),
          );
      addTearDown(first.cancel);

      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline) &&
          !(repository.operationSnapshot.initializationPending &&
              repository.operationSnapshot.nativeRequestId != null)) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final duringInitialization = repository.operationSnapshot;
      expect(duringInitialization.initializationPending, isTrue);
      expect(duringInitialization.nativeRequestId, isNotNull);
      expect(duringInitialization.kind, RuntimeOperationKind.interactive);

      final stopped = repository.cancelActiveInference();
      expect(repository.operationSnapshot.cancellationRequested, isTrue);
      await stopped.timeout(const Duration(seconds: 30));
      await done.future.timeout(const Duration(seconds: 10));
      expect(events, isNotEmpty);
      expect(
        events.every(
          (event) => event.done == true && event.message?.content == null,
        ),
        isTrue,
        reason: 'cold-start cancellation must not publish assistant text',
      );
      expect(repository.operationSnapshot.hasNativeWork, isFalse);
      expect(repository.operationSnapshot.hasRetainedContext, isTrue);

      await repository.prepare();
      await for (final _ in repository.streamChatWithGenerationOptions(
        'cold-start-follow-up',
        messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
        generationOptions: const GenerationOptions(maxTokens: 16),
      )) {}
      expect(repository.lastMetrics?.generatedTokens, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'native tuning Stop during preparation is cancelled and yields to chat',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final registry = _Registry(
        ModelDescriptor(
          id: BundledModelManifest.id,
          displayName: 'Verified fixture',
          source: 'fixture',
          localPath: path,
          sha256: BundledModelManifest.sha256,
          contextTrain: 2048,
          compatibilityStatus: 'compatible',
          installationState: 'installed',
        ),
      );
      final preparationStarted = Completer<void>();
      final repositories = <_PreparationObservedRepository>[];
      final profiles = _ProfileStore();
      final service = ModelWarmupService(
        sentinel: _SafeSentinel(),
        modelRegistry: registry,
        capabilitiesProvider: _Capabilities(),
        profileStore: profiles,
        appVersionResolver: () async => 'native-preparation-cancel',
        processorCount: 2,
        repositoryFactory:
            ({
              required modelPath,
              required contextSize,
              required batchSize,
              required threads,
              required promptThreads,
              required gpuLayers,
              required supportsThinking,
              required runtimeOperationKind,
            }) {
              final repository = _PreparationObservedRepository(
                modelPath,
                contextSize: contextSize,
                batchSize: batchSize,
                threads: threads,
                promptThreads: promptThreads,
                nGpuLayers: gpuLayers,
                runtimeOperationKind: runtimeOperationKind,
                preparationStarted: preparationStarted,
              );
              repositories.add(repository);
              return repository;
            },
      );
      addTearDown(service.close);
      service.scheduleAutoTune(ModelSettings(modelId: BundledModelManifest.id));
      await preparationStarted.future;
      final tuningOwner = repositories.single;
      expect(tuningOwner.operationSnapshot.initializationPending, isTrue);
      expect(tuningOwner.operationSnapshot.nativeRequestId, isNotNull);
      expect(tuningOwner.operationSnapshot.kind, RuntimeOperationKind.tuning);

      final stopped = service.cancelTuning();
      expect(service.cancelTuning(), same(stopped));
      await stopped;

      expect(service.tuningStatus, RuntimeTuningStatus.cancelled);
      expect(service.requiresRecovery, isFalse);
      expect(profiles.writes, 0);
      expect(tuningOwner.isDisposed, isTrue);
      expect(tuningOwner.cleanupFailed, isFalse);
      expect(tuningOwner.operationSnapshot.kind, isNull);

      final chatRepository = await service.ensureProfile(
        RuntimeProfile.forSettings(
          ModelSettings(modelId: BundledModelManifest.id),
          processorCount: 2,
          maximumContextSize: 2048,
        ),
        modelId: BundledModelManifest.id,
      );
      await for (final _ in chatRepository.streamChatWithGenerationOptions(
        'chat-after-tuning-preparation-stop',
        messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
        generationOptions: const GenerationOptions(maxTokens: 16),
      )) {}
      expect(chatRepository.lastMetrics?.generatedTokens, greaterThan(0));
      expect(repositories, hasLength(2));
      expect(profiles.writes, 0);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  for (final scenario in [
    (safetyStop: false, streamClosed: false),
    (safetyStop: true, streamClosed: false),
    (safetyStop: true, streamClosed: true),
  ]) {
    final safetyStop = scenario.safetyStop;
    test(
      'native tuning yields after emitted text and permits user inference (safety: $safetyStop)${scenario.streamClosed ? ' after safety stream closure' : ''}',
      () async {
        void phase(String id) => stdout.writeln('NATIVE_TEST_PHASE:$id');
        final path = Platform.environment['VITALIS_TEST_MODEL'];
        expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
        final file = File(path!);
        expect(
          (await sha256.bind(file.openRead()).first).toString(),
          BundledModelManifest.sha256,
        );
        final registry = _Registry(
          ModelDescriptor(
            id: BundledModelManifest.id,
            displayName: 'Verified fixture',
            source: 'fixture',
            localPath: path,
            sha256: BundledModelManifest.sha256,
            contextTrain: 2048,
            compatibilityStatus: 'compatible',
            installationState: 'installed',
          ),
        );
        final visible = Completer<void>();
        final repositories = <_ObservedRepository>[];
        final store = _ProfileStore();
        final sentinel = _DynamicSentinel();
        addTearDown(sentinel.health.close);
        final service = ModelWarmupService(
          sentinel: sentinel,
          modelRegistry: registry,
          capabilitiesProvider: _Capabilities(),
          profileStore: store,
          appVersionResolver: () async => 'native-test',
          processorCount: 2,
          repositoryFactory:
              ({
                required modelPath,
                required contextSize,
                required batchSize,
                required threads,
                required promptThreads,
                required gpuLayers,
                required supportsThinking,
                required runtimeOperationKind,
              }) {
                final repository = _ObservedRepository(
                  modelPath,
                  contextSize: contextSize,
                  batchSize: batchSize,
                  threads: threads,
                  promptThreads: promptThreads,
                  nGpuLayers: gpuLayers,
                  runtimeOperationKind: runtimeOperationKind,
                  visible: visible,
                );
                repositories.add(repository);
                return repository;
              },
        );
        addTearDown(service.close);
        service.scheduleAutoTune(
          ModelSettings(modelId: BundledModelManifest.id),
        );
        phase('tuning_scheduled');
        await visible.future;
        phase('tuning_text_observed');
        if (safetyStop) {
          expect(repositories.single.stopRequested.isCompleted, isFalse);
          if (scenario.streamClosed) {
            await sentinel.health.close();
            phase('simulated_safety_observation_closed');
          } else {
            sentinel.safe = false;
            sentinel.health.add(false);
            phase('simulated_safety_stop_requested');
          }
          await repositories.single.stopRequested.future;
          phase('automatic_native_stop_observed');
        }
        final stop = service.cancelTuning();
        expect(service.cancelTuning(), same(stop));
        await stop;
        phase('tuning_shutdown_acknowledged');
        expect(service.tuningStatus, RuntimeTuningStatus.cancelled);
        expect(service.requiresRecovery, isFalse);
        expect(store.writes, 0);
        expect(repositories, hasLength(1));
        expect(repositories.single.cleanupFailed, isFalse);
        expect(repositories.single.isDisposed, isTrue);
        expect(repositories.single.lastMetrics?.completionReason, 'cancelled');
        expect(sentinel.health.hasListener, isFalse);
        sentinel.safe = true;
        const profile = RuntimeProfile(
          contextSize: 2048,
          reservedOutputTokens: 16,
          generationThreads: 2,
          promptThreads: 2,
          batchSize: 128,
          gpuLayers: 0,
          thinkingMode: ThinkingMode.off,
        );
        final next = await service.ensureProfile(
          profile,
          modelId: BundledModelManifest.id,
        );
        phase('interactive_profile_prepared');
        await for (final _ in next.streamChatWithGenerationOptions(
          'user-after-tuning',
          messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
          generationOptions: const GenerationOptions(maxTokens: 16),
        )) {}
        expect(next.lastMetrics?.generatedTokens, greaterThan(0));
        expect(next.lastMetrics?.completionReason, isNot('cancelled'));
        expect(repositories, hasLength(2));
        expect(store.writes, 0);
        phase('direct_followup_completed');

        // Exercise the actual interactive caller after native tuning shutdown.
        // Synthetic safety telemetry cannot establish Android safety/performance.
        final provider = GenerationProvider(
          controller: ChatStateController(sentinel: _SafeSentinel()),
          warmup: service,
        );
        addTearDown(provider.dispose);
        final settings = ModelSettings(
          modelId: BundledModelManifest.id,
          tuningMode: TuningMode.advanced,
          contextSizeOverride: 2048,
          generationThreadsOverride: 2,
          promptThreadsOverride: 2,
          batchSizeOverride: 128,
          maxTokens: 256,
          systemPrompt: 'Answer concisely.',
        );
        final firstText = Completer<void>();
        provider.addListener(() {
          if (provider.streamText.isNotEmpty && !firstText.isCompleted) {
            firstText.complete();
          }
        });
        var completionCount = 0;
        provider.onGenerationComplete = (_) => completionCount++;
        final providerErrors = <String>[];
        provider.onError = (error) {
          providerErrors.add(error);
          phase('provider_error_observed');
        };
        phase('provider_first_request_begin');
        await provider.startGeneration(
          messages: [
            Message(
              chatId: 1,
              role: MessageRole.user,
              content:
                  'Write a long numbered list of harmless household objects.',
            ),
          ],
          settings: settings,
        );
        await firstText.future;
        phase('provider_first_text_observed');
        final activeOperation = next.operationSnapshot;
        expect(activeOperation.hasNativeWork, isTrue);
        expect(activeOperation.nativeRequestId, isNotNull);
        expect(activeOperation.hasRetainedContext, isTrue);
        expect(activeOperation.contextOwnerId, isNotNull);
        expect(activeOperation.kind, RuntimeOperationKind.interactive);
        final acknowledged = provider.stopSending();
        expect(provider.stopSending(), same(acknowledged));
        await acknowledged;
        phase('provider_stop_acknowledged');
        expect(provider.isSending, isFalse);
        expect(provider.requiresRecovery, isFalse);
        expect(completionCount, 0);
        expect(next.lastMetrics?.completionReason, 'cancelled');
        expect(next.operationSnapshot.hasNativeWork, isFalse);
        expect(next.operationSnapshot.kind, isNull);
        expect(next.operationSnapshot.hasRetainedContext, isTrue);
        expect(
          next.operationSnapshot.contextOwnerId,
          activeOperation.contextOwnerId,
        );
        expect(
          activeOperation.hasNativeWork,
          isTrue,
          reason: 'Previously captured snapshot is immutable',
        );
        final followup = Completer<String>();
        phase('provider_followup_begin');
        provider.onGenerationComplete = (text) {
          completionCount++;
          followup.complete(text);
        };
        await provider.startGeneration(
          messages: [
            Message(chatId: 1, role: MessageRole.user, content: 'Say hello.'),
          ],
          settings: settings.copyWith(maxTokens: 16),
        );
        expect(await followup.future, isNotEmpty);
        phase('provider_followup_completed');
        expect(completionCount, 1);
        expect(providerErrors, isEmpty);
        expect(provider.lastTokenCount, greaterThan(0));
        expect(provider.lastMetrics?.completionReason, isNot('cancelled'));
        expect(
          repositories,
          hasLength(2),
          reason: 'Interactive caller must reuse the prepared model',
        );

        // Caller disposal drains native generation, but must not dispose the
        // model-service owner borrowed by this provider.
        final closingText = Completer<void>();
        phase('provider_disposal_request_begin');
        provider.addListener(() {
          if (provider.streamText.isNotEmpty && !closingText.isCompleted) {
            closingText.complete();
          }
        });
        provider.onGenerationComplete = (_) => completionCount++;
        await provider.startGeneration(
          messages: [
            Message(
              chatId: 1,
              role: MessageRole.user,
              content:
                  'Write a long numbered list of harmless household objects.',
            ),
          ],
          settings: settings,
        );
        await closingText.future;
        phase('provider_disposal_text_observed');
        expect(next.operationSnapshot.hasNativeWork, isTrue);
        final closing = provider.close();
        expect(provider.close(), same(closing));
        provider.dispose();
        await closing;
        phase('provider_close_acknowledged');
        expect(provider.requiresRecovery, isFalse);
        expect(completionCount, 1);
        expect(next.lastMetrics?.completionReason, 'cancelled');
        expect(next.operationSnapshot.hasNativeWork, isFalse);
        expect(next.isDisposed, isFalse);
        expect(service.isDisposed, isFalse);
        expect(service.repository, same(next));
        await for (final _ in next.streamChatWithGenerationOptions(
          'fixture',
          messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
          generationOptions: const GenerationOptions(
            maxTokens: 16,
            temperature: 0,
          ),
        )) {}
        expect(next.lastMetrics?.generatedTokens, greaterThan(0));
        expect(next.lastMetrics?.completionReason, isNot('cancelled'));
        expect(providerErrors, isEmpty);
        phase('final_direct_inference_completed');
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}

class _PreparationObservedRepository extends LlamaCppChatRepository {
  _PreparationObservedRepository(
    super.modelPath, {
    required super.contextSize,
    required super.batchSize,
    required super.threads,
    super.promptThreads,
    required super.nGpuLayers,
    required super.runtimeOperationKind,
    required this.preparationStarted,
  }) : super.withModelPath();

  final Completer<void> preparationStarted;

  @override
  Future<void> prepare({RuntimeOperationKind? kind}) {
    final operation = super.prepare(kind: kind);
    if (!preparationStarted.isCompleted) preparationStarted.complete();
    return operation;
  }
}

class _ObservedRepository extends LlamaCppChatRepository {
  _ObservedRepository(
    super.modelPath, {
    required super.contextSize,
    required super.batchSize,
    required super.threads,
    super.promptThreads,
    required super.nGpuLayers,
    required super.runtimeOperationKind,
    required this.visible,
  }) : super.withModelPath();
  final Completer<void> visible;
  final stopRequested = Completer<void>();

  @override
  Future<void> cancelActiveInference() {
    if (!stopRequested.isCompleted) stopRequested.complete();
    return super.cancelActiveInference();
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
      if (chunk.done != true &&
          (chunk.message?.content?.isNotEmpty ?? false) &&
          !visible.isCompleted) {
        visible.complete();
      }
      yield chunk;
    }
  }
}

class _Registry extends ModelRegistryService {
  _Registry(this.model);
  final ModelDescriptor model;
  @override
  Future<ModelDescriptor?> findById(String id) async =>
      id == model.id ? model : null;
  @override
  Future<ModelDescriptor?> findByPath(String path) async =>
      path == model.localPath ? model : null;
}

class _ProfileStore implements RuntimeProfileStore {
  @override
  Future<bool> writeIfCurrent(
    RuntimeProfileKey key,
    RuntimeProfile profile, {
    required bool Function() isCurrent,
    String? fallbackReason,
  }) async {
    if (!isCurrent()) return false;
    writes++;
    return true;
  }

  int writes = 0;
  @override
  Future<StoredRuntimeProfile?> read(RuntimeProfileKey key) async => null;
  @override
  Future<void> write(
    RuntimeProfileKey key,
    RuntimeProfile profile, {
    String? fallbackReason,
  }) async {
    writes++;
  }

  @override
  Future<void> invalidate(RuntimeProfileKey key) async {}
  @override
  Future<void> invalidateModel(String modelSha256) async {}
}

class _SafeSentinel implements HardwareSentinelService {
  @override
  bool isSafeForHeavyOperation() => true;
  @override
  String? unsafeReasonHeavy() => null;
  @override
  Stream<bool> get onHealthChanged =>
      Stream<bool>.multi((_) {}, isBroadcast: true);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DynamicSentinel extends _SafeSentinel {
  bool safe = true;
  final health = StreamController<bool>.broadcast(sync: true);
  @override
  bool isSafeForHeavyOperation() => safe;
  @override
  String? unsafeReasonHeavy() => safe ? null : 'simulated critical pressure';
  @override
  Stream<bool> get onHealthChanged => health.stream;
}

class _Capabilities implements RuntimeCapabilitiesProvider {
  @override
  Future<RuntimeCapabilities> snapshot() async => const RuntimeCapabilities(
    logicalProcessors: 2,
    performanceProcessors: 1,
    deviceFingerprint: 'native-preemption-fixture',
    abis: ['x86_64'],
    packagedBackends: {'cpu'},
    availableMemoryBytes: 4 * 1024 * 1024 * 1024,
    thermalStatus: null,
    lowMemory: null,
  );
}
