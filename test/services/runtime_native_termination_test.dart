import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/runtime_native_termination.dart';

void main() {
  for (final owner in [Object(), null]) {
    test(
      'expired receipt retains owner and late acknowledgement ($owner)',
      () async {
        final timers = <_ReceiptTimer>[];
        final native = RuntimeNativeTermination(
          timeout: Duration.zero,
          readMonotonicMicros: () => 0,
          timerFactory: (_, callback) {
            final timer = _ReceiptTimer(callback);
            timers.add(timer);
            return timer;
          },
        );
        native.register(0, owner);
        final original = native.waitFor(0, owner);
        final rejected = expectLater(
          original,
          throwsA(isA<InferenceRecoveryRequired>()),
        );
        for (final timer in timers.toList()) {
          timer.fire();
        }
        await rejected;
        expect(native.contains(0), isTrue);
        expect(native.needsRecovery, isTrue);
        expect(native.canAccessRecovery(Object()), isFalse);
        expect(
          () => native.confirmRecovery(owner),
          throwsA(isA<InferenceRecoveryRequired>()),
        );
        final resumed = native.waitFor(0, owner);
        expect(native.waitFor(0, owner), same(resumed));
        native.acknowledge(0, cleanupConfirmed: true);
        await resumed;
        expect(native.hasPending, isFalse);
        expect(native.needsRecovery, isTrue);
        expect(() => native.register(0, owner), throwsArgumentError);
        expect(
          () => native.confirmRecovery(Object()),
          throwsA(isA<InferenceRuntimeBusy>()),
        );
        native.confirmRecovery(owner);
        expect(native.needsRecovery, isFalse);
        native.retainUnconfirmed(0, owner);
        expect(native.needsRecovery, isFalse);
        await expectLater(original, throwsA(isA<InferenceRecoveryRequired>()));
      },
    );
  }

  test('concurrent cancellation observers share one acknowledgement', () async {
    final native = RuntimeNativeTermination();
    final owner = Object();
    native.register(0, owner);
    final first = native.waitFor(0, owner);
    final second = native.waitFor(0, owner);
    try {
      expect(second, same(first));
    } finally {
      native.acknowledge(0, cleanupConfirmed: true);
      await Future.wait([first, second]);
    }
  });

  test('competing observer cannot quarantine another request', () async {
    final native = RuntimeNativeTermination();
    final owner = Object();
    native.register(0, owner);
    expect(
      () => native.retainUnconfirmed(0, Object()),
      throwsA(isA<InferenceRuntimeBusy>()),
    );
    expect(native.needsRecovery, isFalse);
    final waiting = native.waitFor(0, owner);
    native.acknowledge(0, cleanupConfirmed: true);
    await waiting;
  });

  test(
    'native acknowledgement does not await paused stream delivery',
    () async {
      final native = RuntimeNativeTermination();
      final owner = Object();
      final stream = StreamController<void>();
      final subscription = stream.stream.listen((_) {})..pause();
      native.register(0, owner);
      final acknowledged = native.waitFor(0, owner);
      var streamFinished = false;
      final delivered = stream.done.then((_) => streamFinished = true);
      stream.add(null);
      unawaited(stream.close());
      try {
        expect(
          native.acknowledge(0, cleanupConfirmed: true),
          NativeTerminationOutcome.acknowledged,
        );
        await acknowledged;
        expect(streamFinished, isFalse);
        expect(native.hasPending, isFalse);
      } finally {
        subscription.resume();
        await delivered;
      }
    },
  );

  test(
    'owner drain excludes another owner and waits for native receipt',
    () async {
      final native = RuntimeNativeTermination();
      final owner = Object();
      final other = Object();
      native.register(0, owner);
      native.register(1, other);
      var finished = false;
      final drained = native.drain(owner).then((_) => finished = true);
      await Future<void>.value();
      expect(finished, isFalse);
      native.acknowledge(0, cleanupConfirmed: true);
      await drained;
      expect(native.contains(1), isTrue);
      native.acknowledge(1, cleanupConfirmed: true);
      await native.drain(owner);
      expect(native.hasPending, isFalse);
    },
  );

  test('rejected waiter cannot disturb its owner', () async {
    final native = RuntimeNativeTermination();
    final owner = Object();
    native.register(0, owner);
    await expectLater(
      native.waitFor(0, Object()),
      throwsA(isA<InferenceRuntimeBusy>()),
    );
    expect(native.contains(0), isTrue);
    final waiting = native.waitFor(0, owner);
    native.acknowledge(0, cleanupConfirmed: true);
    await waiting;
  });

  test('unconfirmed cleanup fails both cancellation and owned drain', () async {
    final native = RuntimeNativeTermination();
    final owner = Object();
    native.register(0, owner);
    final waiting = expectLater(
      native.waitFor(0, owner),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    final draining = expectLater(
      native.drain(owner),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    expect(
      native.acknowledge(0, cleanupConfirmed: false),
      NativeTerminationOutcome.cleanupUnconfirmed,
    );
    await waiting;
    await draining;
    expect(native.hasPending, isFalse);
  });

  test(
    'late duplicate acknowledgement cannot change recorded metrics',
    () async {
      final native = RuntimeNativeTermination();
      var observed = 0;
      Object? recorded;
      final owner = Object();
      native.register(
        0,
        owner,
        onTerminal: (payload) {
          observed++;
          recorded = payload;
        },
      );
      final waiting = native.waitFor(0, owner);
      final terminal = Object();
      native.acknowledge(0, cleanupConfirmed: true, payload: terminal);
      await waiting;
      expect(
        native.acknowledge(0, cleanupConfirmed: true, payload: Object()),
        isNull,
      );
      expect(observed, 1);
      expect(recorded, same(terminal));
    },
  );

  test('observer failure is typed and cannot strand acknowledgement', () async {
    final native = RuntimeNativeTermination();
    final owner = Object();
    native.register(
      0,
      owner,
      onTerminal: (_) => throw StateError('private diagnostic'),
    );
    final waiting = expectLater(
      native.waitFor(0, owner),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    expect(
      native.acknowledge(0, cleanupConfirmed: true),
      NativeTerminationOutcome.observerFailed,
    );
    await waiting;
    expect(native.observerFailureCount, 1);
    expect(native.hasPending, isFalse);
  });

  test(
    'reentrant observer cannot acknowledge twice or reuse its identity',
    () async {
      final native = RuntimeNativeTermination();
      final owner = Object();
      Future<void>? observing;
      native.register(
        0,
        owner,
        onTerminal: (_) {
          observing = native.waitFor(0, owner);
          expect(native.acknowledge(0, cleanupConfirmed: true), isNull);
          expect(() => native.register(0, owner), throwsArgumentError);
        },
      );
      native.acknowledge(0, cleanupConfirmed: true);
      await observing;
      expect(native.observerFailureCount, 0);
    },
  );

  test('invalid unknown and duplicate identities are rejected', () async {
    final native = RuntimeNativeTermination();
    expect(() => native.register(-1, null), throwsArgumentError);
    native.register(0, null);
    expect(() => native.register(0, null), throwsArgumentError);
    await expectLater(native.waitFor(1, null), throwsStateError);
    final waiting = native.waitFor(0, null);
    native.acknowledge(0, cleanupConfirmed: true);
    await waiting;
  });
}

class _ReceiptTimer implements Timer {
  _ReceiptTimer(this.callback);
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
