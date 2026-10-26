import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/runtime_shutdown_waiter.dart';

void main() {
  test('reentrant and concurrent waiters share the owned operation', () async {
    final native = Completer<void>();
    late RuntimeShutdownWaiter waiter;
    Future<void>? nested;
    var starts = 0;
    waiter = RuntimeShutdownWaiter(
      timeout: const Duration(seconds: 1),
      shutdown: () {
        starts++;
        nested = waiter.wait();
        return native.future;
      },
    );
    final first = waiter.wait();
    expect(nested, same(first));
    expect(waiter.wait(), same(first));
    expect(waiter.hasPendingOperation, isTrue);
    native.complete();
    await first;
    await waiter.wait();
    expect(starts, 1);
    expect(waiter.hasPendingOperation, isFalse);
  });

  for (final lateFailure in [false, true]) {
    test('expired wait retains late result ($lateFailure)', () async {
      final clock = _Clock();
      final native = Completer<void>();
      var starts = 0;
      final waiter = RuntimeShutdownWaiter(
        timeout: const Duration(seconds: 1),
        timerFactory: clock.schedule,
        readMonotonicMicros: () => clock.micros,
        shutdown: () {
          starts++;
          return starts == 1 ? native.future : Future.value();
        },
      );
      final original = waiter.wait();
      final expired = expectLater(
        original,
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      clock.advance();
      await expired;
      final retry = waiter.wait(retryFailedOperation: true);
      expect(waiter.wait(), same(retry));
      expect(starts, 1);
      expect(waiter.hasPendingOperation, isTrue);
      final observed = lateFailure
          ? expectLater(retry, throwsStateError)
          : retry;
      if (lateFailure) {
        native.completeError(StateError('controlled shutdown error'));
      } else {
        native.complete();
      }
      await observed;
      expect(waiter.hasPendingOperation, isFalse);
      if (lateFailure) {
        await expectLater(waiter.wait(), throwsStateError);
        expect(starts, 1);
      }
      await waiter.wait(retryFailedOperation: true);
      expect(starts, lateFailure ? 2 : 1);
      await expectLater(original, throwsA(isA<InferenceRecoveryRequired>()));
    });
  }

  test('failed shutdown starts another actor only on explicit retry', () async {
    var starts = 0;
    var unconfirmed = 0;
    final waiter = RuntimeShutdownWaiter(
      timeout: const Duration(seconds: 1),
      onUnconfirmed: () => unconfirmed++,
      shutdown: () async {
        if (++starts == 1) throw StateError('control failed');
      },
    );
    await expectLater(waiter.wait(), throwsStateError);
    await expectLater(waiter.wait(), throwsStateError);
    expect(starts, 1);
    await waiter.wait(retryFailedOperation: true);
    expect(starts, 2);
    expect(unconfirmed, 2);
  });

  test(
    'scheduler failure keeps started shutdown and retires old deadlines',
    () async {
      final native = Completer<void>();
      final clock = _Clock();
      var broken = true;
      var starts = 0;
      final waiter = RuntimeShutdownWaiter(
        timeout: const Duration(seconds: 1),
        timerFactory: (delay, callback) {
          if (broken) throw StateError('scheduler failed');
          return clock.schedule(delay, callback);
        },
        readMonotonicMicros: () => clock.micros,
        shutdown: () {
          starts++;
          return native.future;
        },
      );
      await expectLater(
        waiter.wait(),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      expect(waiter.hasPendingOperation, isTrue);
      broken = false;
      final retry = waiter.wait(retryFailedOperation: true);
      native.complete();
      await retry;
      for (final timer in clock.timers) {
        timer.callback();
      }
      expect(starts, 1);
      expect(clock.timers.where((timer) => timer.isActive), isEmpty);
    },
  );

  test('broken clock cannot start an unowned shutdown', () async {
    var broken = true;
    var starts = 0;
    final waiter = RuntimeShutdownWaiter(
      timeout: const Duration(seconds: 1),
      readMonotonicMicros: () {
        if (broken) throw StateError('clock failed');
        return 0;
      },
      shutdown: () async {
        starts++;
      },
    );
    await expectLater(waiter.wait(), throwsStateError);
    expect(starts, 0);
    expect(waiter.hasPendingOperation, isFalse);
    broken = false;
    await waiter.wait(retryFailedOperation: true);
    expect(starts, 1);
  });

  test('negative wait policy is rejected before shutdown', () {
    var starts = 0;
    final waiter = RuntimeShutdownWaiter(
      timeout: const Duration(seconds: -1),
      shutdown: () async {
        starts++;
      },
    );
    expect(waiter.wait, throwsArgumentError);
    expect(starts, 0);
  });
}

class _Clock {
  int micros = 0;
  final timers = <_Timer>[];
  Timer schedule(Duration delay, void Function() callback) {
    final timer = _Timer(micros + delay.inMicroseconds, callback);
    timers.add(timer);
    return timer;
  }

  void advance() {
    micros += const Duration(seconds: 1).inMicroseconds;
    for (final timer in timers.toList()) {
      if (timer.isActive && timer.deadline <= micros) timer.fire();
    }
  }
}

class _Timer implements Timer {
  _Timer(this.deadline, this.callback);
  final int deadline;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;
  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;
  void fire() {
    _active = false;
    _tick++;
    callback();
  }
}
