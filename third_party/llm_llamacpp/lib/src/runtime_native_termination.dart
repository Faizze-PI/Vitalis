import 'dart:async';

import 'package:llm_llamacpp/src/exceptions.dart';
import 'package:llm_llamacpp/src/runtime_shutdown_waiter.dart';
import 'package:llm_llamacpp/src/runtime_watchdog_policy.dart';

enum NativeTerminationOutcome {
  acknowledged,
  cleanupUnconfirmed,
  observerFailed,
}

/// Native acknowledgement is independent of a paused Dart stream consumer.
/// This tracks request completion, not context ownership or acquisition.
class RuntimeNativeTermination {
  RuntimeNativeTermination({
    this.timeout = RuntimeWatchdogDefaults.noProgressTimeout,
    this.timerFactory = Timer.new,
    this.readMonotonicMicros,
  });
  final Duration timeout;
  final RuntimeWatchdogTimerFactory timerFactory;
  final int Function()? readMonotonicMicros;
  final _requests = <int, _NativeTerminationRequest>{};
  final _unconfirmed = <int, Object?>{};
  int observerFailureCount = 0;
  bool get hasPending => _requests.isNotEmpty;
  bool get needsRecovery => _unconfirmed.isNotEmpty;

  bool canAccessRecovery(Object? owner) =>
      _unconfirmed.values.every((candidate) => identical(candidate, owner));

  void retainUnconfirmed(int id, Object? owner) {
    final request = _requests[id];
    if (request == null && !_unconfirmed.containsKey(id)) return;
    final expected = request?.owner ?? _unconfirmed[id];
    if (!identical(expected, owner)) throw InferenceRuntimeBusy();
    _unconfirmed[id] = owner;
  }

  /// Called after acknowledged native unload, never merely a late receipt.
  void confirmRecovery(Object? owner) {
    if (!canAccessRecovery(owner)) throw InferenceRuntimeBusy();
    if (_requests.values.any((request) => identical(request.owner, owner))) {
      throw InferenceRecoveryRequired();
    }
    _unconfirmed.removeWhere((_, candidate) => identical(candidate, owner));
  }

  void register(int id, Object? owner, {void Function(Object?)? onTerminal}) {
    if (id < 0 || _requests.containsKey(id) || _unconfirmed.containsKey(id)) {
      throw ArgumentError('Invalid or duplicate native request identity');
    }
    _requests[id] = _NativeTerminationRequest(owner, onTerminal);
  }

  bool contains(int id) => _requests.containsKey(id);

  Future<void> waitFor(int id, Object? owner) {
    final request = _requests[id];
    if (request == null) {
      return Future.error(StateError('Unknown native request identity'));
    }
    if (!identical(request.owner, owner)) {
      return Future.error(InferenceRuntimeBusy());
    }
    final waiter = request.waiter ??= RuntimeShutdownWaiter(
      timeout: timeout,
      timerFactory: timerFactory,
      readMonotonicMicros: readMonotonicMicros,
      onUnconfirmed: () => retainUnconfirmed(id, owner),
      shutdown: () async {
        _requireAcknowledged(await request.completion.future);
      },
    );
    return waiter.wait();
  }

  Future<void> drain(Object? owner) async {
    final pending = _requests.values
        .where((request) => identical(request.owner, owner))
        .map((request) => request.completion.future)
        .toList();
    for (final outcome in await Future.wait(pending)) {
      _requireAcknowledged(outcome);
    }
  }

  NativeTerminationOutcome? acknowledge(
    int id, {
    required bool cleanupConfirmed,
    Object? payload,
  }) {
    final request = _requests[id];
    if (request == null || request.receiving) return null;
    request.receiving = true;
    var outcome = cleanupConfirmed
        ? NativeTerminationOutcome.acknowledged
        : NativeTerminationOutcome.cleanupUnconfirmed;
    try {
      request.onTerminal?.call(payload);
    } catch (_) {
      // A failing observer cannot strand acknowledgement or imply readiness.
      observerFailureCount++;
      outcome = NativeTerminationOutcome.observerFailed;
    }
    _requests.remove(id);
    request.completion.complete(outcome);
    return outcome;
  }

  void _requireAcknowledged(NativeTerminationOutcome outcome) {
    if (outcome != NativeTerminationOutcome.acknowledged) {
      throw InferenceRecoveryRequired();
    }
  }
}

class _NativeTerminationRequest {
  _NativeTerminationRequest(this.owner, this.onTerminal);
  final Object? owner;
  final void Function(Object?)? onTerminal;
  final completion = Completer<NativeTerminationOutcome>();
  RuntimeShutdownWaiter? waiter;
  bool receiving = false;
}
