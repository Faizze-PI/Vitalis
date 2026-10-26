import 'dart:async';
import 'dart:io';
import 'dart:ffi' as ffi;

import 'preparation_cancellation_cases.dart';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/native_runtime_bridge.dart';
import 'package:llm_llamacpp/src/loader/loader.dart';
import 'package:llm_llamacpp/src/persistent_inference_isolate.dart';
import 'package:llm_llamacpp/src/isolate_messages.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/models/model_descriptor.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/runtime_profile.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/providers/generation_provider.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/services/model_warmup_service.dart';
import 'package:vitalis_app/services/chat_state_controller.dart';
import 'package:vitalis_app/models/generation_watchdog_policy.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/services/startup_access_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerPreparationCancellationCases();
  test(
    'readiness revocation stops real generation before safe followup admission',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final readiness = ValueNotifier(StartupModelReadiness.ready);
      final owner = LlamaCppChatRepository.withModelPath(
        path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      final controller = ChatStateController(sentinel: _SafeSentinel());
      final provider = GenerationProvider(
        controller: controller,
        warmup: _ProviderWarmup(owner),
        startupAccess: StartupAccessGuard(
          () => StartupCapabilities(
            databaseReady: true,
            migrationReady: true,
            safetyReady: true,
            modelReadiness: readiness.value,
          ),
          changes: readiness,
        ),
      );
      addTearDown(() async {
        await provider.close();
        await owner.close();
        readiness.dispose();
      });
      final firstText = Completer<void>();
      final lateVisible = <String>[];
      final errors = <String>[];
      var revoked = false;
      var completions = 0;
      provider.onGenerationComplete = (_) => completions++;
      provider.onError = errors.add;
      provider.addListener(() {
        if (provider.streamText.isNotEmpty && !firstText.isCompleted)
          firstText.complete();
        if (revoked && provider.streamText.isNotEmpty)
          lateVisible.add(provider.streamText);
      });
      await owner.prepare();
      await provider.startGeneration(
        messages: [
          Message(
            chatId: 1,
            role: MessageRole.user,
            content:
                'Write a long numbered list of harmless household objects.',
          ),
        ],
        settings: ModelSettings(maxTokens: 256),
      );
      await firstText.future;
      final beforeRevocation = provider.streamText;
      expect(owner.operationSnapshot.hasNativeWork, isTrue);
      revoked = true;
      readiness.value = StartupModelReadiness.missing;
      await provider.stopSending();
      expect(owner.operationSnapshot.hasNativeWork, isFalse);
      expect(owner.lastMetrics?.completionReason, 'cancelled');
      expect(
        owner.lastMetrics?.cancellationAcknowledgementMicros,
        greaterThan(0),
      );
      expect(provider.isSending, isFalse);
      expect(provider.requiresRecovery, isFalse);
      expect(completions, 0);
      expect(lateVisible.every((text) => text == beforeRevocation), isTrue);
      await expectLater(
        provider.startGeneration(
          messages: [
            Message(
              chatId: 1,
              role: MessageRole.user,
              content: 'Blocked fixture',
            ),
          ],
          settings: ModelSettings(maxTokens: 8),
        ),
        throwsA(isA<StartupAccessDenied>()),
      );
      expect(owner.operationSnapshot.hasNativeWork, isFalse);
      expect(errors, hasLength(1));
      expect(errors.single, contains('readiness'));
      expect(provider.hasError, isTrue);
      errors.clear();
      readiness.value = StartupModelReadiness.ready;
      revoked = false;
      final finished = Completer<void>();
      final observed = expectLater(finished.future, completes);
      provider.onGenerationComplete = (_) {
        completions++;
        if (!finished.isCompleted) finished.complete();
      };
      provider.onError = (error) {
        errors.add(error);
        if (!finished.isCompleted) finished.completeError(StateError(error));
      };
      await provider.startGeneration(
        messages: [
          Message(
            chatId: 1,
            role: MessageRole.user,
            content: 'Say hello briefly.',
          ),
        ],
        settings: ModelSettings(maxTokens: 16),
      );
      await observed;
      expect(completions, 1);
      expect(errors, isEmpty);
      expect(owner.lastMetrics?.generatedTokens, greaterThan(0));
      expect(owner.lastMetrics?.completionReason, isNot('cancelled'));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'legacy backend and loader cannot bypass another context owner',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final owner = LlamaCppChatRepository.withModelPath(
        path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      final competitor = LlamaCppChatRepository();
      addTearDown(() async {
        await competitor.close();
        await owner.close();
      });
      await owner.prepare();
      final held = owner.operationSnapshot.contextOwnerId;
      expect(
        competitor.initializeBackend,
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      await expectLater(
        competitor.loadModel(path),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      expect(
        competitor.retainOwnedRecovery,
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      expect(owner.operationSnapshot.contextOwnerId, held);
      await for (final _ in owner.streamChatWithGenerationOptions(
        'legacy-contention-fixture',
        messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
        generationOptions: const GenerationOptions(maxTokens: 8),
      )) {}
      expect(owner.lastMetrics?.generatedTokens, greaterThan(0));
      expect(owner.operationSnapshot.contextOwnerId, held);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'oversized native prompt fails before decode and permits owner reuse',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final runtime = PersistentInferenceIsolate.instance;
      final owner = Object();
      final competitor = Object();
      addTearDown(() => runtime.releaseOwnedContext(owner));
      await runtime.prepare(
        modelPath: path,
        contextSize: 2048,
        batchSize: 128,
        nGpuLayers: 0,
        threads: 2,
        owner: owner,
      );
      final held = runtime.operationSnapshot.contextOwnerId;
      final oversized = List.filled(3000, 'hello').join(' ');
      final messages = [IsolateMessage(role: 'user', content: oversized)];
      expect(
        await runtime.countChatTokens(messages, owner: owner),
        greaterThan(2048),
        reason: 'Fixture must actually exceed the selected native context',
      );
      Stream<dynamic> generate(List<IsolateMessage> input) =>
          runtime.runInference(
            modelPath: path,
            prompt: '',
            messages: input,
            stopTokens: const [],
            contextSize: 2048,
            batchSize: 128,
            nGpuLayers: 0,
            options: const GenerationOptions(maxTokens: 8),
            owner: owner,
          );
      final rejected = await generate(messages).toList();
      expect(rejected.whereType<InferenceError>(), hasLength(1));
      expect(
        rejected.whereType<InferenceError>().single.error,
        contains('Prompt requires'),
      );
      expect(rejected.whereType<InferenceComplete>(), isEmpty);
      expect(rejected.whereType<InferenceToken>(), isEmpty);
      await runtime.drainOwner(owner);
      expect(runtime.operationSnapshot.contextOwnerId, held);
      await expectLater(
        runtime.prepare(
          modelPath: path,
          contextSize: 2048,
          batchSize: 128,
          nGpuLayers: 0,
          owner: competitor,
        ),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      final recovered = await generate(const [
        IsolateMessage(role: 'user', content: 'Say hello.'),
      ]).toList();
      expect(recovered.whereType<InferenceError>(), isEmpty);
      expect(recovered.whereType<InferenceComplete>(), hasLength(1));
      await runtime.releaseOwnedContext(owner);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'unprepared tokenization and missing model retain owner until cleanup',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final directory = await Directory.systemTemp.createTemp(
        'vitalis-missing-',
      );
      final runtime = PersistentInferenceIsolate.instance;
      final owner = Object();
      final competitor = Object();
      addTearDown(() async {
        if (runtime.canAccess(owner)) await runtime.releaseOwnedContext(owner);
        if (runtime.canAccess(competitor)) {
          await runtime.releaseOwnedContext(competitor);
        }
        await directory.delete();
      });
      await expectLater(
        runtime.countChatTokens(const [
          IsolateMessage(role: 'user', content: 'Hello.'),
        ], owner: owner),
        throwsA(isA<StateError>()),
      );
      final held = runtime.operationSnapshot.contextOwnerId;
      expect(held, isNotNull);
      Future<void> prepare(String model, Object identity) => runtime.prepare(
        modelPath: model,
        contextSize: 2048,
        batchSize: 128,
        nGpuLayers: 0,
        threads: 2,
        owner: identity,
      );
      await expectLater(
        prepare(path, competitor),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      await expectLater(
        prepare(
          '${directory.path}${Platform.pathSeparator}missing.gguf',
          owner,
        ),
        throwsA(isA<StateError>()),
      );
      expect(runtime.operationSnapshot.contextOwnerId, held);
      await runtime.releaseOwnedContext(owner);
      expect(runtime.operationSnapshot.hasRetainedContext, isFalse);
      await prepare(path, competitor);
      expect(
        await runtime.countChatTokens(const [
          IsolateMessage(role: 'user', content: 'Hello.'),
        ], owner: competitor),
        greaterThan(0),
      );
      final events = await runtime
          .runInference(
            modelPath: path,
            prompt: '',
            messages: const [
              IsolateMessage(role: 'user', content: 'Say hello.'),
            ],
            stopTokens: const [],
            contextSize: 2048,
            batchSize: 128,
            nGpuLayers: 0,
            options: const GenerationOptions(maxTokens: 8),
            owner: competitor,
          )
          .toList();
      expect(events.whereType<InferenceError>(), isEmpty);
      expect(events.whereType<InferenceComplete>(), hasLength(1));
      await runtime.releaseOwnedContext(competitor);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'helper shutdown rejects owned context and restarts after acknowledged unload',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final runtime = PersistentInferenceIsolate.instance;
      final owner = Object();
      final successor = Object();
      Future<void> prepare(Object identity) => runtime.prepare(
        modelPath: path,
        contextSize: 2048,
        batchSize: 128,
        nGpuLayers: 0,
        threads: 2,
        owner: identity,
      );
      addTearDown(() async {
        if (runtime.canAccess(owner)) await runtime.releaseOwnedContext(owner);
        if (runtime.canAccess(successor)) {
          await runtime.releaseOwnedContext(successor);
        }
      });
      await prepare(owner);
      final held = runtime.operationSnapshot.contextOwnerId;
      expect(runtime.dispose, throwsA(isA<InferenceRuntimeBusy>()));
      expect(runtime.operationSnapshot.contextOwnerId, held);
      await expectLater(
        prepare(successor),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      await runtime.releaseOwnedContext(owner);
      expect(runtime.operationSnapshot.hasRetainedContext, isFalse);
      // Explicit shutdown is allowed only after acknowledged native unloading.
      runtime.dispose();
      await prepare(successor);
      final events = await runtime
          .runInference(
            modelPath: path,
            prompt: '',
            messages: const [
              IsolateMessage(role: 'user', content: 'Say hello.'),
            ],
            stopTokens: const [],
            contextSize: 2048,
            batchSize: 128,
            nGpuLayers: 0,
            options: const GenerationOptions(maxTokens: 8),
            owner: successor,
          )
          .toList();
      expect(events.whereType<InferenceError>(), isEmpty);
      expect(events.whereType<InferenceComplete>(), hasLength(1));
      await runtime.releaseOwnedContext(successor);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'revoked context owner cannot start work but can finish cleanup',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final runtime = PersistentInferenceIsolate.instance;
      final owner = Object();
      final competitor = Object();
      Future<void> prepare(Object identity) => runtime.prepare(
        modelPath: path,
        contextSize: 2048,
        batchSize: 128,
        nGpuLayers: 0,
        threads: 2,
        owner: identity,
      );
      addTearDown(() async {
        if (runtime.canAccess(owner)) await runtime.releaseOwnedContext(owner);
        if (runtime.canAccess(competitor)) {
          await runtime.releaseOwnedContext(competitor);
        }
      });
      await prepare(owner);
      final held = runtime.operationSnapshot.contextOwnerId;
      runtime.revokeOwner(owner);
      await expectLater(
        prepare(owner),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
      await expectLater(
        runtime.countChatTokens(const [
          IsolateMessage(role: 'user', content: 'Say hello.'),
        ], owner: owner),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
      await expectLater(
        runtime.withExclusiveSession(owner, () async => fail('revoked action')),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
      await expectLater(
        runtime
            .runInference(
              modelPath: path,
              prompt: 'Say hello.',
              stopTokens: const [],
              contextSize: 2048,
              batchSize: 128,
              nGpuLayers: 0,
              options: const GenerationOptions(maxTokens: 8),
              owner: owner,
            )
            .toList(),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
      expect(runtime.operationSnapshot.contextOwnerId, held);
      await expectLater(
        prepare(competitor),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      await runtime.releaseOwnedContext(owner);
      expect(runtime.operationSnapshot.hasRetainedContext, isFalse);
      await prepare(competitor);
      final events = await runtime
          .runInference(
            modelPath: path,
            prompt: '',
            messages: const [
              IsolateMessage(role: 'user', content: 'Say hello.'),
            ],
            stopTokens: const [],
            contextSize: 2048,
            batchSize: 128,
            nGpuLayers: 0,
            options: const GenerationOptions(maxTokens: 8),
            owner: competitor,
          )
          .toList();
      expect(events.whereType<InferenceError>(), isEmpty);
      expect(events.whereType<InferenceComplete>(), hasLength(1));
      await runtime.releaseOwnedContext(competitor);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'repository close expiry retains real context until explicit recovery',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final timers = <_AcknowledgementTimer>[];
      final owner = _DelayedRepositoryClose(path, (_, callback) {
        final timer = _AcknowledgementTimer(callback);
        timers.add(timer);
        return timer;
      });
      final competitor = LlamaCppChatRepository.withModelPath(
        path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      void expireWaiting() {
        for (final timer in timers.toList()) {
          if (timer.isActive) timer.fire();
        }
      }

      addTearDown(() async {
        owner.releaseAcknowledgement();
        if (owner.cleanupFailed) await owner.recoverAfterClose();
        await owner.close();
        await competitor.close();
      });
      await owner.prepare();
      final closing = owner.close();
      final failed = expectLater(
        closing,
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      expireWaiting();
      await failed;
      expect(owner.cleanupFailed, isTrue);
      expect(owner.operationSnapshot.requiresRecovery, isTrue);
      expect(owner.operationSnapshot.hasRetainedContext, isTrue);
      await expectLater(
        competitor.prepare(),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      final pendingRecovery = owner.recoverAfterClose();
      expireWaiting();
      expect(
        await pendingRecovery,
        RuntimeRecoveryOutcome.terminationUnconfirmed,
      );
      expect(owner.cancelCalls, 1);
      owner.releaseAcknowledgement();
      await Future<void>(() {});
      expect(owner.cleanupFailed, isTrue);
      expect(owner.operationSnapshot.requiresRecovery, isTrue);
      expect(owner.operationSnapshot.hasRetainedContext, isTrue);
      final recovery = owner.recoverAfterClose();
      expect(owner.recoverAfterClose(), same(recovery));
      expect(await recovery, RuntimeRecoveryOutcome.recovered);
      expect(owner.operationSnapshot.hasRetainedContext, isFalse);
      expect(owner.cleanupFailed, isFalse);
      expect(owner.isDisposed, isTrue);
      await owner.close();
      await expectLater(closing, throwsA(isA<InferenceRecoveryRequired>()));
      await expectLater(
        owner.prepare(),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
      await competitor.prepare();
      await for (final _ in competitor.streamChatWithGenerationOptions(
        'after-disposed-owner-recovery',
        messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
        generationOptions: const GenerationOptions(maxTokens: 16),
      )) {}
      expect(competitor.lastMetrics?.generatedTokens, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'cached warmup restores context unloaded by owner recovery',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final service = ModelWarmupService(
        sentinel: _SafeSentinel(),
        modelRegistry: _FixtureRegistry(path),
      );
      addTearDown(service.close);
      const profile = RuntimeProfile(
        contextSize: 2048,
        reservedOutputTokens: 64,
        generationThreads: 2,
        promptThreads: 2,
        batchSize: 128,
        gpuLayers: 0,
        thinkingMode: ThinkingMode.off,
      );
      final owner = await service.ensureProfile(
        profile,
        modelId: BundledModelManifest.id,
      );
      owner.retainOwnedRecovery();
      expect(
        await owner.recoverOwnedSession(),
        RuntimeRecoveryOutcome.recovered,
      );
      expect(owner.operationSnapshot.hasRetainedContext, isFalse);
      final restored = await service.ensureProfile(
        profile,
        modelId: BundledModelManifest.id,
      );
      expect(restored, same(owner));
      expect(restored.operationSnapshot.hasRetainedContext, isTrue);
      expect(
        await restored.countChatTokens([
          LLMMessage(role: LLMRole.user, content: 'Say hello.'),
        ]),
        greaterThan(0),
      );
      await for (final _ in restored.streamChatWithGenerationOptions(
        'cached-recovered-context',
        messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
        generationOptions: const GenerationOptions(maxTokens: 16),
      )) {}
      expect(restored.lastMetrics?.generatedTokens, greaterThan(0));
      expect(service.repository, same(owner));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'expired controller Stop retains real owner until explicit recovery',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final repository = _DelayedCancellationRepository(path);
      final competitor = LlamaCppChatRepository.withModelPath(
        path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      final timers = <_AcknowledgementTimer>[];
      final controller = ChatStateController(
        sentinel: _SafeSentinel(),
        watchdogPolicy: const GenerationWatchdogPolicy(
          noProgressTimeout: Duration.zero,
          maximumRequestDuration: Duration.zero,
        ),
        watchdogTimerFactory: (_, callback) {
          final timer = _AcknowledgementTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      void expireWaiting() {
        for (final timer in timers.toList()) {
          if (timer.isActive) timer.fire();
        }
      }

      addTearDown(() async {
        repository.releaseAcknowledgement();
        if (controller.cleanupFailed) await controller.recoverOwnedCleanup();
        await controller.close();
        await repository.close();
        await competitor.close();
      });
      await repository.prepare();
      final visible = Completer<void>();
      controller.onToken = (token) {
        if (token.isNotEmpty && !visible.isCompleted) visible.complete();
      };
      controller.onError = (_) {
        if (!visible.isCompleted) {
          visible.completeError(
            StateError('Native fixture did not reach output'),
          );
        }
      };
      await controller.startGeneration(
        repository: repository,
        messages: [
          LLMMessage(
            role: LLMRole.user,
            content:
                'Write a long numbered list of harmless household objects.',
          ),
        ],
        options: const GenerationOptions(maxTokens: 256),
      );
      await visible.future;
      final stopping = controller.cancelInference();
      expireWaiting();
      await stopping;
      expect(controller.status, ChatStatus.error);
      expect(controller.cleanupFailed, isTrue);
      expect(repository.operationSnapshot.requiresRecovery, isTrue);
      expect(repository.cancelCalls, 1);
      await expectLater(
        competitor.prepare(),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      await expectLater(
        repository.countChatTokens([
          LLMMessage(role: LLMRole.user, content: 'Do not start new work.'),
        ]),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      final pendingRecovery = controller.recoverOwnedCleanup();
      expireWaiting();
      expect(
        await pendingRecovery,
        RuntimeRecoveryOutcome.terminationUnconfirmed,
      );
      expect(repository.cancelCalls, 1);
      // The fixture delays the Dart acknowledgement after actual native Stop;
      // it is not a native deadlock or a two-second cancellation measurement.
      await repository.nativeCancellationSettled.future;
      repository.releaseAcknowledgement();
      await Future<void>(() {});
      expect(repository.lastMetrics?.completionReason, 'cancelled');
      expect(
        repository.lastMetrics?.cancellationAcknowledgementMicros,
        isNotNull,
      );
      expect(controller.cleanupFailed, isTrue);
      expect(repository.operationSnapshot.requiresRecovery, isTrue);
      expect(
        await controller.recoverOwnedCleanup(),
        RuntimeRecoveryOutcome.recovered,
      );
      expect(controller.status, ChatStatus.idle);
      expect(repository.cancelCalls, 1);
      expect(repository.operationSnapshot.requiresRecovery, isFalse);
      expect(repository.operationSnapshot.hasNativeWork, isFalse);
      await controller.close();
      await repository.close();
      await competitor.prepare();
      await for (final _ in competitor.streamChatWithGenerationOptions(
        'after-expired-acknowledgement',
        messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
        generationOptions: const GenerationOptions(maxTokens: 16),
      )) {}
      expect(competitor.lastMetrics?.generatedTokens, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test('packaged bridge retains the receiver token after helper release', () {
    final bridge = NativeRuntimeBridge(loadLlamaLibrary());
    final token = bridge.createCancelToken();
    expect(token, isNot(ffi.nullptr));
    bridge.retainCancelToken(token);
    bridge.destroyCancelToken(token); // Helper reference has ended.
    try {
      bridge.requestCancel(token);
      expect(bridge.isCancelRequested(token), isTrue);
      expect(bridge.isCancelAcknowledged(token), isTrue);
    } finally {
      bridge.destroyCancelToken(token); // Receiver reference ends last.
    }
  });

  test(
    'preparation deadline retains real native work until owner unload acknowledges',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final invalid = LlamaCppChatRepository.withModelPath(
        path,
        preparationWatchdogPolicy: const RuntimeWatchdogPolicy(
          noProgressTimeout: Duration(seconds: -1),
          maximumDuration: Duration.zero,
        ),
      );
      await expectLater(invalid.prepare(), throwsArgumentError);
      expect(invalid.operationSnapshot.hasNativeWork, isFalse);
      expect(invalid.operationSnapshot.hasRetainedContext, isFalse);
      await invalid.close();
      final owner = LlamaCppChatRepository.withModelPath(
        path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
        preparationWatchdogPolicy: const RuntimeWatchdogPolicy(
          noProgressTimeout: Duration.zero,
          maximumDuration: Duration.zero,
        ),
      );
      final next = LlamaCppChatRepository.withModelPath(
        path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      addTearDown(owner.close);
      addTearDown(next.close);
      final original = owner.prepare();
      await expectLater(original, throwsA(isA<InferenceRecoveryRequired>()));
      expect(
        owner.operationSnapshot.initializationPending,
        isTrue,
        reason:
            'Must observe genuinely unfinished native preparation, not skip the boundary',
      );
      expect(owner.operationSnapshot.requiresRecovery, isTrue);
      await expectLater(next.prepare(), throwsA(isA<InferenceRuntimeBusy>()));
      await expectLater(
        owner.countChatTokens([
          LLMMessage(role: LLMRole.user, content: 'Hello'),
        ]),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      await owner.close();
      expect(owner.operationSnapshot.hasNativeWork, isFalse);
      expect(owner.operationSnapshot.initializationRecoveryRequired, isFalse);
      expect(owner.operationSnapshot.requiresRecovery, isFalse);
      await expectLater(original, throwsA(isA<InferenceRecoveryRequired>()));
      await next.prepare();
      await for (final _ in next.streamChatWithGenerationOptions(
        'after-preparation-timeout',
        messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
        generationOptions: const GenerationOptions(maxTokens: 16),
      )) {}
      expect(next.lastMetrics?.generatedTokens, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'Stop at first native progress aborts subsequent decoding',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final owner = LlamaCppChatRepository.withModelPath(
        path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      addTearDown(owner.close);
      Future<void>? stopping;
      var requestedWithHandle = false;
      var visibleChunks = 0;
      await for (final chunk in owner.streamChatWithGenerationOptions(
        'early-stop-fixture',
        messages: [
          LLMMessage(
            role: LLMRole.user,
            content: 'Write a long list of harmless household objects.',
          ),
        ],
        generationOptions: const GenerationOptions(maxTokens: 128),
      )) {
        if (chunk is LlamaCppProgressChunk && stopping == null) {
          requestedWithHandle =
              owner.operationSnapshot.cancellationHandleAvailable;
          expect(
            requestedWithHandle,
            isTrue,
            reason:
                'Cancellation must be published before native loading progress',
          );
          stopping = owner.cancelActiveInference();
        } else if (chunk.message?.content?.isNotEmpty ?? false) {
          visibleChunks++;
        }
      }
      await stopping;
      expect(requestedWithHandle, isTrue);
      expect(visibleChunks, 0);
      expect(owner.lastMetrics?.completionReason, 'cancelled');
      expect(owner.lastMetrics?.cancellationAcknowledgementMicros, isNotNull);
      expect(owner.operationSnapshot.hasNativeWork, isFalse);
      expect(owner.operationSnapshot.cancellationHandleAvailable, isFalse);
      await for (final _ in owner.streamChatWithGenerationOptions(
        'after-early-stop-fixture',
        messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
        generationOptions: const GenerationOptions(maxTokens: 16),
      )) {}
      expect(owner.lastMetrics?.generatedTokens, greaterThan(0));
      expect(owner.lastMetrics?.completionReason, isNot('cancelled'));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'above-batch prompt and token decoding emit ordered native progress',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final owner = LlamaCppChatRepository.withModelPath(
        path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      addTearDown(owner.close);
      final progress = <RuntimeProgress>[];
      var visibleChunks = 0;
      await for (final chunk in owner.streamChatWithGenerationOptions(
        'native-progress-fixture',
        messages: [
          LLMMessage(
            role: LLMRole.user,
            content: '${List.filled(320, 'object').join(' ')}\nSay hello.',
          ),
        ],
        generationOptions: const GenerationOptions(maxTokens: 16),
      )) {
        if (chunk is LlamaCppProgressChunk) {
          progress.add(chunk.progress);
          expect(chunk.message, isNull);
        } else if (chunk.message?.content?.isNotEmpty ?? false) {
          visibleChunks++;
        }
      }
      expect(progress, isNotEmpty);
      final tracker = RuntimeProgressTracker();
      expect(progress.every(tracker.accept), isTrue);
      expect(progress.map((event) => event.requestId).toSet(), hasLength(1));
      final promptProgress = progress
          .where(
            (event) => event.phase == RuntimeProgressPhase.promptEvaluating,
          )
          .toList();
      expect(promptProgress.length, greaterThan(2));
      expect(
        promptProgress.last.completedUnits,
        owner.lastMetrics?.promptTokens,
      );
      final tokenProgress = progress
          .where((event) => event.phase == RuntimeProgressPhase.tokenDecoding)
          .toList();
      expect(tokenProgress, isNotEmpty);
      expect(
        tokenProgress.last.completedUnits,
        owner.lastMetrics?.generatedTokens,
      );
      expect(visibleChunks, greaterThan(0));
      expect(progress.last.phase, RuntimeProgressPhase.requestCleanup);
      expect(progress.last.completedUnits, 1);
      expect(owner.operationSnapshot.hasNativeWork, isFalse);
      expect(owner.operationSnapshot.cancellationHandleAvailable, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'provider recovers failed Stop before a subsequent native request',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final owner = _FailingCancellationRepository(path);
      final controller = ChatStateController(sentinel: _SafeSentinel());
      final provider = GenerationProvider(
        controller: controller,
        warmup: _ProviderWarmup(owner),
      );
      addTearDown(() async {
        owner.rejectCancellation = false;
        if (provider.requiresRecovery) await provider.recoverOwnedCleanup();
        await provider.close();
        await owner.close();
      });
      await owner.prepare();
      final emitted = Completer<void>();
      provider.addListener(() {
        if (provider.streamText.isNotEmpty && !emitted.isCompleted)
          emitted.complete();
      });
      await provider.startGeneration(
        messages: [
          Message(
            chatId: 1,
            role: MessageRole.user,
            content:
                'Write a long numbered list of harmless household objects.',
          ),
        ],
        settings: ModelSettings(maxTokens: 256),
      );
      await emitted.future;
      final failedStop = provider.stopSending();
      await expectLater(failedStop, throwsA(isA<InferenceRecoveryRequired>()));
      final visible = provider.streamText;
      expect(
        await provider.recoverOwnedCleanup(),
        RuntimeRecoveryOutcome.terminationUnconfirmed,
      );
      owner.rejectCancellation = false;
      final recovery = provider.recoverOwnedCleanup();
      expect(provider.recoverOwnedCleanup(), same(recovery));
      expect(await recovery, RuntimeRecoveryOutcome.recovered);
      expect(provider.requiresRecovery, isFalse);
      expect(owner.operationSnapshot.hasNativeWork, isFalse);
      expect(owner.lastMetrics?.cancellationAcknowledgementMicros, isNotNull);
      expect(owner.lastMetrics?.completionReason, 'cancelled');
      expect(owner.isDisposed, isFalse);
      expect(visible, isNotEmpty);
      expect(provider.streamText, isEmpty);
      await expectLater(failedStop, throwsA(isA<InferenceRecoveryRequired>()));
      final finished = Completer<void>();
      provider.onGenerationComplete = (_) => finished.complete();
      provider.onError = (error) => finished.completeError(StateError(error));
      await provider.startGeneration(
        messages: [
          Message(chatId: 1, role: MessageRole.user, content: 'Say hello.'),
        ],
        settings: ModelSettings(maxTokens: 16),
      );
      await finished.future;
      expect(owner.lastMetrics?.generatedTokens, greaterThan(0));
      expect(owner.lastMetrics?.completionReason, isNot('cancelled'));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'controller recovers its failed native request without retiring the borrowed model',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final owner = _FailingCancellationRepository(path);
      final controller = ChatStateController(sentinel: _SafeSentinel());
      addTearDown(() async {
        owner.rejectCancellation = false;
        await controller.close();
        await owner.close();
      });
      await owner.prepare();
      final emitted = Completer<void>();
      final errors = <String>[];
      var chunks = 0;
      controller.onToken = (_) {
        chunks++;
        if (!emitted.isCompleted) emitted.complete();
      };
      controller.onError = errors.add;
      await controller.startGeneration(
        repository: owner,
        messages: [
          LLMMessage(
            role: LLMRole.user,
            content:
                'Write a long numbered list of harmless household objects.',
          ),
        ],
        options: const GenerationOptions(maxTokens: 256),
      );
      await emitted.future;
      await controller.cancelInference();
      final visibleBeforeRecovery = chunks;
      expect(controller.cleanupFailed, isTrue);
      expect(
        await controller.recoverOwnedCleanup(),
        RuntimeRecoveryOutcome.terminationUnconfirmed,
      );
      expect(controller.cleanupFailed, isTrue);
      owner.rejectCancellation = false;
      final recovery = controller.recoverOwnedCleanup();
      expect(controller.recoverOwnedCleanup(), same(recovery));
      expect(await recovery, RuntimeRecoveryOutcome.recovered);
      expect(controller.cleanupFailed, isFalse);
      expect(owner.isDisposed, isFalse);
      expect(owner.lastMetrics?.completionReason, 'cancelled');
      expect(owner.operationSnapshot.hasNativeWork, isFalse);
      expect(chunks, visibleBeforeRecovery);
      final finished = Completer<void>();
      controller.onComplete = finished.complete;
      await controller.startGeneration(
        repository: owner,
        messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
        options: const GenerationOptions(maxTokens: 16),
      );
      await finished.future;
      expect(owner.lastMetrics?.generatedTokens, greaterThan(0));
      expect(owner.lastMetrics?.completionReason, isNot('cancelled'));
      expect(errors, everyElement(contains('not acknowledged')));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'disposal after finalized native text suppresses later completion',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      final fixture = File(path!);
      expect(
        (await sha256.bind(fixture.openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final repository = LlamaCppChatRepository.withModelPath(
        path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      addTearDown(repository.close);
      await repository.prepare();
      var reachedBoundary = false;
      var deliveredAfterDisposal = 0;
      Future<void>? retiring;
      final drained = Completer<void>();
      final errors = <Object>[];
      final subscription = repository
          .streamChatWithGenerationOptions(
            'completion-disposal-boundary',
            messages: [
              LLMMessage(
                role: LLMRole.user,
                content:
                    'Output one character only: an opening curly brace. Do not close it. No prose. No code fence.',
              ),
            ],
            generationOptions: const GenerationOptions(
              maxTokens: 128,
              temperature: 0,
              seed: 20261006,
            ),
          )
          .listen(
            (chunk) {
              if (reachedBoundary) {
                deliveredAfterDisposal++;
                return;
              }
              // An incomplete brace is buffered by the actual product formatter until
              // native completion. Metrics distinguish it from an ordinary token.
              if (repository.lastMetrics != null &&
                  (chunk.message?.content?.contains('{') ?? false)) {
                reachedBoundary = true;
                retiring = repository.close();
              }
            },
            onError: (Object error) => errors.add(error),
            onDone: drained.complete,
          );
      addTearDown(subscription.cancel);
      await drained.future;
      await retiring;
      expect(errors, isEmpty);
      expect(
        reachedBoundary,
        isTrue,
        reason:
            'Fixture must reach completion finalization; unavailable boundary is not a product pass',
      );
      expect(
        deliveredAfterDisposal,
        0,
        reason:
            'Completion must recheck disposal after yielding finalized text',
      );
      expect(repository.lastMetrics?.generatedTokens, greaterThan(0));
      expect(repository.isDisposed, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'failed owner cleanup stays quarantined until native unload acknowledges',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      final fixture = File(path!);
      expect(
        (await sha256.bind(fixture.openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final owner = _FailingCancellationRepository(path);
      final next = LlamaCppChatRepository.withModelPath(
        path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      addTearDown(() async {
        owner.rejectCancellation = false;
        if (owner.cleanupFailed) await owner.recoverAfterClose();
        await owner.close();
        await next.close();
      });
      await owner.prepare();
      final emitted = Completer<void>();
      final drained = Completer<void>();
      final errors = <Object>[];
      final subscription = owner
          .streamChatWithGenerationOptions(
            'close-recovery-fixture',
            messages: [
              LLMMessage(
                role: LLMRole.user,
                content:
                    'Write a long numbered list of harmless household objects.',
              ),
            ],
            generationOptions: const GenerationOptions(maxTokens: 256),
          )
          .listen(
            (chunk) {
              if ((chunk.message?.content?.isNotEmpty ?? false) &&
                  !emitted.isCompleted)
                emitted.complete();
            },
            onError: (Object error) {
              errors.add(error);
              if (!emitted.isCompleted) emitted.completeError(error);
            },
            onDone: () {
              if (!emitted.isCompleted)
                emitted.completeError(StateError('No visible native text'));
              drained.complete();
            },
          );
      addTearDown(subscription.cancel);
      await emitted.future;
      final originalClose = owner.close();
      await expectLater(originalClose, throwsStateError);
      expect(owner.close(), same(originalClose));
      expect(owner.cleanupFailed, isTrue);
      expect(owner.operationSnapshot.requiresRecovery, isTrue);
      final contextIdentity = owner.operationSnapshot.contextOwnerId;
      await expectLater(next.prepare(), throwsStateError);
      final unsuccessful = owner.recoverAfterClose();
      expect(owner.recoverAfterClose(), same(unsuccessful));
      expect(await unsuccessful, RuntimeRecoveryOutcome.terminationUnconfirmed);
      expect(owner.cleanupFailed, isTrue);
      expect(owner.operationSnapshot.requiresRecovery, isTrue);
      expect(owner.operationSnapshot.contextOwnerId, contextIdentity);
      owner.rejectCancellation = false;
      final successful = owner.recoverAfterClose();
      expect(owner.recoverAfterClose(), same(successful));
      expect(await successful, RuntimeRecoveryOutcome.recovered);
      await drained.future;
      expect(errors, isEmpty);
      expect(owner.lastMetrics?.completionReason, 'cancelled');
      expect(owner.lastMetrics?.cancellationAcknowledgementMicros, isNotNull);
      expect(owner.isDisposed, isTrue);
      expect(owner.cleanupFailed, isFalse);
      expect(owner.operationSnapshot.requiresRecovery, isFalse);
      expect(owner.operationSnapshot.hasRetainedContext, isFalse);
      await expectLater(
        owner.prepare(),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
      await expectLater(
        originalClose,
        throwsStateError,
        reason: 'Recovery must not rewrite the historical failed attempt',
      );
      await owner.close();
      await next.prepare();
      await for (final _ in next.streamChatWithGenerationOptions(
        'after-owner-recovery',
        messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
        generationOptions: const GenerationOptions(maxTokens: 16),
      )) {}
      expect(next.lastMetrics?.generatedTokens, greaterThan(0));
      expect(next.lastMetrics?.completionReason, isNot('cancelled'));
      expect(await fixture.exists(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'model service retires failed active owner before accepting a replacement',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      final fixture = File(path!);
      expect(
        (await sha256.bind(fixture.openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final repositories = <_FailingCancellationRepository>[];
      final service = ModelWarmupService(
        sentinel: _SafeSentinel(),
        modelRegistry: _FixtureRegistry(path),
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
              final repository = _FailingCancellationRepository(
                modelPath,
                runtimeOperationKind: runtimeOperationKind,
              )..rejectCancellation = repositories.isEmpty;
              repositories.add(repository);
              return repository;
            },
      );
      addTearDown(() async {
        for (final owner in repositories) {
          owner.rejectCancellation = false;
        }
        if (service.requiresRecovery) await service.recoverOwnedCleanup();
        await service.close();
      });
      const profile = RuntimeProfile(
        contextSize: 2048,
        reservedOutputTokens: 256,
        generationThreads: 2,
        promptThreads: 2,
        batchSize: 128,
        gpuLayers: 0,
        thinkingMode: ThinkingMode.off,
      );
      final owner = await service.ensureProfile(
        profile,
        modelId: BundledModelManifest.id,
      );
      final emitted = Completer<void>();
      final drained = Completer<void>();
      final errors = <Object>[];
      var deliveredChunks = 0;
      var deliveredCompletions = 0;
      final subscription = owner
          .streamChatWithGenerationOptions(
            'service-owner-recovery',
            messages: [
              LLMMessage(
                role: LLMRole.user,
                content:
                    'Write a long numbered list of harmless household objects.',
              ),
            ],
            generationOptions: const GenerationOptions(maxTokens: 256),
          )
          .listen(
            (chunk) {
              deliveredChunks++;
              if (chunk.done == true) deliveredCompletions++;
              if ((chunk.message?.content?.isNotEmpty ?? false) &&
                  !emitted.isCompleted)
                emitted.complete();
            },
            onError: (Object error) {
              errors.add(error);
              if (!emitted.isCompleted) emitted.completeError(error);
            },
            onDone: () {
              if (!emitted.isCompleted)
                emitted.completeError(StateError('No native text'));
              drained.complete();
            },
          );
      addTearDown(subscription.cancel);
      await emitted.future;
      final failedUnload = service.unloadModel(BundledModelManifest.id);
      await expectLater(failedUnload, throwsStateError);
      final retiredChunkCount = deliveredChunks;
      expect(service.requiresRecovery, isTrue);
      expect(service.repository, same(owner));
      expect(owner.operationSnapshot.requiresRecovery, isTrue);
      final rejected = service.recoverOwnedCleanup();
      expect(service.recoverOwnedCleanup(), same(rejected));
      expect(await rejected, RuntimeRecoveryOutcome.terminationUnconfirmed);
      expect(service.requiresRecovery, isTrue);
      await expectLater(
        service.ensureProfile(profile, modelId: BundledModelManifest.id),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      repositories.single.rejectCancellation = false;
      final acknowledged = service.recoverOwnedCleanup();
      expect(service.recoverOwnedCleanup(), same(acknowledged));
      expect(await acknowledged, RuntimeRecoveryOutcome.recovered);
      await drained.future;
      expect(errors, isEmpty);
      expect(
        deliveredChunks,
        retiredChunkCount,
        reason: 'Disposed output stays suppressed while diagnostics drain',
      );
      expect(deliveredCompletions, 0);
      expect(owner.lastMetrics?.completionReason, 'cancelled');
      expect(owner.lastMetrics?.cancellationAcknowledgementMicros, isNotNull);
      expect(service.repository, isNull);
      expect(service.requiresRecovery, isFalse);
      expect(service.isDisposed, isFalse);
      expect(owner.operationSnapshot.hasRetainedContext, isFalse);
      await expectLater(failedUnload, throwsStateError);
      final next = await service.ensureProfile(
        profile,
        modelId: BundledModelManifest.id,
      );
      expect(next, isNot(same(owner)));
      await for (final _ in next.streamChatWithGenerationOptions(
        'after-service-recovery',
        messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
        generationOptions: const GenerationOptions(maxTokens: 16),
      )) {}
      expect(next.lastMetrics?.generatedTokens, greaterThan(0));
      expect(next.lastMetrics?.completionReason, isNot('cancelled'));
      expect(repositories, hasLength(2));
      expect(await fixture.exists(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

class _AcknowledgementTimer implements Timer {
  _AcknowledgementTimer(this.callback);
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    isActive = false;
    tick++;
    callback();
  }
}

class _DelayedRepositoryClose extends LlamaCppChatRepository {
  _DelayedRepositoryClose(
    String path,
    Timer Function(Duration, void Function()) timerFactory,
  ) : super.withModelPath(
        path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
        shutdownTimeout: Duration.zero,
        shutdownTimerFactory: timerFactory,
      );
  final _release = Completer<void>();
  int cancelCalls = 0;
  void releaseAcknowledgement() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<void> cancelActiveInference() async {
    cancelCalls++;
    await super.cancelActiveInference();
    await _release.future;
  }
}

class _DelayedCancellationRepository extends LlamaCppChatRepository {
  _DelayedCancellationRepository(String path)
    : super.withModelPath(path, contextSize: 2048, batchSize: 128, threads: 2);
  int cancelCalls = 0;
  final nativeCancellationSettled = Completer<void>();
  final _release = Completer<void>();
  void releaseAcknowledgement() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<void> cancelActiveInference() async {
    cancelCalls++;
    await super.cancelActiveInference();
    if (!nativeCancellationSettled.isCompleted)
      nativeCancellationSettled.complete();
    await _release.future;
  }
}

class _FailingCancellationRepository extends LlamaCppChatRepository {
  _FailingCancellationRepository(
    String path, {
    RuntimeOperationKind runtimeOperationKind =
        RuntimeOperationKind.interactive,
  }) : super.withModelPath(
         path,
         contextSize: 2048,
         batchSize: 128,
         threads: 2,
         runtimeOperationKind: runtimeOperationKind,
       );
  bool rejectCancellation = true;
  @override
  Future<void> cancelActiveInference() => rejectCancellation
      ? Future.error(StateError('Injected cancellation transport failure'))
      : super.cancelActiveInference();
}

class _FixtureRegistry implements ModelRegistryService {
  _FixtureRegistry(String path)
    : model = ModelDescriptor(
        id: BundledModelManifest.id,
        displayName: 'Immutable test fixture',
        source: 'verified-fixture',
        localPath: path,
        sha256: BundledModelManifest.sha256,
        contextTrain: 2048,
        compatibilityStatus: 'compatible',
        installationState: 'installed',
      );
  final ModelDescriptor model;
  @override
  Future<ModelDescriptor> requireInstalled(String id) async {
    if (id != model.id) throw StateError('Fixture model unavailable');
    return model;
  }

  @override
  Future<ModelDescriptor?> findByPath(String path) async =>
      path == model.localPath ? model : null;
  @override
  Future<ModelDescriptor?> findById(String id) async =>
      id == model.id ? model : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SafeSentinel implements HardwareSentinelService {
  @override
  String? unsafeReasonHeavy() => null;
  @override
  Stream<bool> get onHealthChanged =>
      Stream<bool>.multi((_) {}, isBroadcast: true);
  @override
  bool isSafeForHeavyOperation() => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ProviderWarmup implements ModelWarmupService {
  _ProviderWarmup(this.owner);
  final LlamaCppChatRepository owner;
  @override
  bool get requiresRecovery => false;
  @override
  Future<void> cancelTuning() async {}
  @override
  void scheduleAutoTune(ModelSettings settings) {}
  @override
  Future<RuntimeProfile> resolveProfile(ModelSettings settings) async =>
      RuntimeProfile.forSettings(settings, processorCount: 2);
  @override
  Future<LlamaCppChatRepository> ensureProfile(
    RuntimeProfile profile, {
    required String modelId,
  }) async {
    await owner.prepare();
    return owner;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
