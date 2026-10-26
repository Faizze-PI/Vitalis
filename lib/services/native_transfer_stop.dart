import 'dart:async';

import 'package:flutter/services.dart';

typedef NativeStopTimerFactory = Timer Function(Duration, void Function());

abstract final class NativeTransferStopPolicy {
  // This bounds a UI waiter, not the native writer's lifetime. Expiry never
  // authorizes deletion or resuming a job (hardcode: HC-050).
  static const acknowledgementTimeout = Duration(
    seconds: 30,
  ); // hardcode: HC-050
  static const pollInterval = Duration(milliseconds: 350); // hardcode: HC-050
}

enum NativeStopFailure {
  deadline,
  inventory,
  identity,
  terminalState,
  transport,
  pending,
}

final class NativeTransferStopUnconfirmed extends StateError {
  NativeTransferStopUnconfirmed(this.reason)
    : super('nativeTransferStopUnconfirmed');

  final NativeStopFailure reason;
}

/// Controls durable writers without treating waiting-time expiry as termination.
final class NativeTransferStopController {
  const NativeTransferStopController({
    required this.channel,
    this.timeout = NativeTransferStopPolicy.acknowledgementTimeout,
    this.pollInterval = NativeTransferStopPolicy.pollInterval,
    this.timerFactory = Timer.new,
    this.monotonicNow,
  });

  final MethodChannel channel;
  final Duration timeout;
  final Duration pollInterval;
  final NativeStopTimerFactory timerFactory;
  final Duration Function()? monotonicNow;

  Future<void> cancelJob(String jobId) async {
    final deadline = _deadline();
    try {
      final values = await deadline.wait(
        () => channel.invokeListMethod<Object?>('list'),
      );
      if (values == null) {
        throw NativeTransferStopUnconfirmed(NativeStopFailure.inventory);
      }
      final identities = <String>{};
      for (final value in values) {
        if (value is! Map || value['jobId'] is! String) {
          throw NativeTransferStopUnconfirmed(NativeStopFailure.inventory);
        }
        if (value['jobId'] != jobId) continue;
        final identity = value['transferId'];
        if (identity is! String ||
            identity.isEmpty ||
            !identities.add(identity)) {
          throw NativeTransferStopUnconfirmed(NativeStopFailure.identity);
        }
      }
      await _stop(jobId, identities, true, deadline);
    } finally {
      deadline.dispose();
    }
  }

  /// Known active identities do not depend on an outstanding progress reply.
  Future<void> stopTransfer(
    String jobId,
    String transferId, {
    required bool cancel,
  }) async {
    final deadline = _deadline();
    try {
      if (jobId.isEmpty || transferId.isEmpty) {
        throw NativeTransferStopUnconfirmed(NativeStopFailure.identity);
      }
      await _stop(jobId, {transferId}, cancel, deadline);
    } finally {
      deadline.dispose();
    }
  }

  _StopDeadline _deadline() {
    if (timeout <= Duration.zero || pollInterval < Duration.zero) {
      throw ArgumentError('Invalid native stop waiting policy');
    }
    return _StopDeadline(timeout, timerFactory, monotonicNow);
  }

  Future<void> _stop(
    String jobId,
    Set<String> identities,
    bool cancel,
    _StopDeadline deadline,
  ) async {
    // Request all shards before waiting for any one acknowledgement.
    for (final identity in identities) {
      await deadline.wait(
        () => channel.invokeMethod<void>(cancel ? 'cancel' : 'pause', {
          'transferId': identity,
        }),
      );
    }
    for (final identity in identities) {
      var recoveryAttempted = false;
      while (true) {
        final snapshot = await deadline.wait(
          () => channel.invokeMapMethod<String, dynamic>('status', {
            'transferId': identity,
          }),
        );
        if (snapshot == null ||
            snapshot['jobId'] != jobId ||
            snapshot['transferId'] != identity) {
          throw NativeTransferStopUnconfirmed(NativeStopFailure.identity);
        }
        final state = snapshot['state'];
        if (state == (cancel ? 'cancelled' : 'paused') &&
            snapshot['stopAcknowledged'] == true)
          break;
        if (!recoveryAttempted &&
            state == (cancel ? 'cancelled' : 'paused') &&
            snapshot['recoveryRequired'] == true) {
          recoveryAttempted = true;
          final recovered = await deadline.wait(
            () => channel.invokeMapMethod<String, dynamic>('recoverStop', {
              'jobId': jobId,
              'transferId': identity,
            }),
          );
          if (recovered == null ||
              recovered['jobId'] != jobId ||
              recovered['transferId'] != identity) {
            throw NativeTransferStopUnconfirmed(NativeStopFailure.identity);
          }
          if (recovered['state'] != (cancel ? 'cancelled' : 'paused') ||
              recovered['stopAcknowledged'] != true) {
            throw NativeTransferStopUnconfirmed(NativeStopFailure.pending);
          }
          continue;
        }
        if (state != 'queued' &&
            state != 'running' &&
            state != 'paused' &&
            state != 'cancelled' &&
            state != 'downloaded' &&
            state != 'validating') {
          throw NativeTransferStopUnconfirmed(NativeStopFailure.terminalState);
        }
        await deadline.pause(pollInterval);
      }
    }
  }
}

/// One absolute monotonic-duration budget spans inventory, every shard and polls.
/// Pending channel callbacks are observed after expiry, but cannot advance work.
final class _StopDeadline {
  _StopDeadline(this.timeout, this._timerFactory, Duration Function()? now) {
    final stopwatch = Stopwatch()..start();
    _now = now ?? () => stopwatch.elapsed;
    _started = _now();
    _timer = _timerFactory(timeout, _expire);
  }

  final Duration timeout;
  final NativeStopTimerFactory _timerFactory;
  late final Duration Function() _now;
  late final Duration _started;
  late final Timer _timer;
  void Function()? _pendingFailure;
  bool _expired = false;
  bool get _pastDeadline => _expired || _now() - _started >= timeout;

  Future<T> wait<T>(Future<T> Function() operation) {
    if (_pastDeadline) {
      _expire();
      return Future<T>.error(
        NativeTransferStopUnconfirmed(NativeStopFailure.deadline),
      );
    }
    final result = Completer<T>();
    _pendingFailure = () {
      if (!result.isCompleted) {
        result.completeError(
          NativeTransferStopUnconfirmed(NativeStopFailure.deadline),
        );
      }
    };
    Future<T>.sync(operation).then(
      (value) {
        if (!result.isCompleted) {
          if (_pastDeadline) {
            _expire();
            return;
          }
          _pendingFailure = null;
          result.complete(value);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) {
          if (_pastDeadline) {
            _expire();
            return;
          }
          _pendingFailure = null;
          result.completeError(error, stack);
        }
      },
    );
    return result.future;
  }

  Future<void> pause(Duration duration) async {
    Timer? delay;
    try {
      await wait(() {
        final ready = Completer<void>();
        delay = _timerFactory(duration, () => ready.complete());
        return ready.future;
      });
    } finally {
      delay?.cancel();
    }
  }

  void _expire() {
    _expired = true;
    final fail = _pendingFailure;
    _pendingFailure = null;
    fail?.call();
  }

  void dispose() {
    _pendingFailure = null;
    _timer.cancel();
  }
}
