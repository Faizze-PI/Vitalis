import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/models/runtime_profile.dart';
import 'package:vitalis_app/providers/generation_provider.dart';
import 'package:vitalis_app/services/chat_state_controller.dart';
import 'package:vitalis_app/services/model_warmup_service.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/services/startup_access_guard.dart';

class _MockSentinel implements HardwareSentinelService {
  @override
  int get currentLevel => 100;
  @override
  bool get isCharging => true;
  @override
  bool get isInSaveMode => false;
  @override
  bool get isDisposed => false;
  @override
  ConnectivityResult get connectivityType => ConnectivityResult.wifi;
  @override
  int get memoryPressureLevel => 0;
  @override
  bool isSafeForHeavyOperation() => true;
  @override
  bool isSafeForDownload() => true;
  @override
  String? unsafeReasonHeavy() => null;
  @override
  String? unsafeReasonDownload() => null;
  @override
  void checkHeavyOperation() {}
  @override
  void checkDownload() {}
  @override
  Stream<bool> get onHealthChanged =>
      Stream<bool>.multi((_) {}, isBroadcast: true);
  @override
  Future<void> init() async {}
  @override
  void dispose() {}
}

void main() {
  test(
    'painted response timing survives completion and rejects old or stopped work',
    () async {
      var clock = 100;
      final controller = _EventController();
      final provider = GenerationProvider(
        controller: controller,
        warmup: _PreparedWarmup(),
        readOutputMonotonicMicros: () => clock,
      );
      addTearDown(provider.close);
      Future<void> start() => provider.startGeneration(
        messages: [
          Message(chatId: 1, role: MessageRole.user, content: 'Disposable'),
        ],
        settings: ModelSettings(),
      );
      await start();
      expect(provider.responseFrameIdentity, isNotNull);
      final identity = provider.responseFrameIdentity!;
      controller.onToken?.call('  ');
      expect(provider.lastResponseFrameTiming!.firstReceivedTextMicros, isNull);
      clock = 140;
      controller.onToken?.call('Reply');
      controller.onMetrics?.call(
        const LlamaCppInferenceMetrics(
          promptTokens: 1,
          generatedTokens: 1,
          modelLoadMicros: 0,
          contextInitMicros: 0,
          promptEvalMicros: 1,
          generationMicros: 1,
          timeToFirstTokenMicros: 2,
          completionReason: 'outputLimit',
          outputTiming: InferenceOutputTiming(
            requestId: 0,
            firstSampledTokenMicros: 1,
            firstEmittedTextMicros: 2,
          ),
        ),
      );
      expect(provider.lastResponseFrameTiming!.nativeRequestId, 0);
      controller.onComplete?.call();
      expect(provider.isSending, isFalse);
      clock = 170;
      provider.recordResponseFrame(identity);
      expect(provider.lastResponseFrameTiming!.firstReceivedTextMicros, 40);
      expect(provider.lastResponseFrameTiming!.firstRenderedFrameMicros, 70);
      clock = 180;
      await start();
      final next = provider.responseFrameIdentity!;
      expect(identical(next, identity), isFalse);
      controller.onToken?.call('Next');
      provider.recordResponseFrame(identity);
      expect(
        provider.lastResponseFrameTiming!.firstRenderedFrameMicros,
        isNull,
      );
      await provider.stopSending();
      provider.recordResponseFrame(next);
      expect(
        provider.lastResponseFrameTiming!.firstRenderedFrameMicros,
        isNull,
      );
      await start();
      controller.onToken?.call('Saved response');
      controller.onComplete?.call();
      final abandoned = provider.responseFrameIdentity!;
      provider.abandonResponseFrameObservation();
      provider.recordResponseFrame(abandoned);
      expect(
        provider.lastResponseFrameTiming!.firstRenderedFrameMicros,
        isNull,
      );
      provider.dispose();
      provider.recordResponseFrame(next);
      expect(
        provider.lastResponseFrameTiming!.firstRenderedFrameMicros,
        isNull,
      );
    },
  );
  test(
    'generation uses the output allowance left by its context plan',
    () async {
      final controller = _EventController();
      final provider = GenerationProvider(
        controller: controller,
        warmup: _PreparedWarmup(),
      );
      addTearDown(provider.close);
      await provider.startGeneration(
        messages: [
          Message(chatId: 1, role: MessageRole.user, content: 'current'),
        ],
        settings: ModelSettings(contextSizeOverride: 2048, maxTokens: 3000),
      );
      expect(controller.requests, 1);
      expect(controller.options?.maxTokens, 2046);
    },
  );
  test(
    'readiness signal shares Stop and detaches during pending disposal',
    () async {
      var readiness = StartupModelReadiness.ready;
      final signal = _ReadinessSignal();
      final controller = _ReadinessCancellationController();
      final provider = GenerationProvider(
        controller: controller,
        warmup: _PreparedWarmup(),
        startupAccess: StartupAccessGuard(
          () => StartupCapabilities(
            databaseReady: true,
            migrationReady: true,
            safetyReady: true,
            modelReadiness: readiness,
          ),
          changes: signal,
        ),
      );
      addTearDown(signal.dispose);
      addTearDown(controller.dispose);
      signal.emit();
      expect(controller.cancellations, 0);
      await provider.startGeneration(
        messages: [
          Message(chatId: 1, role: MessageRole.user, content: 'Disposable'),
        ],
        settings: ModelSettings(),
      );
      readiness = StartupModelReadiness.missing;
      signal.emit();
      await controller.cancellationStarted.future;
      signal.emit();
      final stopping = provider.stopSending();
      expect(controller.cancellations, 1);
      expect(provider.isSending, isTrue);
      provider.dispose();
      expect(signal.hasObservers, isFalse);
      signal.emit();
      controller.acknowledgement.complete();
      await stopping;
      await provider.close();
      expect(controller.cancellations, 1);
    },
  );

  test(
    'readiness cancellation failure retains recovery and rejects the next request',
    () async {
      var readiness = StartupModelReadiness.ready;
      final signal = _ReadinessSignal();
      final controller = _ReadinessCancellationController();
      final provider = GenerationProvider(
        controller: controller,
        warmup: _PreparedWarmup(),
        startupAccess: StartupAccessGuard(
          () => StartupCapabilities(
            databaseReady: true,
            migrationReady: true,
            safetyReady: true,
            modelReadiness: readiness,
          ),
          changes: signal,
        ),
      );
      addTearDown(() async {
        await provider.close().then<void>(
          (_) {},
          onError: (Object error) {
            expect(provider.requiresRecovery, isTrue);
          },
        );
        signal.dispose();
        controller.dispose();
      });
      await provider.startGeneration(
        messages: [
          Message(chatId: 1, role: MessageRole.user, content: 'Disposable'),
        ],
        settings: ModelSettings(),
      );
      readiness = StartupModelReadiness.missing;
      signal.emit();
      final stopping = provider.stopSending();
      controller.acknowledgement.completeError(
        StateError('fixture acknowledgement failure'),
      );
      await expectLater(stopping, throwsStateError);
      expect(provider.requiresRecovery, isTrue);
      expect(provider.isSending, isTrue);
      readiness = StartupModelReadiness.ready;
      signal.emit();
      await expectLater(
        provider.startGeneration(messages: [], settings: ModelSettings()),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      expect(controller.requests, 1);
    },
  );
  test(
    'active readiness revocation suppresses late tokens and retains Stop until acknowledgement',
    () async {
      var readiness = StartupModelReadiness.ready;
      final controller = _ReadinessCancellationController();
      final provider = GenerationProvider(
        controller: controller,
        warmup: _PreparedWarmup(),
        startupAccess: StartupAccessGuard(
          () => StartupCapabilities(
            databaseReady: true,
            migrationReady: true,
            safetyReady: true,
            modelReadiness: readiness,
          ),
        ),
      );
      addTearDown(() async {
        if (!controller.acknowledgement.isCompleted)
          controller.acknowledgement.complete();
        await provider.close();
        controller.dispose();
      });
      var saved = 0;
      provider.onGenerationComplete = (_) => saved++;
      await provider.startGeneration(
        messages: [
          Message(chatId: 1, role: MessageRole.user, content: 'Disposable'),
        ],
        settings: ModelSettings(),
      );
      controller.onToken!('before');
      readiness = StartupModelReadiness.missing;
      controller.onToken!('late');
      expect(provider.streamText, 'before');
      await controller.cancellationStarted.future;
      final stopping = provider.stopSending();
      controller.onComplete!();
      expect(saved, 0);
      expect(controller.cancellations, 1);
      expect(provider.isSending, isTrue);
      controller.acknowledgement.complete();
      await stopping;
      expect(provider.isSending, isFalse);
    },
  );
  for (final boundary in ['profile', 'model', 'context']) {
    test(
      'revocation at $boundary boundary prevents native generation',
      () async {
        var readiness = StartupModelReadiness.ready;
        final warmup = _BoundaryWarmup(boundary);
        final controller = _EventController();
        final provider = GenerationProvider(
          controller: controller,
          warmup: warmup,
          startupAccess: StartupAccessGuard(
            () => StartupCapabilities(
              databaseReady: true,
              migrationReady: true,
              safetyReady: true,
              modelReadiness: readiness,
            ),
          ),
        );
        final generating = provider.startGeneration(
          messages: [
            Message(chatId: 1, role: MessageRole.user, content: 'Disposable'),
          ],
          settings: ModelSettings(),
        );
        await warmup.entered.future;
        readiness = StartupModelReadiness.missing;
        warmup.release.complete();
        await generating;
        expect(controller.requests, 0);
        expect(provider.isSending, isFalse);
        expect(provider.hasError, isTrue);
        expect(warmup.ensureCalls, boundary == 'profile' ? 0 : 1);
        await provider.close();
        controller.dispose();
      },
    );
  }
  test(
    'revoked startup permission stops preparation after tuning acknowledgement',
    () async {
      var readiness = StartupModelReadiness.ready;
      final warmup = _WaitingWarmup();
      final controller = ChatStateController(sentinel: _MockSentinel());
      final provider = GenerationProvider(
        controller: controller,
        warmup: warmup,
        startupAccess: StartupAccessGuard(
          () => StartupCapabilities(
            databaseReady: true,
            migrationReady: true,
            safetyReady: true,
            modelReadiness: readiness,
          ),
        ),
      );
      final preparing = provider.prepareModel(ModelSettings());
      readiness = StartupModelReadiness.missing;
      warmup.stop.complete();
      await expectLater(preparing, throwsA(isA<StartupAccessDenied>()));
      expect(warmup.resolveCalls, 0);
      await provider.close();
      controller.dispose();
    },
  );
  test(
    'read-only startup rejects direct preparation and generation before warmup',
    () async {
      final warmup = _WaitingWarmup();
      final controller = ChatStateController(sentinel: _MockSentinel());
      final provider = GenerationProvider(
        controller: controller,
        warmup: warmup,
        startupAccess: StartupAccessGuard(
          () => const StartupCapabilities(
            databaseReady: true,
            migrationReady: true,
            safetyReady: true,
            modelReadiness: StartupModelReadiness.missing,
          ),
        ),
      );
      await expectLater(
        provider.prepareModel(ModelSettings()),
        throwsA(isA<StartupAccessDenied>()),
      );
      await expectLater(
        provider.startGeneration(messages: [], settings: ModelSettings()),
        throwsA(isA<StartupAccessDenied>()),
      );
      expect(warmup.resolveCalls, 0);
      expect(provider.isSending, isFalse);
      warmup.stop.complete();
      await provider.close();
      controller.dispose();
    },
  );
  test(
    'provider close expiry retains pending preparation until recovery',
    () async {
      final warmup = _WaitingWarmup();
      final controller = ChatStateController(sentinel: _MockSentinel());
      final timers = <_CloseTimer>[];
      final provider = GenerationProvider(
        controller: controller,
        warmup: warmup,
        shutdownTimeout: Duration.zero,
        readShutdownMonotonicMicros: () => 0,
        shutdownTimerFactory: (_, callback) {
          final timer = _CloseTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      final preparing = provider.prepareModel(ModelSettings());
      final closing = provider.close();
      var settled = false;
      final observed = closing.then<void>(
        (_) => settled = true,
        onError: (Object _, StackTrace __) => settled = true,
      );
      for (final timer in timers.toList()) {
        timer.fire();
      }
      await Future<void>.delayed(Duration.zero);
      try {
        expect(settled, isTrue);
        await expectLater(closing, throwsA(isA<InferenceRecoveryRequired>()));
        expect(provider.requiresRecovery, isTrue);
        expect(warmup.resolveCalls, 0);
      } finally {
        warmup.stop.complete();
        await preparing;
        await observed;
      }
      await Future<void>.delayed(Duration.zero);
      expect(provider.requiresRecovery, isTrue);
      expect(
        await provider.recoverOwnedCleanup(),
        RuntimeRecoveryOutcome.recovered,
      );
      expect(provider.requiresRecovery, isFalse);
      await provider.close();
      await expectLater(closing, throwsA(isA<InferenceRecoveryRequired>()));
      await expectLater(
        provider.prepareModel(ModelSettings()),
        throwsStateError,
      );
    },
  );

  test(
    'provider close drains preparation and rejects new work immediately',
    () async {
      final warmup = _WaitingWarmup();
      final controller = ChatStateController(sentinel: _MockSentinel());
      final provider = GenerationProvider(
        controller: controller,
        warmup: warmup,
      );
      final preparing = provider.prepareModel(ModelSettings());
      final closing = provider.close();
      var settled = false;
      final observing = closing.then((_) => settled = true);
      expect(provider.close(), same(closing));
      provider.dispose();
      expect(controller.isDisposed, isTrue);
      await expectLater(
        provider.prepareModel(ModelSettings()),
        throwsStateError,
      );
      expect(settled, isFalse);
      warmup.stop.complete();
      await preparing;
      await observing;
      expect(warmup.resolveCalls, 0);
      expect(provider.requiresRecovery, isFalse);
      expect(provider.isSending, isFalse);
    },
  );

  test('provider close retains unacknowledged controller cleanup', () async {
    final warmup = _WaitingWarmup();
    final controller = _ControlledCloseController();
    final provider = GenerationProvider(controller: controller, warmup: warmup);
    final closing = provider.close();
    final failed = expectLater(
      closing,
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    provider.dispose();
    expect(provider.close(), same(closing));
    expect(controller.closeCalls, 1);
    controller.finished.completeError(
      StateError('private/path cleanup failure'),
    );
    await failed;
    expect(provider.requiresRecovery, isTrue);
    await expectLater(
      provider.close(),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    await expectLater(provider.prepareModel(ModelSettings()), throwsStateError);
    expect(warmup.stopCalls, 0);
  });

  test(
    'provider close waits for both controller and preparation actors',
    () async {
      final warmup = _WaitingWarmup();
      final controller = _ControlledCloseController();
      final provider = GenerationProvider(
        controller: controller,
        warmup: warmup,
      );
      final preparing = provider.prepareModel(ModelSettings());
      final closing = provider.close();
      var finished = false;
      final failed = expectLater(
        closing,
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      final observed = closing.then<void>(
        (_) {
          finished = true;
        },
        onError: (Object _, StackTrace __) {
          finished = true;
        },
      );
      controller.finished.completeError(
        StateError('fixture cancellation failure'),
      );
      // New operations reject synchronously at their lifecycle check; this await
      // also lets controller failure propagate while preparation remains owned.
      await expectLater(
        provider.prepareModel(ModelSettings()),
        throwsStateError,
      );
      expect(finished, isFalse);
      warmup.stop.complete();
      await preparing;
      await failed;
      await observed;
      expect(finished, isTrue);
      expect(warmup.resolveCalls, 0);
      provider.dispose();
    },
  );
  group('prepared generation lifecycle', () {
    late _PreparedWarmup warmup;
    late _EventController controller;
    late GenerationProvider subject;
    final messages = [
      Message(chatId: 1, role: MessageRole.user, content: 'fixture'),
    ];
    setUp(() {
      warmup = _PreparedWarmup();
      controller = _EventController();
      subject = GenerationProvider(controller: controller, warmup: warmup);
      addTearDown(subject.dispose);
    });
    Future<void> start() =>
        subject.startGeneration(messages: messages, settings: ModelSettings());

    test(
      'completion preserves one response and authoritative metrics',
      () async {
        String? saved;
        subject.onGenerationComplete = (value) => saved = value;
        await start();
        expect(controller.requests, 1);
        expect(controller.messages!.last.content, 'fixture');
        controller.onToken!('one');
        controller.onToken!(' two');
        expect(subject.streamText, 'one two');
        expect(subject.lastContextUsage, greaterThan(0));
        controller.onMetrics!(
          const LlamaCppInferenceMetrics(
            promptTokens: 2,
            generatedTokens: 4,
            modelLoadMicros: 0,
            contextInitMicros: 0,
            promptEvalMicros: 1000,
            generationMicros: 1000000,
            timeToFirstTokenMicros: 1000,
            completionReason: 'eog',
          ),
        );
        expect(subject.lastTokenCount, 4);
        expect(subject.lastTps, 4);
        controller.onComplete!();
        expect(saved, 'one two');
        expect(subject.isSending, isFalse);
        expect(subject.streamText, isEmpty);
        expect(warmup.tuneCalls, 1);
      },
    );
    test('empty completion reports retry instead of saving', () async {
      await start();
      controller.onComplete!();
      expect(subject.hasError, isTrue);
      expect(subject.errorMessage, contains('No response'));
      expect(warmup.tuneCalls, 0);
    });
    test('completion callback disposal cannot restart tuning', () async {
      await start();
      controller.onToken!('done');
      subject.onGenerationComplete = (_) => subject.dispose();
      controller.onComplete!();
      expect(warmup.tuneCalls, 0);
    });
    test('error callback can dispose without late notification', () async {
      await start();
      subject.onError = (_) => subject.dispose();
      expect(
        () => controller.onError!('redacted fixture failure'),
        returnsNormally,
      );
    });
    test('tokenizer failures do not expose private paths', () async {
      warmup.fixtureRepository.failCounting = true;
      await start();
      expect(subject.hasError, isTrue);
      expect(subject.errorMessage, isNot(contains('private-model')));
      expect(controller.requests, 0);
    });
    test('initialization failures leave preparation retryable', () async {
      warmup.failEnsure = true;
      await start();
      expect(subject.isSending, isFalse);
      expect(subject.hasError, isTrue);
      warmup.failEnsure = false;
      await start();
      expect(controller.requests, 1);
    });
    test('late callbacks after Stop do not save or publish output', () async {
      await start();
      final token = controller.onToken!;
      final done = controller.onComplete!;
      await subject.stopSending();
      token('late');
      done();
      expect(subject.streamText, isEmpty);
      expect(warmup.tuneCalls, 0);
    });
    test('automatic cancellation failure quarantines the caller', () async {
      await start();
      controller.failureCode = ChatFailureCode.cancellationUnacknowledged;
      controller.onError!('Native cancellation was not acknowledged.');
      expect(subject.requiresRecovery, isTrue);
      expect(subject.isSending, isTrue);
      await expectLater(start(), throwsA(isA<InferenceRecoveryRequired>()));
      await expectLater(
        subject.stopSending(),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
    });
    test('unloading drains generation before invoking warmup', () async {
      await start();
      await subject.unloadModel('fixture');
      expect(subject.isSending, isFalse);
      expect(warmup.unloads, ['fixture']);
    });
  });
  test('recorded cancellation failure cannot report idle', () async {
    final warmup = _WaitingWarmup();
    final provider = GenerationProvider(
      controller: _RecordedFailureController(),
      warmup: warmup,
    );
    addTearDown(provider.dispose);
    final preparing = provider.startGeneration(
      messages: [],
      settings: ModelSettings(),
    );
    final stopped = expectLater(
      provider.stopSending(),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    warmup.stop.complete();
    await preparing;
    await stopped;
    expect(provider.requiresRecovery, isTrue);
    expect(provider.isSending, isTrue);
  });

  test('unacknowledged Stop quarantines new operations', () async {
    final warmup = _WaitingWarmup();
    final provider = GenerationProvider(
      controller: _FailingStopController(),
      warmup: warmup,
    );
    addTearDown(provider.dispose);
    final preparing = provider.startGeneration(
      messages: [],
      settings: ModelSettings(),
    );
    final stopping = provider.stopSending();
    await expectLater(stopping, throwsStateError);
    expect(provider.stopSending(), same(stopping));
    expect(provider.requiresRecovery, isTrue);
    expect(provider.isSending, isTrue);
    warmup.stop.complete();
    await preparing;
    await expectLater(
      provider.prepareModel(ModelSettings()),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    expect(warmup.resolveCalls, 0);
  });

  test(
    'Stop drains pending preparation and duplicate callers share it',
    () async {
      final warmup = _WaitingWarmup();
      final provider = GenerationProvider(
        controller: ChatStateController(sentinel: _MockSentinel()),
        warmup: warmup,
      );
      addTearDown(provider.dispose);
      final pending = provider.startGeneration(
        messages: [],
        settings: ModelSettings(),
      );
      expect(provider.isSending, isTrue);
      final stopping = provider.stopSending();
      expect(provider.stopSending(), same(stopping));
      expect(provider.isSending, isTrue);
      final rejected = expectLater(
        provider.startGeneration(messages: [], settings: ModelSettings()),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      warmup.stop.complete();
      await pending;
      await stopping;
      await rejected;
      expect(warmup.resolveCalls, 0);
      expect(provider.isSending, isFalse);
      await provider.startGeneration(messages: [], settings: ModelSettings());
      expect(warmup.resolveCalls, 1);
      expect(provider.hasError, isTrue);
      expect(provider.isSending, isFalse);
    },
  );

  test('disposed provider rejects new preparation and generation', () async {
    final warmup = _WaitingWarmup();
    final provider = GenerationProvider(
      controller: ChatStateController(sentinel: _MockSentinel()),
      warmup: warmup,
    );
    provider.dispose();
    provider.dispose();
    await expectLater(provider.prepareModel(ModelSettings()), throwsStateError);
    await expectLater(
      provider.startGeneration(messages: [], settings: ModelSettings()),
      throwsStateError,
    );
    expect(warmup.stopCalls, 0);
  });

  test('standalone preparation excludes a competing generation', () async {
    final warmup = _WaitingWarmup();
    final provider = GenerationProvider(
      controller: ChatStateController(sentinel: _MockSentinel()),
      warmup: warmup,
    );
    addTearDown(provider.dispose);
    final preparing = provider.prepareModel(ModelSettings());
    final preparationError = expectLater(preparing, throwsStateError);
    final rejected = expectLater(
      provider.startGeneration(messages: [], settings: ModelSettings()),
      throwsA(isA<InferenceRuntimeBusy>()),
    );
    warmup.stop.complete();
    await preparationError;
    await rejected;
    expect(warmup.stopCalls, 1);
  });

  test(
    'generation reserves its caller before tuning acknowledgement',
    () async {
      final warmup = _WaitingWarmup();
      final provider = GenerationProvider(
        controller: ChatStateController(sentinel: _MockSentinel()),
        warmup: warmup,
      );
      addTearDown(provider.dispose);
      final first = provider.startGeneration(
        messages: [],
        settings: ModelSettings(),
      );
      final firstObserved = first.then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {},
      );
      final second = expectLater(
        provider.startGeneration(messages: [], settings: ModelSettings()),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      warmup.stop.complete();
      await firstObserved;
      await second;
      expect(warmup.stopCalls, 1);
      expect(provider.isSending, isFalse);
    },
  );

  test('disposed preparation never resolves or initializes a model', () async {
    final warmup = _WaitingWarmup();
    final provider = GenerationProvider(
      controller: ChatStateController(sentinel: _MockSentinel()),
      warmup: warmup,
    );
    final pending = provider.prepareModel(ModelSettings());
    final observed = pending.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    provider.dispose();
    warmup.stop.complete();
    await observed;
    expect(warmup.resolveCalls, 0);
  });

  test('disposed generation never resumes preparation', () async {
    final warmup = _WaitingWarmup();
    final provider = GenerationProvider(
      controller: ChatStateController(sentinel: _MockSentinel()),
      warmup: warmup,
    );
    final pending = provider.startGeneration(
      messages: [],
      settings: ModelSettings(),
    );
    final observed = pending.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    provider.dispose();
    warmup.stop.complete();
    await observed;
    expect(warmup.resolveCalls, 0);
  });

  late GenerationProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final controller = ChatStateController(sentinel: _MockSentinel());
    provider = GenerationProvider(
      controller: controller,
      warmup: ModelWarmupService(sentinel: _MockSentinel()),
    );
  });

  group('GenerationProvider', () {
    test('initial state is idle', () {
      expect(provider.isSending, false);
      expect(provider.hasError, false);
      expect(provider.errorMessage, '');
      expect(provider.chatStatus.name, 'idle');
      expect(provider.lastTokenCount, 0);
      expect(provider.lastTps, 0.0);
      expect(provider.streamText, '');
      expect(provider.showTruncationWarning, false);
      expect(provider.truncationDismissed, false);
    });

    test('clearError resets error state', () {
      provider.clearError();
      expect(provider.hasError, false);
      expect(provider.errorMessage, '');
    });

    test('dismissTruncationWarning updates state', () {
      provider.dismissTruncationWarning();
      expect(provider.truncationDismissed, true);
    });

    test('stopSending resets generation state', () {
      provider.stopSending();
      expect(provider.isSending, false);
      expect(provider.hasError, false);
      expect(provider.streamText, '');
    });

    test('streamText is empty when not sending', () {
      expect(provider.streamText, '');
    });

    test('onGenerationComplete callback can be set', () {
      provider.onGenerationComplete = (content) {};
      expect(provider.onGenerationComplete, isNotNull);
    });

    test('onError callback can be set', () {
      provider.onError = (error) {};
      expect(provider.onError, isNotNull);
    });

    test('tps calculation accuracy', () {
      expect(provider.lastTps, 0.0);
      expect(provider.lastTokenCount, 0);
    });

    test('truncation warning flag defaults to false', () {
      expect(provider.showTruncationWarning, false);
      expect(provider.truncationDismissed, false);
    });
  });
}

class _CloseTimer implements Timer {
  _CloseTimer(this.callback);
  final void Function() callback;
  bool _active = true;
  @override
  bool get isActive => _active;
  @override
  int get tick => _active ? 0 : 1;
  @override
  void cancel() => _active = false;
  void fire() {
    if (!_active) return;
    _active = false;
    callback();
  }
}

class _ControlledCloseController extends ChatStateController {
  _ControlledCloseController() : super(sentinel: _MockSentinel());
  final finished = Completer<void>();
  int closeCalls = 0;
  @override
  Future<void> close() {
    closeCalls++;
    return finished.future;
  }
}

class _WaitingWarmup implements ModelWarmupService {
  @override
  bool get requiresRecovery => false;
  final stop = Completer<void>();
  int stopCalls = 0;
  int resolveCalls = 0;
  @override
  Future<void> cancelTuning() {
    stopCalls++;
    return stop.future;
  }

  @override
  Future<RuntimeProfile> resolveProfile(ModelSettings settings) {
    resolveCalls++;
    return Future.error(StateError('fixture profile failure'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingStopController extends ChatStateController {
  _FailingStopController() : super(sentinel: _MockSentinel());

  @override
  Future<void> cancelInference() =>
      Future.error(StateError('fixture cancellation failure'));
}

class _RecordedFailureController extends ChatStateController {
  _RecordedFailureController() : super(sentinel: _MockSentinel());

  @override
  Future<void> cancelInference() async {
    failureCode = ChatFailureCode.cancellationUnacknowledged;
  }
}

class _PreparedWarmup implements ModelWarmupService {
  _PreparedWarmup({_CountingRepository? repository})
    : fixtureRepository = repository ?? _CountingRepository();
  final _CountingRepository fixtureRepository;
  bool failEnsure = false;
  int tuneCalls = 0;
  final unloads = <String>[];
  @override
  Future<void> cancelTuning() async {}
  @override
  Future<RuntimeProfile> resolveProfile(ModelSettings settings) async =>
      RuntimeProfile.forSettings(settings, processorCount: 2);
  @override
  Future<LlamaCppChatRepository> ensureProfile(
    RuntimeProfile profile, {
    required String modelId,
  }) async {
    if (failEnsure) throw StateError('fixture initialization failed');
    return fixtureRepository;
  }

  @override
  void scheduleAutoTune(ModelSettings settings) => tuneCalls++;
  @override
  Future<void> unloadModel(String id) async => unloads.add(id);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BoundaryWarmup extends _PreparedWarmup {
  _BoundaryWarmup(this.boundary) : super(repository: _BoundaryRepository()) {
    (fixtureRepository as _BoundaryRepository).beforeCount = () =>
        _wait('context');
  }
  final String boundary;
  final entered = Completer<void>();
  final release = Completer<void>();
  int ensureCalls = 0;
  Future<void> _wait(String stage) async {
    if (boundary != stage) return;
    entered.complete();
    await release.future;
  }

  @override
  Future<RuntimeProfile> resolveProfile(ModelSettings settings) async {
    await _wait('profile');
    return super.resolveProfile(settings);
  }

  @override
  Future<LlamaCppChatRepository> ensureProfile(
    RuntimeProfile profile, {
    required String modelId,
  }) async {
    ensureCalls++;
    await _wait('model');
    return super.ensureProfile(profile, modelId: modelId);
  }
}

class _CountingRepository implements LlamaCppChatRepository {
  bool failCounting = false;
  @override
  Future<int> countChatTokens(
    List<LLMMessage> messages, {
    bool think = false,
  }) async {
    if (failCounting) throw StateError('private-model/path tokenizer failure');
    return messages.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BoundaryRepository extends _CountingRepository {
  Future<void> Function()? beforeCount;
  @override
  Future<int> countChatTokens(
    List<LLMMessage> messages, {
    bool think = false,
  }) async {
    final callback = beforeCount;
    beforeCount = null;
    await callback?.call();
    return super.countChatTokens(messages, think: think);
  }
}

class _EventController extends ChatStateController {
  _EventController() : super(sentinel: _MockSentinel());
  int requests = 0;
  List<LLMMessage>? messages;
  GenerationOptions? options;
  @override
  Future<void> startGeneration({
    required LlamaCppChatRepository repository,
    required List<LLMMessage> messages,
    required GenerationOptions options,
    bool think = false,
  }) async {
    requests++;
    this.messages = messages;
    this.options = options;
  }
}

class _ReadinessCancellationController extends _EventController {
  final cancellationStarted = Completer<void>();
  final acknowledgement = Completer<void>();
  int cancellations = 0;
  @override
  Future<void> cancelInference() {
    cancellations++;
    if (!cancellationStarted.isCompleted) cancellationStarted.complete();
    return acknowledgement.future;
  }
}

class _ReadinessSignal extends ChangeNotifier {
  bool get hasObservers => hasListeners;
  void emit() => notifyListeners();
}
