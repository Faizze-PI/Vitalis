import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/models/generation_watchdog_policy.dart';
import 'package:vitalis_app/services/chat_state_controller.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';

void main() {
  const options = GenerationOptions(maxTokens: 8);
  final messages = [LLMMessage(role: LLMRole.user, content: 'hello')];

  for (final synchronousCall in [1, 2]) {
    test(
      'synchronous watchdog expiry retires its returned timer: $synchronousCall',
      () async {
        final sentinel = _ControlledSentinel();
        final repository = _ControlledRepository();
        final clock = _WatchdogClock();
        var scheduled = 0;
        final controller = ChatStateController(
          sentinel: sentinel,
          watchdogTimerFactory: (duration, action) {
            final timer = clock.schedule(duration, action);
            if (++scheduled == synchronousCall) action();
            return timer;
          },
        );
        try {
          await controller.startGeneration(
            repository: repository,
            messages: messages,
            options: options,
          );
          expect(repository.cancelCalls, 1);
          expect(repository.lastMessages, isNull);
          expect(sentinel._health.hasListener, isFalse);
          repository.acknowledgeCancellation();
          await controller.cancelInference();
          expect(clock.timers.where((timer) => timer.isActive), isEmpty);
        } finally {
          repository.acknowledgeCancellation();
          await controller.close();
          await repository.close();
          await sentinel.close();
        }
      },
    );
  }

  for (final failure in [
    'initial timer',
    'maximum timer',
    'progress timer',
    'text timer',
  ]) {
    test(
      'watchdog scheduling failure retains shutdown ownership: $failure',
      () async {
        final sentinel = _ControlledSentinel();
        final repository = _ControlledRepository();
        final clock = _WatchdogClock();
        var scheduled = 0;
        final failureCall = failure == 'initial timer'
            ? 1
            : failure == 'maximum timer'
            ? 2
            : 3;
        final controller = ChatStateController(
          sentinel: sentinel,
          watchdogTimerFactory: (duration, action) {
            if (++scheduled == failureCall)
              throw StateError('private/watchdog/path unavailable');
            return clock.schedule(duration, action);
          },
        );
        final escaped = <Object>[];
        final startErrors = <Object>[];
        final visible = <String>[];
        final errors = <String>[];
        controller.onToken = visible.add;
        controller.onError = errors.add;
        Future<void>? starting;
        try {
          await runZonedGuarded<Future<void>>(() async {
            starting = controller.startGeneration(
              repository: repository,
              messages: messages,
              options: options,
            );
            unawaited(
              starting!.then<void>(
                (_) {},
                onError: (Object error, StackTrace stack) =>
                    startErrors.add(error),
              ),
            );
            if (failure == 'progress timer')
              repository.addProgress(
                const RuntimeProgress(
                  requestId: 1,
                  phase: RuntimeProgressPhase.promptEvaluating,
                  completedUnits: 1,
                  elapsedMicroseconds: 1,
                ),
              );
            if (failure == 'text timer')
              repository.addText('should not be displayed');
            await Future<void>(() {});
          }, (error, stack) => escaped.add(error))!;
          expect(escaped, isEmpty);
          expect(startErrors, isEmpty);
          expect(repository.cancelCalls, 1);
          expect(controller.status, ChatStatus.interrupting);
          await expectLater(
            controller.startGeneration(
              repository: repository,
              messages: messages,
              options: options,
            ),
            throwsA(isA<InferenceRuntimeBusy>()),
          );
          repository.acknowledgeCancellation();
          await controller.cancelInference();
          await starting;
          expect(controller.status, ChatStatus.error);
          expect(controller.cleanupFailed, isFalse);
          expect(visible, isEmpty);
          expect(errors.single, isNot(contains('private/watchdog/path')));
        } finally {
          repository.acknowledgeCancellation();
          await controller.close();
          await repository.close();
          await sentinel.close();
        }
      },
    );
  }

  for (final failure in [
    'closed stream',
    'reason throws',
    'subscription throws',
  ]) {
    test('lost safety observation cancels generation: $failure', () async {
      final sentinel = _ControlledSentinel(
        throwOnReason: failure == 'reason throws',
        throwOnSubscribe: failure == 'subscription throws',
      );
      final repository = _ControlledRepository();
      final controller = ChatStateController(sentinel: sentinel);
      final escaped = <Object>[];
      final startErrors = <Object>[];
      final visible = <String>[];
      final errors = <String>[];
      controller.onToken = visible.add;
      controller.onError = errors.add;
      Future<void>? starting;
      try {
        await runZonedGuarded<Future<void>>(() async {
          starting = controller.startGeneration(
            repository: repository,
            messages: messages,
            options: options,
          );
          unawaited(
            starting!.then<void>(
              (_) {},
              onError: (Object error, StackTrace stack) {
                startErrors.add(error);
              },
            ),
          );
          if (failure == 'closed stream') await sentinel.close();
          if (failure == 'reason throws') sentinel.emit(false);
          await Future<void>(() {});
        }, (error, stack) => escaped.add(error))!;
        expect(escaped, isEmpty);
        expect(startErrors, isEmpty);
        expect(repository.cancelCalls, 1);
        expect(controller.status, ChatStatus.interrupting);
        repository.addText('must not be visible');
        repository.acknowledgeCancellation();
        await controller.cancelInference();
        await starting;
        expect(controller.status, ChatStatus.error);
        expect(controller.cleanupFailed, isFalse);
        expect(visible, isEmpty);
        expect(errors.single, isNot(contains('private/sensor/path')));
      } finally {
        repository.acknowledgeCancellation();
        await controller.close();
        await repository.close();
        await sentinel.close();
      }
    });
  }

  test(
    'health stream error requests acknowledged shutdown without leaking details',
    () async {
      final sentinel = _ControlledSentinel();
      final repository = _ControlledRepository();
      final controller = ChatStateController(sentinel: sentinel);
      final escaped = <Object>[];
      final displayedErrors = <String>[];
      final visible = <String>[];
      controller.onError = displayedErrors.add;
      controller.onToken = visible.add;
      try {
        await runZonedGuarded<Future<void>>(() async {
          await controller.startGeneration(
            repository: repository,
            messages: messages,
            options: options,
          );
          sentinel.fail(StateError('private/model/path sensor failed'));
          await Future<void>(() {});
        }, (error, stack) => escaped.add(error))!;
        expect(escaped, isEmpty);
        expect(repository.cancelCalls, 1);
        expect(controller.status, ChatStatus.interrupting);
        repository.addText('late output');
        repository.acknowledgeCancellation();
        await controller.cancelInference();
        expect(controller.status, ChatStatus.error);
        expect(controller.cleanupFailed, isFalse);
        expect(visible, isEmpty);
        expect(controller.failureCode, ChatFailureCode.generationFailed);
        expect(displayedErrors.single, isNot(contains('private/model/path')));
      } finally {
        repository.acknowledgeCancellation();
        await controller.close();
        await repository.close();
        await sentinel.close();
      }
    },
  );

  test(
    'unacknowledged Stop expires without restarting native shutdown',
    () async {
      final sentinel = _ControlledSentinel();
      final repository = _ControlledRepository();
      final clock = _WatchdogClock();
      final controller = ChatStateController(
        sentinel: sentinel,
        watchdogTimerFactory: clock.schedule,
        watchdogPolicy: const GenerationWatchdogPolicy(
          noProgressTimeout: Duration.zero,
          maximumRequestDuration: Duration.zero,
        ),
      );
      Future<void>? stopping;
      try {
        await controller.startGeneration(
          repository: repository,
          messages: messages,
          options: options,
        );
        stopping = controller.cancelInference();
        clock.advance(Duration.zero);
        await Future<void>(() {});
        expect(controller.status, ChatStatus.error);
        expect(controller.cleanupFailed, isTrue);
        await stopping;
        expect(repository.cancelCalls, 1);
        await expectLater(
          controller.startGeneration(
            repository: repository,
            messages: messages,
            options: options,
          ),
          throwsStateError,
        );
        final retry = controller.recoverOwnedCleanup();
        clock.advance(Duration.zero);
        expect(await retry, RuntimeRecoveryOutcome.terminationUnconfirmed);
        expect(repository.cancelCalls, 1);
        repository.acknowledgeCancellation();
        await Future<void>(() {});
        expect(
          controller.cleanupFailed,
          isTrue,
          reason: 'Late native completion cannot establish recovery by itself',
        );
        expect(
          await controller.recoverOwnedCleanup(),
          RuntimeRecoveryOutcome.recovered,
        );
        expect(repository.cancelCalls, 1);
      } finally {
        repository.acknowledgeCancellation();
        await stopping;
        if (controller.cleanupFailed) await controller.recoverOwnedCleanup();
        await controller.close();
        await repository.close();
        await sentinel.close();
      }
    },
  );

  test('disposed Stop expiry stays failed until explicit recovery', () async {
    final sentinel = _ControlledSentinel();
    final repository = _ControlledRepository();
    final clock = _WatchdogClock();
    final controller = ChatStateController(
      sentinel: sentinel,
      watchdogTimerFactory: clock.schedule,
      watchdogPolicy: const GenerationWatchdogPolicy(
        noProgressTimeout: Duration.zero,
        maximumRequestDuration: Duration.zero,
      ),
    );
    await controller.startGeneration(
      repository: repository,
      messages: messages,
      options: options,
    );
    final closing = controller.close();
    final failed = expectLater(
      closing,
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    clock.advance(Duration.zero);
    await failed;
    expect(controller.isDisposed, isTrue);
    expect(controller.cleanupFailed, isTrue);
    expect(repository.cancelCalls, 1);
    repository.acknowledgeCancellation();
    await Future<void>(() {});
    expect(controller.cleanupFailed, isTrue);
    expect(
      await controller.recoverOwnedCleanup(),
      RuntimeRecoveryOutcome.recovered,
    );
    await controller.close();
    await expectLater(closing, throwsA(isA<InferenceRecoveryRequired>()));
    await expectLater(
      controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
      ),
      throwsStateError,
    );
    await repository.close();
    await sentinel.close();
  });

  test('stalled owner recovery reuses its actor after deadline', () async {
    final sentinel = _ControlledSentinel();
    final repository = _QuarantinedRepository();
    final clock = _WatchdogClock();
    final controller = ChatStateController(
      sentinel: sentinel,
      watchdogTimerFactory: clock.schedule,
      watchdogPolicy: const GenerationWatchdogPolicy(
        noProgressTimeout: Duration.zero,
        maximumRequestDuration: Duration.zero,
      ),
    );
    await controller.startGeneration(
      repository: repository,
      messages: messages,
      options: options,
    );
    final stopping = controller.cancelInference();
    clock.advance(Duration.zero);
    await stopping;
    expect(repository.quarantined, isTrue);
    repository.acknowledgeCancellation();
    await Future<void>(() {});
    final recovery = controller.recoverOwnedCleanup();
    await Future<void>(() {});
    expect(repository.recoveryCalls, 1);
    clock.advance(Duration.zero);
    expect(await recovery, RuntimeRecoveryOutcome.terminationUnconfirmed);
    final next = controller.recoverOwnedCleanup();
    await Future<void>(() {});
    expect(repository.recoveryCalls, 1);
    repository.recoveryAcknowledgement.complete(
      RuntimeRecoveryOutcome.recovered,
    );
    expect(await next, RuntimeRecoveryOutcome.recovered);
    expect(repository.cancelCalls, 1);
    expect(controller.cleanupFailed, isFalse);
    await controller.close();
    await repository.close();
    await sentinel.close();
  });

  test('native progress cannot extend the maximum request duration', () async {
    final sentinel = _ControlledSentinel();
    final repository = _ControlledRepository(autoAcknowledgeCancel: true);
    final clock = _WatchdogClock();
    final controller = ChatStateController(
      sentinel: sentinel,
      watchdogTimerFactory: clock.schedule,
      watchdogPolicy: const GenerationWatchdogPolicy(
        noProgressTimeout: Duration(seconds: 10),
        maximumRequestDuration: Duration(seconds: 20),
      ),
    );
    addTearDown(() async {
      await controller.close();
      await repository.close();
      await sentinel.close();
    });
    await controller.startGeneration(
      repository: repository,
      messages: messages,
      options: options,
    );
    for (final units in [128, 256]) {
      clock.advance(const Duration(seconds: 8));
      repository.addProgress(
        RuntimeProgress(
          requestId: 7,
          phase: RuntimeProgressPhase.promptEvaluating,
          completedUnits: units,
          elapsedMicroseconds: clock.elapsed.inMicroseconds,
        ),
      );
      await Future<void>(() {});
    }
    expect(repository.cancelCalls, 0);
    clock.advance(const Duration(seconds: 4));
    await controller.cancelInference();
    expect(repository.cancelCalls, 1);
    expect(controller.status, ChatStatus.error);
  });

  test(
    'retired watchdog callbacks cannot cancel a replacement request',
    () async {
      final sentinel = _ControlledSentinel();
      final repository = _ControlledRepository(autoAcknowledgeCancel: true);
      final next = _ControlledRepository(autoAcknowledgeCancel: true);
      final clock = _WatchdogClock();
      final controller = ChatStateController(
        sentinel: sentinel,
        watchdogTimerFactory: clock.schedule,
      );
      addTearDown(() async {
        await controller.close();
        await repository.close();
        await next.close();
        await sentinel.close();
      });
      await controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
      );
      final staleCallbacks = clock.timers.map((timer) => timer.action).toList();
      await controller.cancelInference();
      await controller.startGeneration(
        repository: next,
        messages: messages,
        options: options,
      );
      for (final callback in staleCallbacks) {
        callback();
      }
      await Future<void>(() {});
      expect(next.cancelCalls, 0);
      expect(controller.status, ChatStatus.generating);
      await controller.close();
    },
  );

  test('native decode progress keeps a text-silent request alive', () async {
    final sentinel = _ControlledSentinel();
    final repository = _ControlledRepository(autoAcknowledgeCancel: true);
    final clock = _WatchdogClock();
    final controller = ChatStateController(
      sentinel: sentinel,
      watchdogTimerFactory: clock.schedule,
      watchdogPolicy: const GenerationWatchdogPolicy(
        noProgressTimeout: Duration(seconds: 10),
        maximumRequestDuration: Duration(minutes: 1),
      ),
    );
    addTearDown(() async {
      await controller.close();
      await repository.close();
      await sentinel.close();
    });
    await controller.startGeneration(
      repository: repository,
      messages: messages,
      options: options,
    );
    clock.advance(const Duration(seconds: 8));
    repository.addProgress(
      const RuntimeProgress(
        requestId: 7,
        phase: RuntimeProgressPhase.promptEvaluating,
        completedUnits: 128,
        elapsedMicroseconds: 8000000,
      ),
    );
    await Future<void>(() {});
    clock.advance(const Duration(seconds: 8));
    expect(repository.cancelCalls, 0);
    // Duplicate and unrelated request progress cannot prolong this deadline.
    repository.addProgress(
      const RuntimeProgress(
        requestId: 7,
        phase: RuntimeProgressPhase.promptEvaluating,
        completedUnits: 128,
        elapsedMicroseconds: 16000000,
      ),
    );
    repository.addProgress(
      const RuntimeProgress(
        requestId: 8,
        phase: RuntimeProgressPhase.promptEvaluating,
        completedUnits: 256,
        elapsedMicroseconds: 16000000,
      ),
    );
    await Future<void>(() {});
    clock.advance(const Duration(seconds: 3));
    expect(repository.cancelCalls, 1);
    await controller.cancelInference();
    expect(controller.status, ChatStatus.error);
    await controller.close();
    await repository.close();
    await sentinel.close();
  });

  test('recovery callback failure cannot clear cleanup quarantine', () async {
    final sentinel = _ControlledSentinel();
    final repository = _ControlledRepository(
      failCancellation: true,
      autoAcknowledgeCancel: true,
    );
    final controller = ChatStateController(sentinel: sentinel);
    addTearDown(() async {
      controller.dispose();
      await repository.close();
      await sentinel.close();
    });
    await controller.startGeneration(
      repository: repository,
      messages: messages,
      options: options,
    );
    await controller.cancelInference();
    repository.failCancellation = false;
    controller.onStatusChanged = (status) {
      if (status == ChatStatus.idle)
        throw StateError('fixture callback failure');
    };
    expect(
      await controller.recoverOwnedCleanup(),
      RuntimeRecoveryOutcome.terminationUnconfirmed,
    );
    expect(controller.cleanupFailed, isTrue);
    controller.onStatusChanged = null;
    expect(
      await controller.recoverOwnedCleanup(),
      RuntimeRecoveryOutcome.recovered,
    );
  });

  test('healthy controller cannot invoke failed-owner recovery', () async {
    final sentinel = _ControlledSentinel();
    final controller = ChatStateController(sentinel: sentinel);
    addTearDown(() async {
      await controller.close();
      await sentinel.close();
    });
    await expectLater(
      controller.recoverOwnedCleanup(),
      throwsA(isA<InferenceRuntimeBusy>()),
    );
  });

  test(
    'disposed controller recovery shares acknowledgement without reviving it',
    () async {
      final sentinel = _ControlledSentinel();
      final repository = _ControlledRepository(failCancellation: true);
      final controller = ChatStateController(sentinel: sentinel);
      addTearDown(() async {
        repository.failCancellation = false;
        repository.acknowledgeCancellation();
        await repository.close();
        await sentinel.close();
      });
      await controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
      );
      final failedClose = controller.close();
      await expectLater(failedClose, throwsA(isA<InferenceRecoveryRequired>()));
      expect(
        await controller.recoverOwnedCleanup(),
        RuntimeRecoveryOutcome.terminationUnconfirmed,
      );
      expect(controller.cleanupFailed, isTrue);
      repository.failCancellation = false;
      final recovering = controller.recoverOwnedCleanup();
      expect(controller.recoverOwnedCleanup(), same(recovering));
      await expectLater(
        controller.startGeneration(
          repository: repository,
          messages: messages,
          options: options,
        ),
        throwsStateError,
      );
      expect(controller.cleanupFailed, isTrue);
      repository.acknowledgeCancellation();
      expect(await recovering, RuntimeRecoveryOutcome.recovered);
      expect(controller.isDisposed, isTrue);
      expect(controller.cleanupFailed, isFalse);
      await controller.close();
      await expectLater(failedClose, throwsA(isA<InferenceRecoveryRequired>()));
    },
  );

  test(
    'native work remaining after acknowledgement prevents recovery',
    () async {
      final sentinel = _ControlledSentinel();
      final repository = _ControlledRepository(autoAcknowledgeCancel: true)
        ..nativeWorkAfterAcknowledgement = true;
      final controller = ChatStateController(sentinel: sentinel);
      addTearDown(() async {
        controller.dispose();
        await repository.close();
        await sentinel.close();
      });
      await controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
      );
      await controller.cancelInference();
      expect(controller.cleanupFailed, isTrue);
      expect(
        await controller.recoverOwnedCleanup(),
        RuntimeRecoveryOutcome.terminationUnconfirmed,
      );
      repository.nativeWorkAfterAcknowledgement = false;
      expect(
        await controller.recoverOwnedCleanup(),
        RuntimeRecoveryOutcome.recovered,
      );
      expect(controller.cleanupFailed, isFalse);
      expect(controller.status, ChatStatus.idle);
    },
  );

  test(
    'close reports Stop expiry while health cleanup remains pending',
    () async {
      final acknowledgement = Completer<void>();
      final sentinel = _ControlledSentinel(
        onCancel: () => acknowledgement.future,
      );
      final repository = _ControlledRepository(autoAcknowledgeCancel: true);
      final clock = _WatchdogClock();
      final controller = ChatStateController(
        sentinel: sentinel,
        watchdogTimerFactory: clock.schedule,
        watchdogPolicy: const GenerationWatchdogPolicy(
          noProgressTimeout: Duration.zero,
          maximumRequestDuration: Duration.zero,
        ),
      );
      await controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
      );
      Object? failure;
      final closing = controller.close().then<void>(
        (_) {},
        onError: (Object error) {
          failure = error;
        },
      );
      try {
        clock.advance(Duration.zero);
        await Future<void>(() {});
        expect(failure, isA<InferenceRecoveryRequired>());
        expect(controller.cleanupFailed, isTrue);
      } finally {
        acknowledgement.complete();
        await closing;
        await Future<void>(() {});
        await controller.recoverOwnedCleanup();
        await repository.close();
        await sentinel.close();
      }
    },
  );

  test(
    'idle close bounds retained health cleanup and recovers explicitly',
    () async {
      final acknowledgement = Completer<void>();
      final sentinel = _ControlledSentinel(
        onCancel: () => acknowledgement.future,
      );
      final repository = _ControlledRepository();
      final clock = _WatchdogClock();
      final controller = ChatStateController(
        sentinel: sentinel,
        watchdogTimerFactory: clock.schedule,
        watchdogPolicy: const GenerationWatchdogPolicy(
          noProgressTimeout: Duration.zero,
          maximumRequestDuration: Duration.zero,
        ),
      );
      await controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
      );
      repository.finish();
      await Future<void>(() {});
      expect(controller.status, ChatStatus.idle);
      Object? failure;
      final originalClose = controller.close();
      final observing = originalClose.then<void>(
        (_) {},
        onError: (Object error) {
          failure = error;
        },
      );
      try {
        // Idle close first observes the already-settled request before arming
        // the separate retained sensor-cleanup deadline.
        await Future<void>(() {});
        clock.advance(Duration.zero);
        await Future<void>(() {});
        expect(failure, isA<InferenceRecoveryRequired>());
        expect(repository.cancelCalls, 0);
        acknowledgement.complete();
        await Future<void>(() {});
        expect(controller.cleanupFailed, isTrue);
        expect(
          await controller.recoverOwnedCleanup(),
          RuntimeRecoveryOutcome.recovered,
        );
        await controller.close();
        expect(controller.isDisposed, isTrue);
      } finally {
        if (!acknowledgement.isCompleted) acknowledgement.complete();
        await observing;
        await repository.close();
        await sentinel.close();
      }
    },
  );

  test('close also drains asynchronous health subscription shutdown', () async {
    final cancelled = Completer<void>();
    final acknowledgement = Completer<void>();
    final sentinel = _ControlledSentinel(
      onCancel: () {
        cancelled.complete();
        return acknowledgement.future;
      },
    );
    final repository = _ControlledRepository(autoAcknowledgeCancel: true);
    final controller = ChatStateController(sentinel: sentinel);
    addTearDown(() async {
      if (!acknowledgement.isCompleted) acknowledgement.complete();
      await repository.close();
      await sentinel.close();
    });
    await controller.startGeneration(
      repository: repository,
      messages: messages,
      options: options,
    );
    var finished = false;
    final closing = controller.close().then((_) => finished = true);
    await cancelled.future;
    // Let the native acknowledgement settle without acknowledging the sensor.
    final stopping = controller.cancelInference();
    // A scheduled event drains existing microtasks without a wall-clock delay.
    await Future<void>(() {});
    final finishedBeforeHealthAcknowledgement = finished;
    acknowledgement.complete();
    await stopping;
    await closing;
    expect(finishedBeforeHealthAcknowledgement, isFalse);
  });

  test('close shares shutdown and waits for native acknowledgement', () async {
    final sentinel = _ControlledSentinel();
    final repository = _ControlledRepository();
    final controller = ChatStateController(sentinel: sentinel);
    addTearDown(() async {
      repository.acknowledgeCancellation();
      await controller.cancelInference();
      await repository.close();
      await sentinel.close();
    });
    await controller.startGeneration(
      repository: repository,
      messages: messages,
      options: options,
    );
    final closing = controller.close();
    var finished = false;
    final observing = closing.then((_) => finished = true);
    expect(controller.close(), same(closing));
    controller.dispose();
    expect(controller.isDisposed, isTrue);
    await expectLater(
      controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
      ),
      throwsStateError,
    );
    expect(finished, isFalse);
    expect(repository.cancelCalls, 1);
    expect(repository.hasListener, isTrue);
    repository.acknowledgeCancellation();
    await observing;
    expect(repository.hasListener, isFalse);
    expect(controller.cleanupFailed, isFalse);
  });

  test(
    'health cleanup failure keeps close failed and runtime unavailable',
    () async {
      final sentinel = _ControlledSentinel(
        onCancel: () => Future.error(StateError('private/path sensor cleanup')),
      );
      final repository = _ControlledRepository(autoAcknowledgeCancel: true);
      final controller = ChatStateController(sentinel: sentinel);
      addTearDown(() async {
        await repository.close();
        await sentinel.close();
      });
      await controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
      );
      final closing = controller.close();
      await expectLater(closing, throwsA(isA<InferenceRecoveryRequired>()));
      expect(controller.cleanupFailed, isTrue);
      expect(controller.status, ChatStatus.error);
      controller.dispose();
      expect(controller.close(), same(closing));
    },
  );

  test('failed close stays observable after synchronous disposal', () async {
    final sentinel = _ControlledSentinel();
    final repository = _ControlledRepository(failCancellation: true);
    final controller = ChatStateController(sentinel: sentinel);
    addTearDown(() async {
      await repository.close();
      await sentinel.close();
    });
    await controller.startGeneration(
      repository: repository,
      messages: messages,
      options: options,
    );
    final closing = controller.close();
    await expectLater(closing, throwsA(isA<InferenceRecoveryRequired>()));
    expect(controller.cleanupFailed, isTrue);
    controller.dispose();
    expect(controller.close(), same(closing));
    await expectLater(
      controller.close(),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    expect(repository.cancelCalls, 1);
    expect(controller.status, ChatStatus.error);
  });

  test('idle close is shared and does not start native cleanup', () async {
    final sentinel = _ControlledSentinel();
    final controller = ChatStateController(sentinel: sentinel);
    addTearDown(sentinel.close);
    final closing = controller.close();
    expect(controller.close(), same(closing));
    await closing;
    expect(controller.isDisposed, isTrue);
    expect(controller.cleanupFailed, isFalse);
  });

  test(
    'generation rejects pending Stop instead of queueing behind it',
    () async {
      final sentinel = _ControlledSentinel();
      final repository = _ControlledRepository();
      final next = _ControlledRepository(autoAcknowledgeCancel: true);
      final controller = ChatStateController(sentinel: sentinel);
      addTearDown(() async {
        repository.acknowledgeCancellation();
        await controller.cancelInference();
        controller.dispose();
        await repository.close();
        await next.close();
        await sentinel.close();
      });
      await controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
      );
      final stopping = controller.cancelInference();
      final competing = controller.startGeneration(
        repository: next,
        messages: messages,
        options: options,
      );
      // Attach the failure observer before releasing the controlled old owner.
      // The old implementation waits, then incorrectly starts this request.
      final rejected = expectLater(
        competing,
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      repository.acknowledgeCancellation();
      await stopping;
      await rejected;
      expect(next.lastMessages, isNull);
    },
  );

  test('status callback disposal cannot start native work', () async {
    final sentinel = _ControlledSentinel();
    final repository = _ControlledRepository(autoAcknowledgeCancel: true);
    final controller = ChatStateController(sentinel: sentinel);
    addTearDown(() async {
      await controller.cancelInference();
      await repository.close();
      await sentinel.close();
    });
    controller.onStatusChanged = (status) {
      if (status == ChatStatus.generating) controller.dispose();
    };
    await expectLater(
      controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
      ),
      throwsStateError,
    );
    expect(repository.lastMessages, isNull);
    expect(repository.hasListener, isFalse);
  });

  test('status callback Stop prevents stream startup', () async {
    final sentinel = _ControlledSentinel();
    final repository = _ControlledRepository(autoAcknowledgeCancel: true);
    final controller = ChatStateController(sentinel: sentinel);
    addTearDown(() async {
      controller.dispose();
      await repository.close();
      await sentinel.close();
    });
    Future<void>? stopping;
    controller.onStatusChanged = (status) {
      if (status == ChatStatus.generating)
        stopping = controller.cancelInference();
    };
    await controller.startGeneration(
      repository: repository,
      messages: messages,
      options: options,
    );
    await stopping;
    expect(repository.lastMessages, isNull);
    expect(repository.hasListener, isFalse);
    expect(controller.status, ChatStatus.idle);
  });

  test(
    'Stop keeps terminal stream attached until native acknowledgement',
    () async {
      final sentinel = _ControlledSentinel();
      final repository = _ControlledRepository();
      final controller = ChatStateController(sentinel: sentinel);
      addTearDown(() async {
        controller.dispose();
        await repository.close();
        await sentinel.close();
      });
      await controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
      );
      final stopping = controller.cancelInference();
      await _flush();
      expect(
        repository.hasListener,
        isTrue,
        reason: 'Terminal native events must still be consumed',
      );
      repository.acknowledgeCancellation();
      await stopping;
      expect(repository.hasListener, isFalse);
      expect(controller.status, ChatStatus.idle);
    },
  );

  for (final boundary in ['status', 'metrics']) {
    test(
      'completion cannot finish a reentrant request from $boundary callback',
      () async {
        final sentinel = _ControlledSentinel();
        final first = _ControlledRepository(
          autoAcknowledgeCancel: true,
          metrics: const LlamaCppInferenceMetrics(
            promptTokens: 1,
            generatedTokens: 1,
            modelLoadMicros: 1,
            contextInitMicros: 1,
            promptEvalMicros: 1,
            generationMicros: 1,
            timeToFirstTokenMicros: 1,
            completionReason: 'eog',
          ),
        );
        final next = _ControlledRepository(autoAcknowledgeCancel: true);
        final controller = ChatStateController(sentinel: sentinel);
        addTearDown(() async {
          controller.dispose();
          await first.close();
          await next.close();
          await sentinel.close();
        });
        final started = Completer<void>();
        var switched = false;
        var completionCount = 0;
        void startNext() {
          if (switched) return;
          switched = true;
          unawaited(
            controller
                .startGeneration(
                  repository: next,
                  messages: messages,
                  options: options,
                )
                .then<void>(started.complete, onError: started.completeError),
          );
        }

        controller.onComplete = () => completionCount++;
        if (boundary == 'status') {
          controller.onStatusChanged = (status) {
            if (status == ChatStatus.idle) startNext();
          };
        } else {
          controller.onMetrics = (_) => startNext();
        }
        await controller.startGeneration(
          repository: first,
          messages: messages,
          options: options,
        );
        await first.close();
        await started.future;
        expect(controller.status, ChatStatus.generating);
        expect(next.lastMessages, isNotNull);
        expect(
          completionCount,
          0,
          reason: 'The terminal event belongs only to the previous request',
        );
      },
    );
  }

  test(
    'failed cancellation blocks new work instead of reporting idle',
    () async {
      final sentinel = _ControlledSentinel();
      final repository = _ControlledRepository(failCancellation: true);
      final controller = ChatStateController(sentinel: sentinel);
      addTearDown(() {
        controller.dispose();
        repository.close();
        sentinel.close();
      });
      await controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
      );
      await controller.cancelInference();
      expect(controller.status, ChatStatus.error);
      expect(
        controller.failureCode,
        ChatFailureCode.cancellationUnacknowledged,
      );
      await expectLater(
        controller.startGeneration(
          repository: repository,
          messages: messages,
          options: options,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'error keeps native ownership until acknowledgement and rejects late text',
    () async {
      final sentinel = _ControlledSentinel();
      final repository = _ControlledRepository();
      final controller = ChatStateController(sentinel: sentinel);
      addTearDown(() {
        controller.dispose();
        repository.close();
        sentinel.close();
      });
      final tokens = <String>[];
      var completions = 0;
      controller.onToken = tokens.add;
      controller.onComplete = () {
        completions++;
      };
      await controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
      );
      repository.fail(StateError('decode failure'));
      await _flush();
      expect(controller.status, ChatStatus.interrupting);
      expect(repository.cancelCalls, 1);
      repository.addText('late');
      repository.finish();
      await _flush();
      expect(controller.status, ChatStatus.interrupting);
      repository.acknowledgeCancellation();
      await _flush();
      expect(controller.status, ChatStatus.error);
      expect(tokens, isEmpty);
      expect(completions, 0);
    },
  );

  test(
    'disposal during Stop shares cancellation and rejects restart',
    () async {
      final sentinel = _ControlledSentinel();
      final repository = _ControlledRepository();
      final controller = ChatStateController(sentinel: sentinel);
      await controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
      );
      final stop = controller.cancelInference();
      controller.dispose();
      expect(repository.cancelCalls, 1);
      repository.acknowledgeCancellation();
      await stop;
      await expectLater(
        controller.startGeneration(
          repository: repository,
          messages: messages,
          options: options,
        ),
        throwsStateError,
      );
      await repository.close();
      await sentinel.close();
    },
  );

  test(
    'streams visible output, metrics, completion, and returns idle',
    () async {
      final sentinel = _ControlledSentinel();
      final repository = _ControlledRepository(
        metrics: const LlamaCppInferenceMetrics(
          promptTokens: 2,
          generatedTokens: 1,
          modelLoadMicros: 3,
          contextInitMicros: 4,
          promptEvalMicros: 5,
          generationMicros: 6,
          timeToFirstTokenMicros: 7,
          completionReason: 'eog',
        ),
      );
      final controller = ChatStateController(sentinel: sentinel);
      addTearDown(() {
        controller.dispose();
        repository.close();
        sentinel.close();
      });
      final statuses = <ChatStatus>[];
      final tokens = <String>[];
      LlamaCppInferenceMetrics? metrics;
      var completed = false;
      controller
        ..onStatusChanged = statuses.add
        ..onToken = tokens.add
        ..onMetrics = (value) {
          metrics = value;
        }
        ..onComplete = () => completed = true;

      await controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
        think: true,
      );
      repository
        ..addText('answer')
        ..addStatusOnly()
        ..finish();
      await _flush();

      expect(repository.lastThink, isTrue);
      expect(repository.lastMessages, same(messages));
      expect(tokens, ['answer']);
      expect(metrics?.completionReason, 'eog');
      expect(completed, isTrue);
      expect(statuses, [ChatStatus.generating, ChatStatus.idle]);
      expect(controller.isIdle, isTrue);
    },
  );

  test(
    'rejects overlapping generation and accepts a new run after cancel',
    () async {
      final sentinel = _ControlledSentinel();
      final first = _ControlledRepository();
      final second = _ControlledRepository();
      final controller = ChatStateController(sentinel: sentinel);
      addTearDown(() {
        controller.dispose();
        first.close();
        second.close();
        sentinel.close();
      });

      await controller.startGeneration(
        repository: first,
        messages: messages,
        options: options,
      );
      await expectLater(
        controller.startGeneration(
          repository: second,
          messages: messages,
          options: options,
        ),
        throwsA(isA<StateError>()),
      );

      final cancel = controller.cancelInference();
      expect(controller.isInterrupting, isTrue);
      first.acknowledgeCancellation();
      await cancel;
      expect(controller.isIdle, isTrue);

      await controller.startGeneration(
        repository: second,
        messages: messages,
        options: options,
      );
      second.finish();
      await _flush();
      expect(controller.isIdle, isTrue);
    },
  );

  test('concurrent cancellation callers share acknowledgement path', () async {
    final sentinel = _ControlledSentinel();
    final repository = _ControlledRepository();
    final controller = ChatStateController(sentinel: sentinel);
    addTearDown(() {
      controller.dispose();
      repository.close();
      sentinel.close();
    });
    await controller.startGeneration(
      repository: repository,
      messages: messages,
      options: options,
    );

    final first = controller.cancelInference();
    final second = controller.cancelInference();
    repository.acknowledgeCancellation();
    await Future.wait([first, second]);

    expect(repository.cancelCalls, 1);
    expect(controller.status, ChatStatus.idle);
    await controller.cancelInference();
    controller.cancel();
    expect(repository.cancelCalls, 1);
  });

  test(
    'stream errors are typed as controller errors and cancel output',
    () async {
      final sentinel = _ControlledSentinel();
      final repository = _ControlledRepository(autoAcknowledgeCancel: true);
      final controller = ChatStateController(sentinel: sentinel);
      addTearDown(() {
        controller.dispose();
        repository.close();
        sentinel.close();
      });
      final errors = <String>[];
      controller.onError = errors.add;

      await controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
      );
      repository.fail(StateError('decode failed'));
      await _flush();

      expect(controller.status, ChatStatus.error);
      expect(errors.single, contains('decode failed'));
      expect(repository.cancelCalls, 1);
    },
  );

  test('synchronous start failures recover on the next request', () async {
    final sentinel = _ControlledSentinel();
    final broken = _ControlledRepository(
      throwOnStart: true,
      autoAcknowledgeCancel: true,
    );
    final working = _ControlledRepository();
    final controller = ChatStateController(sentinel: sentinel);
    addTearDown(() {
      controller.dispose();
      broken.close();
      working.close();
      sentinel.close();
    });
    final errors = <String>[];
    controller.onError = errors.add;

    await controller.startGeneration(
      repository: broken,
      messages: messages,
      options: options,
    );
    expect(controller.status, ChatStatus.error);
    expect(errors.single, contains('Failed to start generation'));

    await controller.startGeneration(
      repository: working,
      messages: messages,
      options: options,
    );
    working.finish();
    await _flush();
    expect(controller.status, ChatStatus.idle);
  });

  test(
    'unsafe health event invokes acknowledged emergency cancellation',
    () async {
      final sentinel = _ControlledSentinel(reason: 'critical memory');
      final repository = _ControlledRepository(autoAcknowledgeCancel: true);
      final controller = ChatStateController(sentinel: sentinel);
      addTearDown(() {
        controller.dispose();
        repository.close();
        sentinel.close();
      });
      final errors = <String>[];
      controller.onError = errors.add;

      await controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
      );
      sentinel.emit(false);
      await _flush();

      expect(repository.cancelCalls, 1);
      expect(controller.status, ChatStatus.error);
      expect(errors.single, 'critical memory');
    },
  );

  test('no-progress and maximum-duration watchdogs cancel safely', () async {
    for (final policy in [
      const GenerationWatchdogPolicy(
        noProgressTimeout: Duration(milliseconds: 5),
        maximumRequestDuration: Duration(seconds: 1),
      ),
      const GenerationWatchdogPolicy(
        noProgressTimeout: Duration(seconds: 1),
        maximumRequestDuration: Duration(milliseconds: 5),
      ),
    ]) {
      final sentinel = _ControlledSentinel();
      final repository = _ControlledRepository(autoAcknowledgeCancel: true);
      final controller = ChatStateController(
        sentinel: sentinel,
        watchdogPolicy: policy,
      );
      final errors = <String>[];
      controller.onError = errors.add;
      await controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(repository.cancelCalls, 1);
      expect(controller.status, ChatStatus.error);
      expect(errors, hasLength(1));
      controller.dispose();
      await repository.close();
      await sentinel.close();
    }
  });

  test(
    'dispose is idempotent, rejects late output, and cancels active work',
    () async {
      final sentinel = _ControlledSentinel();
      final repository = _ControlledRepository(autoAcknowledgeCancel: true);
      final controller = ChatStateController(sentinel: sentinel);
      final tokens = <String>[];
      controller.onToken = tokens.add;
      await controller.startGeneration(
        repository: repository,
        messages: messages,
        options: options,
      );

      controller
        ..dispose()
        ..dispose();
      repository.addText('late');
      await _flush();

      expect(controller.isDisposed, isTrue);
      expect(repository.cancelCalls, 1);
      expect(tokens, isEmpty);
      await repository.close();
      await sentinel.close();
    },
  );
}

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 2));

class _WatchdogClock {
  Duration elapsed = Duration.zero;
  final timers = <_WatchdogTimer>[];
  Timer schedule(Duration duration, void Function() action) {
    final timer = _WatchdogTimer(elapsed + duration, action);
    timers.add(timer);
    return timer;
  }

  void advance(Duration duration) {
    elapsed += duration;
    for (final timer in timers.toList()) {
      if (timer.isActive && timer.deadline <= elapsed) timer.fire();
    }
  }
}

class _WatchdogTimer implements Timer {
  _WatchdogTimer(this.deadline, this.action);
  final Duration deadline;
  final void Function() action;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  void fire() {
    isActive = false;
    tick++;
    action();
  }

  @override
  void cancel() => isActive = false;
}

final class _QuarantinedRepository extends _ControlledRepository {
  bool quarantined = false;
  int recoveryCalls = 0;
  final recoveryAcknowledgement = Completer<RuntimeRecoveryOutcome>();
  @override
  void retainOwnedRecovery() => quarantined = true;
  @override
  Future<RuntimeRecoveryOutcome> recoverOwnedSession() {
    recoveryCalls++;
    return recoveryAcknowledgement.future.then((result) {
      if (result == RuntimeRecoveryOutcome.recovered) quarantined = false;
      return result;
    });
  }

  @override
  RuntimeOperationSnapshot get operationSnapshot => RuntimeOperationSnapshot(
    state: quarantined
        ? RuntimeReservationState.recoveryRequired
        : RuntimeReservationState.idle,
    kind: RuntimeOperationKind.interactive,
    ownerId: 1,
    contextOwnerId: 1,
    hasRetainedContext: true,
    sessionGeneration: 1,
    nativeRequestId: _cancelAcknowledgement.isCompleted ? null : 1,
    cancellationRequested: true,
    recoveryOutcome: null,
    initializationPending: false,
    initializationRecoveryRequired: false,
  );
}

final class _ControlledRepository implements LlamaCppChatRepository {
  _ControlledRepository({
    this.metrics,
    this.throwOnStart = false,
    this.autoAcknowledgeCancel = false,
    this.failCancellation = false,
  });

  final StreamController<LLMChunk> _chunks = StreamController<LLMChunk>();
  bool get hasListener => _chunks.hasListener;
  final Completer<void> _cancelAcknowledgement = Completer<void>();
  final LlamaCppInferenceMetrics? metrics;
  final bool throwOnStart;
  final bool autoAcknowledgeCancel;
  bool failCancellation;
  bool nativeWorkAfterAcknowledgement = false;
  int cancelCalls = 0;
  bool? lastThink;
  List<LLMMessage>? lastMessages;

  @override
  LlamaCppInferenceMetrics? get lastMetrics => metrics;

  @override
  RuntimeOperationSnapshot get operationSnapshot => RuntimeOperationSnapshot(
    state: RuntimeReservationState.idle,
    kind: RuntimeOperationKind.interactive,
    ownerId: 1,
    contextOwnerId: 1,
    hasRetainedContext: true,
    sessionGeneration: 1,
    nativeRequestId: nativeWorkAfterAcknowledgement ? 1 : null,
    cancellationRequested: true,
    recoveryOutcome: null,
    initializationPending: false,
    initializationRecoveryRequired: false,
  );

  @override
  Stream<LLMChunk> streamChatWithGenerationOptions(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    LLMChatOptions? options,
    GenerationOptions? generationOptions,
  }) {
    if (throwOnStart) throw StateError('start failed');
    lastThink = think;
    lastMessages = messages;
    return _chunks.stream;
  }

  @override
  Future<void> cancelActiveInference() {
    cancelCalls++;
    if (failCancellation)
      return Future.error(StateError('native acknowledgement unavailable'));
    if (autoAcknowledgeCancel && !_cancelAcknowledgement.isCompleted) {
      _cancelAcknowledgement.complete();
    }
    return _cancelAcknowledgement.future;
  }

  void acknowledgeCancellation() {
    if (!_cancelAcknowledgement.isCompleted) _cancelAcknowledgement.complete();
  }

  void addText(String text) => _chunks.add(
    LLMChunk(
      model: 'fixture',
      createdAt: DateTime.utc(2026),
      message: LLMChunkMessage(content: text, role: LLMRole.assistant),
    ),
  );

  void addProgress(RuntimeProgress progress) =>
      _chunks.add(LlamaCppProgressChunk(progress));

  void addStatusOnly() => _chunks.add(
    LLMChunk(
      model: 'fixture',
      createdAt: DateTime.utc(2026),
      message: null,
      status: 'evaluating',
    ),
  );

  void fail(Object error) => _chunks.addError(error);
  void finish() => _chunks.close();
  Future<void> close() async {
    if (_chunks.isClosed) return;
    // A never-opened single-subscription stream needs a drain listener for
    // close() to settle. Correct startup suppression now exercises this case.
    final drain = lastMessages == null ? _chunks.stream.listen(null) : null;
    await _chunks.close();
    await drain?.cancel();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ControlledSentinel implements HardwareSentinelService {
  _ControlledSentinel({
    this.reason,
    this.throwOnReason = false,
    this.throwOnSubscribe = false,
    Future<void> Function()? onCancel,
  }) : _health = onCancel == null
           ? StreamController<bool>.broadcast()
           : StreamController<bool>(onCancel: onCancel);

  final StreamController<bool> _health;
  final String? reason;
  final bool throwOnReason;
  final bool throwOnSubscribe;
  bool _disposed = false;

  void emit(bool safe) => _health.add(safe);
  void fail(Object error) => _health.addError(error);
  Future<void> close() => _health.close();

  @override
  Stream<bool> get onHealthChanged {
    if (throwOnSubscribe)
      throw StateError('private/sensor/path subscription failed');
    return _health.stream;
  }

  @override
  bool get isDisposed => _disposed;
  @override
  String? unsafeReasonHeavy() {
    if (throwOnReason) throw StateError('private/sensor/path reading failed');
    return reason;
  }

  @override
  void dispose() => _disposed = true;
  @override
  int? get currentLevel => 100;
  @override
  bool? get isCharging => true;
  @override
  bool? get isInSaveMode => false;
  @override
  ConnectivityResult? get connectivityType => ConnectivityResult.wifi;
  @override
  int get memoryPressureLevel => 0;
  @override
  bool isSafeForHeavyOperation() => reason == null;
  @override
  bool isSafeForDownload() => reason == null;
  @override
  String? unsafeReasonDownload() => reason;
  @override
  void checkHeavyOperation() {}
  @override
  void checkDownload() {}
  @override
  Future<void> init() async {}
}
