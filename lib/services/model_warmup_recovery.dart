part of 'model_warmup_service.dart';

Future<RuntimeRecoveryOutcome> _recoverModelServiceCleanup(
  ModelWarmupService service, {
  required Future<void>? originalClose,
  required Future<void>? originalTuningStop,
}) async {
  service._tuningCancellation?.cancel();
  // Capture actors before yielding. A close started during recovery awaits
  // recovery itself, so it must never be added to this drain (a self-deadlock).
  final actors = <Future<dynamic>?>[
    originalClose,
    service._tuningFuture,
    originalTuningStop,
    service._preparationFuture,
    service._unloadFuture,
  ].whereType<Future<dynamic>>().toSet();
  final retired = <LlamaCppChatRepository>{};

  Set<LlamaCppChatRepository> retainedOwners() => {
    if (service._repository case final owner?) owner,
    if (service._preparingRepository case final owner?) owner,
    if (service._tuningRepository case final owner?) owner,
  };

  Future<bool> retireOwners() async {
    for (final owner in retainedOwners()) {
      if (retired.contains(owner)) continue;
      try {
        await owner.close();
      } catch (_) {
        if (!owner.cleanupFailed) return false;
        final outcome = await owner.recoverAfterClose();
        if (outcome != RuntimeRecoveryOutcome.recovered ||
            owner.cleanupFailed) {
          return false;
        }
      }
      retired.add(owner);
    }
    return true;
  }

  if (!await retireOwners()) {
    return RuntimeRecoveryOutcome.terminationUnconfirmed;
  }
  for (final actor in actors) {
    try {
      await actor;
    } catch (error) {
      // Observe completed historical failures, not a new acceptance pass.
      // Native retirement is independently required above and below.
      AppLogger.instance.warning(
        'Retired model-service actor failed (${error.runtimeType})',
      );
    }
  }
  // Cancellation can settle before discovery creates any native owner.
  // All captured actors must still settle, and every retained owner must retire;
  // do not fabricate an unload merely to make the retired set nonempty.
  if (!await retireOwners()) {
    return RuntimeRecoveryOutcome.terminationUnconfirmed;
  }

  if (!identical(service._closeFuture, originalClose) &&
      service._closeObservationFailed) {
    // This actor confirmed its own retirement, not the newer expired close.
    // Preserve references and quarantine for a separate explicit recovery.
    service._cleanupFailed = true;
    return RuntimeRecoveryOutcome.recovered;
  }
  final ownsStop = identical(service._tuningStopFuture, originalTuningStop);
  if (!ownsStop &&
      (service._tuningStopObservationFailed ||
          (service._tuningStopWaiter?.hasPendingOperation ?? false))) {
    service._cleanupFailed = true;
    return RuntimeRecoveryOutcome.recovered;
  }

  service._repository = null;
  service._preparingRepository = null;
  service._tuningRepository = null;
  service._activeModelPath = null;
  service._effectiveContextSize = null;
  service._effectiveProfile = null;
  service._warmedUp = false;
  service._warmingUp = false;
  service._cleanupFailed = false;
  service._preparationFuture = null;
  service._unloadFuture = null;
  service._tuningFuture = null;
  service._tuningStopFuture = null;
  service._tuningStopWaiter = null;
  service._tuningStopObservationFailed = false;
  service._tuningCancellation = null;
  service._tuningModelId = null;
  service._tuningStatus = RuntimeTuningStatus.cancelled;
  if (identical(service._closeFuture, originalClose)) {
    service._closeFuture = service._isDisposed ? Future<void>.value() : null;
    service._closeWaiter = null;
    service._closeObservationFailed = false;
  }
  service._notifyIfActive();
  return RuntimeRecoveryOutcome.recovered;
}
