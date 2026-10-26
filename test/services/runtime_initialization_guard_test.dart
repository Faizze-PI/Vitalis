import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/runtime_initialization_guard.dart';

void main() {
  RuntimeProgress progress(int units) => RuntimeProgress(
    requestId: 7,
    phase: RuntimeProgressPhase.modelLoading,
    completedUnits: units,
    elapsedMicroseconds: units,
  );

  test(
    'progress resets inactivity without changing the maximum deadline',
    () async {
      final clock = _DeadlineClock();
      final native = Completer<void>();
      final guard = RuntimeInitializationGuard(
        timeout: const Duration(seconds: 1),
        maximumDuration: const Duration(seconds: 3),
        timerFactory: clock.schedule,
        readMonotonicMicros: () => clock.micros,
      );
      final waiting = guard.ensure(() => native.future);
      final observed = expectLater(
        waiting,
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      for (var unit = 0; unit < 3; unit++) {
        clock.advance(const Duration(milliseconds: 800));
        expect(guard.observeProgress(progress(unit)), isTrue);
      }
      expect(guard.needsRecovery, isFalse);
      clock.advance(const Duration(milliseconds: 600));
      await observed;
      expect(guard.isPending, isTrue);
      expect(guard.needsRecovery, isTrue);
      native.complete();
      await guard.settleForCleanup(() => throw StateError('must not restart'));
      expect(guard.needsRecovery, isTrue);
      guard.confirmCleanup();
      expect(clock.timers.where((timer) => timer.isActive), isEmpty);
    },
  );

  test('duplicate progress cannot postpone inactivity expiry', () async {
    final clock = _DeadlineClock();
    final native = Completer<void>();
    final guard = RuntimeInitializationGuard(
      timeout: const Duration(seconds: 1),
      maximumDuration: const Duration(seconds: 3),
      timerFactory: clock.schedule,
      readMonotonicMicros: () => clock.micros,
    );
    expect(guard.observeProgress(progress(0)), isFalse);
    final waiting = guard.ensure(() => native.future);
    final observed = expectLater(
      waiting,
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    expect(guard.observeProgress(progress(0)), isTrue);
    clock.advance(const Duration(milliseconds: 800));
    expect(guard.observeProgress(progress(0)), isFalse);
    clock.advance(const Duration(milliseconds: 200));
    await observed;
    expect(guard.observeProgress(progress(1)), isFalse);
    native.complete();
    await guard.settleForCleanup(() => throw StateError('must not restart'));
  });

  test('early and retired callbacks cannot expire completed work', () async {
    final clock = _DeadlineClock();
    final native = Completer<void>();
    final guard = RuntimeInitializationGuard(
      timeout: const Duration(seconds: 1),
      maximumDuration: const Duration(seconds: 3),
      timerFactory: clock.schedule,
      readMonotonicMicros: () => clock.micros,
    );
    final waiting = guard.ensure(() => native.future);
    final original = clock.timers.toList();
    for (final timer in original) {
      timer.callback(); // Queued callback observed before its deadline.
      timer.callback(); // Old epoch must not schedule another deadline.
    }
    expect(clock.timers.where((timer) => timer.isActive), hasLength(2));
    expect(guard.needsRecovery, isFalse);
    native.complete();
    await waiting;
    for (final timer in clock.timers) {
      timer.callback(); // Even a cancelled callback cannot revive completion.
    }
    expect(guard.isPending, isFalse);
    expect(guard.needsRecovery, isFalse);
    expect(guard.observeProgress(progress(1)), isFalse);
  });

  test(
    'recovery hook failure remains quarantined and does not rerun',
    () async {
      final clock = _DeadlineClock();
      final native = Completer<void>();
      var hooks = 0;
      final guard = RuntimeInitializationGuard(
        timeout: Duration.zero,
        timerFactory: clock.schedule,
        readMonotonicMicros: () => clock.micros,
        onRecoveryRequired: () {
          hooks++;
          throw StateError('injected recovery hook failure');
        },
      );
      final waiting = guard.ensure(() => native.future);
      final observed = expectLater(
        waiting,
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      clock.advance(Duration.zero);
      await observed;
      expect(guard.recoveryCallbackFailed, isTrue);
      expect(guard.needsRecovery, isTrue);
      for (final timer in clock.timers) {
        timer.callback();
      }
      expect(hooks, 1);
      native.complete();
      await guard.settleForCleanup(() => throw StateError('must not restart'));
    },
  );

  test('scheduler failure retains the already-started operation', () async {
    final native = Completer<void>();
    var starts = 0;
    final guard = RuntimeInitializationGuard(
      timeout: const Duration(seconds: 1),
      timerFactory: (_, _) => throw StateError('injected scheduler failure'),
    );
    await expectLater(
      guard.ensure(() {
        starts++;
        return native.future;
      }),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    expect(starts, 1);
    expect(guard.watchdogSchedulingFailed, isTrue);
    expect(guard.isPending, isTrue);
    native.complete();
    await guard.settleForCleanup(() => throw StateError('must not restart'));
  });

  test('clock setup failure never starts an unowned initialization', () async {
    var starts = 0;
    final guard = RuntimeInitializationGuard(
      timeout: const Duration(seconds: 1),
      readMonotonicMicros: () => throw StateError('injected clock failure'),
    );
    await expectLater(
      guard.ensure(() async {
        starts++;
      }),
      throwsStateError,
    );
    expect(starts, 0);
    expect(guard.isPending, isFalse);
    expect(guard.needsRecovery, isTrue);
    expect(guard.hasObservedFailure, isTrue);
  });

  for (final failClock in [false, true]) {
    test(
      'progress adapter failure retains native ownership ($failClock)',
      () async {
        final clock = _DeadlineClock();
        final native = Completer<void>();
        var fail = false;
        final guard = RuntimeInitializationGuard(
          timeout: const Duration(seconds: 1),
          timerFactory: (delay, callback) {
            if (fail && !failClock) throw StateError('scheduler failure');
            return clock.schedule(delay, callback);
          },
          readMonotonicMicros: () {
            if (fail && failClock) throw StateError('clock failure');
            return clock.micros;
          },
        );
        final waiting = guard.ensure(() => native.future);
        final observed = expectLater(
          waiting,
          throwsA(isA<InferenceRecoveryRequired>()),
        );
        fail = true;
        expect(() => guard.observeProgress(progress(1)), returnsNormally);
        await observed;
        expect(guard.isPending, isTrue);
        expect(guard.needsRecovery, isTrue);
        native.complete();
        await guard.settleForCleanup(
          () => throw StateError('must not restart'),
        );
        expect(guard.needsRecovery, isTrue);
        guard.confirmCleanup();
      },
    );
  }

  test('negative deadline policy is rejected', () {
    expect(
      () => RuntimeInitializationGuard(timeout: const Duration(seconds: -1)),
      throwsArgumentError,
    );
    expect(
      () => RuntimeInitializationGuard(
        timeout: Duration.zero,
        maximumDuration: const Duration(seconds: -1),
      ),
      throwsArgumentError,
    );
  });
  test('pending initialization recognizes actual native progress', () async {
    final native = Completer<void>();
    final guard = RuntimeInitializationGuard(
      timeout: const Duration(seconds: 1),
    );
    final waiting = guard.ensure(() => native.future);
    try {
      expect(
        guard.observeProgress(
          const RuntimeProgress(
            requestId: 7,
            phase: RuntimeProgressPhase.modelLoading,
            completedUnits: 1,
            elapsedMicroseconds: 1,
          ),
        ),
        isTrue,
      );
    } finally {
      native.complete();
      await waiting;
    }
  });
  test('initialization callers share one operation', () async {
    final guard = RuntimeInitializationGuard(
      timeout: const Duration(seconds: 1),
    );
    final native = Completer<void>();
    var starts = 0;
    Future<void> start() {
      starts++;
      return native.future;
    }

    final first = guard.ensure(start);
    expect(guard.ensure(start), same(first));
    expect(starts, 1);
    native.complete();
    await first;
    expect(guard.isPending, isFalse);
    await guard.ensure(start);
    expect(starts, 1);
  });

  for (final fails in [false, true]) {
    test('timeout retains late native result (failure: $fails)', () async {
      final guard = RuntimeInitializationGuard(timeout: Duration.zero);
      final native = Completer<void>();
      var starts = 0;
      Future<void> start() {
        starts++;
        return native.future;
      }

      await expectLater(
        guard.ensure(start),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      expect(guard.isPending, isTrue);
      expect(guard.needsRecovery, isTrue);
      await expectLater(
        guard.ensure(start),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      expect(starts, 1);
      expect(guard.confirmCleanup, throwsA(isA<InferenceRecoveryRequired>()));
      final cleanup = guard.settleForCleanup(start);
      final observed = fails ? expectLater(cleanup, throwsStateError) : cleanup;
      if (fails) {
        native.completeError(StateError('fixture'));
      } else {
        native.complete();
      }
      await observed;
      expect(guard.isPending, isFalse);
      expect(guard.needsRecovery, isTrue);
      if (fails) {
        expect(guard.confirmCleanup, throwsA(isA<InferenceRecoveryRequired>()));
      } else {
        guard.confirmCleanup();
        await guard.ensure(start);
        expect(guard.needsRecovery, isFalse);
      }
      expect(starts, 1);
    });
  }
}

class _DeadlineClock {
  int micros = 0;
  final timers = <_DeadlineTimer>[];
  Timer schedule(Duration delay, void Function() callback) {
    final timer = _DeadlineTimer(micros + delay.inMicroseconds, callback);
    timers.add(timer);
    return timer;
  }

  void advance(Duration duration) {
    micros += duration.inMicroseconds;
    for (final timer in timers.toList()) {
      if (timer.isActive && timer.deadline <= micros) timer.fire();
    }
  }
}

class _DeadlineTimer implements Timer {
  _DeadlineTimer(this.deadline, this.callback);
  final int deadline;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;
  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() {
    _active = false;
  }

  void fire() {
    if (!_active) return;
    _active = false;
    _tick++;
    callback();
  }
}
