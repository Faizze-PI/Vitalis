import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/isolate_messages.dart';
import 'package:llm_llamacpp/src/persistent_inference_isolate.dart';
import 'package:llm_llamacpp/src/runtime_cleanup_fault.dart';
import 'package:llm_llamacpp/src/runtime_request_finalizer.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String modelPath;
  setUpAll(() async {
    expect(
      RuntimeCleanupFault.enabled,
      isTrue,
      reason: 'Explicit VITALIS_RUNTIME_FAULT_TESTS=true define is mandatory',
    );
    final path = Platform.environment['VITALIS_TEST_MODEL'];
    expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
    modelPath = path!;
    expect(
      (await sha256.bind(File(modelPath).openRead()).first).toString(),
      BundledModelManifest.sha256,
    );
  });

  test('explicit fault mode rejects nonpositive failure counts', () {
    for (final count in [0, -1]) {
      expect(
        RuntimeCleanupFault(
          step: RuntimeCleanupStep.sampler,
          failures: count,
        ).validate,
        throwsArgumentError,
      );
    }
  });

  test(
    'abandoned text stream acknowledges native cancellation before reuse',
    () async {
      final runtime = PersistentInferenceIsolate.instance;
      final owner = Object();
      addTearDown(() async {
        if (runtime.operationSnapshot.requiresRecovery) {
          await runtime.recover(owner);
        }
        if (runtime.canAccess(owner)) await runtime.releaseOwnedContext(owner);
      });
      await runtime.prepare(
        modelPath: modelPath,
        contextSize: 2048,
        batchSize: 128,
        nGpuLayers: 0,
        threads: 2,
        owner: owner,
      );
      final firstText = Completer<void>();
      final terminal = Completer<Object?>();
      var terminalCalls = 0;
      final subscription = runtime
          .runInference(
            modelPath: modelPath,
            prompt: '',
            messages: const [
              IsolateMessage(
                role: 'user',
                content: 'Write a long list of harmless household objects.',
              ),
            ],
            stopTokens: const [],
            contextSize: 2048,
            batchSize: 128,
            nGpuLayers: 0,
            threads: 2,
            owner: owner,
            options: const GenerationOptions(maxTokens: 256),
            onTerminal: (event) {
              terminalCalls++;
              if (!terminal.isCompleted) terminal.complete(event);
            },
          )
          .listen((event) {
            if (event is InferenceToken && !firstText.isCompleted) {
              firstText.complete();
            }
          }, onError: firstText.completeError);
      addTearDown(subscription.cancel);
      await firstText.future;
      expect(runtime.operationSnapshot.hasNativeWork, isTrue);
      await subscription.cancel();
      final receipt = await terminal.future;
      expect(receipt, isA<InferenceCancelled>());
      expect(
        (receipt as InferenceCancelled).acknowledgementMicros,
        greaterThan(0),
      );
      expect(receipt.generatedTokens, greaterThan(0));
      await runtime.drainOwner(owner);
      expect(terminalCalls, 1);
      expect(runtime.operationSnapshot.hasNativeWork, isFalse);
      expect(runtime.operationSnapshot.requiresRecovery, isFalse);
      final followup = await runtime
          .runInference(
            modelPath: modelPath,
            prompt: '',
            messages: const [
              IsolateMessage(role: 'user', content: 'Say hello.'),
            ],
            stopTokens: const [],
            contextSize: 2048,
            batchSize: 128,
            nGpuLayers: 0,
            threads: 2,
            owner: owner,
            options: const GenerationOptions(maxTokens: 8),
          )
          .toList();
      expect(followup.whereType<InferenceError>(), isEmpty);
      expect(followup.whereType<InferenceComplete>(), hasLength(1));
      expect(terminalCalls, 1);
      await runtime.releaseOwnedContext(owner);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'failed terminal observer retains real owner until acknowledged recovery',
    () async {
      final runtime = PersistentInferenceIsolate.instance;
      final owner = Object();
      final competitor = Object();
      addTearDown(() async {
        if (runtime.operationSnapshot.requiresRecovery) {
          await runtime.recover(owner);
        }
        if (runtime.canAccess(owner)) await runtime.releaseOwnedContext(owner);
      });
      Future<void> prepare(Object identity) => runtime.prepare(
        modelPath: modelPath,
        contextSize: 2048,
        batchSize: 128,
        nGpuLayers: 0,
        threads: 2,
        owner: identity,
      );
      var observerCalls = 0;
      Stream<dynamic> generate({bool failObserver = false}) =>
          runtime.runInference(
            modelPath: modelPath,
            prompt: '',
            messages: const [
              IsolateMessage(role: 'user', content: 'Say hello.'),
            ],
            stopTokens: const [],
            contextSize: 2048,
            batchSize: 128,
            nGpuLayers: 0,
            threads: 2,
            owner: owner,
            options: const GenerationOptions(maxTokens: 8),
            onTerminal: failObserver
                ? (_) {
                    observerCalls++;
                    throw StateError('private observer fixture');
                  }
                : null,
          );
      await prepare(owner);
      final held = runtime.operationSnapshot.contextOwnerId;
      final events = await generate(failObserver: true).toList();
      expect(observerCalls, 1);
      expect(
        events.whereType<InferenceCleanupRequired>().single.step,
        'terminal_observer',
      );
      expect(events.whereType<InferenceComplete>(), isEmpty);
      expect(events.whereType<InferenceCancelled>(), isEmpty);
      expect(runtime.operationSnapshot.requiresRecovery, isTrue);
      expect(runtime.operationSnapshot.contextOwnerId, held);
      await expectLater(
        prepare(competitor),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      await expectLater(
        runtime.cancel(null, competitor),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      await expectLater(
        runtime.releaseOwnedContext(competitor),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      expect(runtime.operationSnapshot.requiresRecovery, isTrue);
      expect(runtime.operationSnapshot.contextOwnerId, held);
      await expectLater(
        generate().drain<void>(),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      expect(await runtime.recover(owner), RuntimeRecoveryOutcome.recovered);
      expect(runtime.operationSnapshot.hasRetainedContext, isFalse);
      expect(runtime.operationSnapshot.hasNativeWork, isFalse);
      await prepare(owner);
      final followup = await generate().toList();
      expect(followup.whereType<InferenceError>(), isEmpty);
      expect(followup.whereType<InferenceComplete>(), hasLength(1));
      expect(observerCalls, 1);
      await runtime.releaseOwnedContext(owner);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'failed native unload is typed and retains its context owner',
    () async {
      final runtime = PersistentInferenceIsolate.instance;
      final owner = Object();
      final competitor = Object();
      addTearDown(() async {
        if (runtime.operationSnapshot.requiresRecovery)
          await runtime.recover(owner);
        if (runtime.canAccess(owner)) await runtime.releaseOwnedContext(owner);
      });
      Future<void> prepare(Object identity) => runtime.prepare(
        modelPath: modelPath,
        contextSize: 2048,
        batchSize: 128,
        nGpuLayers: 0,
        threads: 2,
        owner: identity,
      );
      await prepare(owner);
      final events = await runtime
          .runInference(
            modelPath: modelPath,
            prompt: '',
            messages: const [
              IsolateMessage(role: 'user', content: 'Say hello.'),
            ],
            stopTokens: const [],
            contextSize: 2048,
            batchSize: 128,
            nGpuLayers: 0,
            threads: 2,
            owner: owner,
            options: const GenerationOptions(maxTokens: 8),
            cleanupFault: const RuntimeCleanupFault(
              step: RuntimeCleanupStep.sampler,
              failures: 2,
            ),
          )
          .toList();
      expect(events.whereType<InferenceCleanupRequired>(), hasLength(1));
      final held = runtime.operationSnapshot;
      await expectLater(
        runtime.unload(owner: owner),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      expect(runtime.operationSnapshot.requiresRecovery, isTrue);
      expect(runtime.operationSnapshot.hasRetainedContext, isTrue);
      expect(runtime.operationSnapshot.contextOwnerId, held.contextOwnerId);
      await expectLater(
        prepare(competitor),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      expect(await runtime.recover(owner), RuntimeRecoveryOutcome.recovered);
      expect(runtime.operationSnapshot.hasRetainedContext, isFalse);
      expect(runtime.operationSnapshot.hasNativeWork, isFalse);
      await prepare(competitor);
      await runtime.releaseOwnedContext(competitor);
      expect(await File(modelPath).exists(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  for (final step in RuntimeCleanupStep.values) {
    // Every registered helper cleanup boundary is mandatory, never skipped.
    test(
      'actual helper retains ${step.name} cleanup until owner retry',
      () async {
        final runtime = PersistentInferenceIsolate.instance;
        final owner = Object();
        final competitor = Object();
        addTearDown(() async {
          for (
            var retry = 0;
            retry < 3 && runtime.operationSnapshot.requiresRecovery;
            retry++
          ) {
            await runtime.recover(owner);
          }
          if (runtime.canAccess(owner))
            await runtime.releaseOwnedContext(owner);
        });
        Future<void> prepare(Object identity) => runtime.prepare(
          modelPath: modelPath,
          contextSize: 2048,
          batchSize: 128,
          nGpuLayers: 0,
          threads: 2,
          owner: identity,
        );
        Stream<dynamic> generate({RuntimeCleanupFault? fault}) =>
            runtime.runInference(
              modelPath: modelPath,
              prompt: '',
              messages: const [
                IsolateMessage(role: 'user', content: 'Say hello.'),
              ],
              stopTokens: const [],
              contextSize: 2048,
              batchSize: 128,
              nGpuLayers: 0,
              threads: 2,
              owner: owner,
              options: const GenerationOptions(maxTokens: 8),
              cleanupFault: fault,
            );
        await prepare(owner);
        final events = await generate(
          fault: RuntimeCleanupFault(step: step, failures: 2),
        ).toList();
        expect(
          events.whereType<InferenceCleanupRequired>().single.step,
          step.name,
        );
        expect(events.whereType<InferenceComplete>(), isEmpty);
        expect(events.whereType<InferenceCancelled>(), isEmpty);
        expect(
          events.whereType<RuntimeProgress>().where(
            (event) =>
                event.phase == RuntimeProgressPhase.requestCleanup &&
                event.completedUnits == 1,
          ),
          isEmpty,
        );
        final held = runtime.operationSnapshot;
        expect(held.requiresRecovery, isTrue);
        expect(held.hasRetainedContext, isTrue);
        expect(held.hasNativeWork, isTrue);
        expect(held.cancellationHandleAvailable, isTrue);
        await expectLater(
          generate().drain<void>(),
          throwsA(isA<InferenceRecoveryRequired>()),
        );
        await expectLater(
          prepare(competitor),
          throwsA(isA<InferenceRuntimeBusy>()),
        );
        await expectLater(
          runtime.cancel(null, competitor),
          throwsA(isA<InferenceRuntimeBusy>()),
        );
        await expectLater(
          runtime.unload(owner: competitor),
          throwsA(isA<InferenceRuntimeBusy>()),
        );
        final first = runtime.recover(owner);
        expect(runtime.recover(owner), same(first));
        expect(await first, RuntimeRecoveryOutcome.terminationUnconfirmed);
        expect(runtime.operationSnapshot.requiresRecovery, isTrue);
        expect(runtime.operationSnapshot.contextOwnerId, held.contextOwnerId);
        expect(runtime.operationSnapshot.nativeRequestId, held.nativeRequestId);
        expect(runtime.operationSnapshot.cancellationHandleAvailable, isTrue);
        final second = runtime.recover(owner);
        expect(runtime.recover(owner), same(second));
        expect(await second, RuntimeRecoveryOutcome.recovered);
        expect(runtime.operationSnapshot.hasNativeWork, isFalse);
        expect(runtime.operationSnapshot.hasRetainedContext, isFalse);
        expect(runtime.operationSnapshot.requiresRecovery, isFalse);
        // Retry may publish the original native outcome internally, but the
        // already-retired request stream must never gain duplicate completion.
        expect(events.whereType<InferenceComplete>(), isEmpty);
        await prepare(owner);
        final followUp = await generate().toList();
        expect(followUp.whereType<InferenceError>(), isEmpty);
        expect(
          followUp.whereType<InferenceComplete>().single.generatedTokens,
          greaterThan(0),
        );
        await runtime.releaseOwnedContext(owner);
        expect(await File(modelPath).exists(), isTrue);
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }
}
