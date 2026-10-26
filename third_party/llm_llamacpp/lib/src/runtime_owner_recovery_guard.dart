import 'dart:async';

import 'package:llm_llamacpp/src/exceptions.dart';
import 'package:llm_llamacpp/src/runtime_session_reservation.dart';

/// Shares an owner's recovery attempt, not native ownership itself. The
/// existing reservation remains the only authority for cancellation/unload.
class RuntimeOwnerRecoveryGuard {
  Future<RuntimeRecoveryOutcome>? _pending;
  bool get isRecovering => _pending != null;
  Future<RuntimeRecoveryOutcome>? get pending => _pending;

  Future<RuntimeRecoveryOutcome> run({
    required bool recoveryAllowed,
    required Future<RuntimeRecoveryOutcome> Function() recover,
  }) {
    final pending = _pending;
    if (pending != null) return pending;
    if (!recoveryAllowed) return Future.error(InferenceRuntimeBusy());
    final completion = Completer<RuntimeRecoveryOutcome>();
    _pending = completion.future;
    unawaited(
      Future<RuntimeRecoveryOutcome>.sync(recover).then<void>(
        (outcome) {
          _pending = null;
          completion.complete(outcome);
        },
        onError: (Object _, StackTrace __) {
          // A failed observer/adapter is unconfirmed, never a readiness signal.
          _pending = null;
          completion.complete(RuntimeRecoveryOutcome.terminationUnconfirmed);
        },
      ),
    );
    return completion.future;
  }
}
