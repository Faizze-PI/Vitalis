import 'dart:async';

import 'package:llm_llamacpp/src/exceptions.dart';
import 'package:llm_llamacpp/src/runtime_progress.dart';
import 'package:llm_llamacpp/src/runtime_watchdog_policy.dart';

/// A waiting deadline never cancels the native initialization it observes.
class RuntimeInitializationGuard {
  RuntimeInitializationGuard({
    required this.timeout,
    Duration? maximumDuration,
    RuntimeWatchdogTimerFactory timerFactory = Timer.new,
    int Function()? readMonotonicMicros,
    this.onRecoveryRequired,
  }) : maximumDuration = maximumDuration ?? timeout,
       _timerFactory = timerFactory {
    if (timeout < Duration.zero || this.maximumDuration < Duration.zero) {
      throw ArgumentError('Invalid runtime deadline policy');
    }
    final clock = Stopwatch()..start();
    _readMicros = readMonotonicMicros ?? () => clock.elapsedMicroseconds;
  }

  final Duration timeout;
  final Duration maximumDuration;
  final RuntimeWatchdogTimerFactory _timerFactory;
  final void Function()? onRecoveryRequired;
  late final int Function() _readMicros;
  final _progress = RuntimeProgressTracker();
  Timer? _noProgressTimer;
  Timer? _maximumTimer;
  int _deadlineEpoch = 0;
  int _maximumEpoch = 0;
  int _startedMicros = 0;
  int _lastProgressMicros = 0;
  Completer<void>? _waiting;
  bool _recoveryCallbackFailed = false;
  bool _hasObservedFailure = false;
  bool _watchdogSchedulingFailed = false;
  bool get recoveryCallbackFailed => _recoveryCallbackFailed;
  bool get hasObservedFailure => _hasObservedFailure;
  bool get watchdogSchedulingFailed => _watchdogSchedulingFailed;
  Future<void>? _operation;
  Future<void>? _waiter;
  bool _settled = false;
  bool _succeeded = false;
  bool _needsRecovery = false;

  bool get needsRecovery => _needsRecovery;
  bool get isPending => _operation != null && !_settled;

  bool observeProgress(RuntimeProgress progress) {
    if (!isPending || _needsRecovery || !_progress.accept(progress))
      return false;
    _observeDeadline(() {
      _lastProgressMicros = _readMicros();
      _armNoProgress();
    });
    return !_needsRecovery;
  }

  void _observeDeadline(void Function() observe) {
    try {
      observe();
    } catch (_) {
      // A broken clock/scheduler cannot release the native operation or leave
      // its waiting UI silently pending. Quarantine until owned cleanup.
      _watchdogSchedulingFailed = true;
      _expire();
    }
  }

  void _armNoProgress() {
    _noProgressTimer?.cancel();
    final epoch = ++_deadlineEpoch;
    final remaining =
        timeout.inMicroseconds - (_readMicros() - _lastProgressMicros);
    _noProgressTimer = _timerFactory(Duration(microseconds: remaining), () {
      if (!isPending || _needsRecovery || epoch != _deadlineEpoch) return;
      _observeDeadline(() {
        if (_readMicros() - _lastProgressMicros < timeout.inMicroseconds) {
          _armNoProgress();
        } else {
          _expire();
        }
      });
    });
  }

  void _armMaximum() {
    _maximumTimer?.cancel();
    final epoch = ++_maximumEpoch;
    final remaining =
        maximumDuration.inMicroseconds - (_readMicros() - _startedMicros);
    _maximumTimer = _timerFactory(Duration(microseconds: remaining), () {
      if (!isPending || _needsRecovery || epoch != _maximumEpoch) return;
      _observeDeadline(() {
        if (_readMicros() - _startedMicros < maximumDuration.inMicroseconds) {
          _armMaximum();
        } else {
          _expire();
        }
      });
    });
  }

  void _retireTimers() {
    _deadlineEpoch++;
    _maximumEpoch++;
    _noProgressTimer?.cancel();
    _maximumTimer?.cancel();
  }

  void _requireRecovery() {
    if (_needsRecovery) return;
    _needsRecovery = true;
    try {
      onRecoveryRequired?.call();
    } catch (_) {
      // The failed hook cannot confirm ownership cleanup or hide quarantine.
      _recoveryCallbackFailed = true;
    }
  }

  void _expire() {
    _retireTimers();
    _requireRecovery();
    if (!_waiting!.isCompleted)
      _waiting!.completeError(InferenceRecoveryRequired());
  }

  Future<void> ensure(Future<void> Function() initialize) {
    if (_needsRecovery) return Future.error(InferenceRecoveryRequired());
    final existing = _waiter;
    if (existing != null) return existing;
    final completion = Completer<void>();
    _operation = completion.future;
    _waiting = Completer<void>();
    _waiter = _waiting!.future;
    // Keep original failure available to cleanup without an unhandled duplicate.
    unawaited(
      _operation!.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          _hasObservedFailure = true;
        },
      ),
    );
    try {
      _startedMicros = _lastProgressMicros = _readMicros();
    } catch (error, stack) {
      _settled = true;
      _requireRecovery();
      completion.completeError(error, stack);
      _waiting!.completeError(error, stack);
      return _waiter!;
    }
    // Install ownership before invoking a synchronously reentrant adapter.
    unawaited(
      Future<void>.sync(initialize).then<void>(
        (_) {
          _settled = true;
          _succeeded = true;
          _retireTimers();
          completion.complete();
          if (!_waiting!.isCompleted) _waiting!.complete();
        },
        onError: (Object error, StackTrace stack) {
          _settled = true;
          _retireTimers();
          _requireRecovery();
          completion.completeError(error, stack);
          if (!_waiting!.isCompleted) _waiting!.completeError(error, stack);
        },
      ),
    );
    _observeDeadline(() {
      _armNoProgress();
      _armMaximum();
    });
    return _waiter!;
  }

  /// Cleanup may observe late completion, but cannot start a second helper.
  Future<void> settleForCleanup(Future<void> Function() initialize) {
    if (_operation == null) return ensure(initialize);
    return _operation!;
  }

  /// Call only after the owner receives native unload acknowledgement.
  void confirmCleanup() {
    if (!_settled || !_succeeded) throw InferenceRecoveryRequired();
    _needsRecovery = false;
    _waiter = Future<void>.value();
  }
}
