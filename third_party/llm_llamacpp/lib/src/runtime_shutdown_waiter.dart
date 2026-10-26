import 'dart:async';

import 'package:llm_llamacpp/src/runtime_initialization_guard.dart';
import 'package:llm_llamacpp/src/runtime_watchdog_policy.dart';

/// Bounds waiting, never the lifetime of the underlying owned shutdown.
/// This is observation bookkeeping; the runtime reservation owns the context.
class RuntimeShutdownWaiter {
  RuntimeShutdownWaiter({
    required this.shutdown,
    required this.timeout,
    this.timerFactory = Timer.new,
    this.readMonotonicMicros,
    this.onUnconfirmed,
  });
  final Future<void> Function() shutdown;
  final Duration timeout;
  final RuntimeWatchdogTimerFactory timerFactory;
  final int Function()? readMonotonicMicros;
  final void Function()? onUnconfirmed;
  Future<void>? _operation;
  RuntimeInitializationGuard? _waiting;
  bool _settled = false;
  bool _failed = false;
  bool get hasPendingOperation => _operation != null && !_settled;

  Future<void> wait({bool retryFailedOperation = false}) {
    var guard = _waiting;
    if (guard == null || guard.needsRecovery) {
      guard = RuntimeInitializationGuard(
        timeout: timeout,
        timerFactory: timerFactory,
        readMonotonicMicros: readMonotonicMicros,
        onRecoveryRequired: onUnconfirmed,
      );
      _waiting = guard;
    }
    return guard.ensure(() {
      final retained = _operation;
      if (retained != null && (!_settled || !_failed || !retryFailedOperation))
        return retained;
      final completion = Completer<void>();
      _operation = completion.future;
      _settled = false;
      _failed = false;
      // Install operation identity before invoking a reentrant control adapter.
      unawaited(
        Future<void>.sync(shutdown).then<void>(
          (_) {
            _settled = true;
            completion.complete();
          },
          onError: (Object error, StackTrace stack) {
            _settled = true;
            _failed = true;
            completion.completeError(error, stack);
          },
        ),
      );
      return completion.future;
    });
  }
}
