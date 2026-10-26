part of 'generation_provider.dart';

Future<RuntimeRecoveryOutcome> _recoverGenerationCleanup(
  GenerationProvider provider,
) async {
  provider._stopRequested = true;
  final originalClose = provider._closeFuture;
  final retainedClose = provider._closeWaiter;
  // Capture before yielding: a later close waits for this recovery itself.
  final actors = <Future<void>?>[
    originalClose,
    provider._preparationFuture,
    provider._stopFuture,
  ].whereType<Future<void>>().toSet();
  try {
    if (retainedClose != null) {
      try {
        await retainedClose.wait();
      } catch (_) {
        if (retainedClose.hasPendingOperation) {
          return RuntimeRecoveryOutcome.terminationUnconfirmed;
        }
      }
    }
    // A successful raw close proves all its captured preparation/controller
    // actors settled, even if the original observation expired.
    var confirmedOwner =
        provider._rawCloseConfirmed && provider._closeObservationFailed;
    if (provider._controller.cleanupFailed) {
      final outcome = await provider._controller.recoverOwnedCleanup();
      if (outcome != RuntimeRecoveryOutcome.recovered ||
          provider._controller.cleanupFailed) {
        return RuntimeRecoveryOutcome.terminationUnconfirmed;
      }
      confirmedOwner = true;
    }
    if (provider._warmup.requiresRecovery) {
      final outcome = await provider._warmup.recoverOwnedCleanup();
      if (outcome != RuntimeRecoveryOutcome.recovered ||
          provider._warmup.requiresRecovery) {
        return RuntimeRecoveryOutcome.terminationUnconfirmed;
      }
      confirmedOwner = true;
    }
    if (!confirmedOwner) return RuntimeRecoveryOutcome.terminationUnconfirmed;
    for (final actor in actors) {
      try {
        await actor;
      } catch (error) {
        // Observe historical failures; they are not termination evidence.
        AppLogger.instance.warning(
          'Retired generation actor failed (${error.runtimeType})',
        );
      }
    }
    if (provider._controller.cleanupFailed ||
        provider._warmup.requiresRecovery) {
      return RuntimeRecoveryOutcome.terminationUnconfirmed;
    }
    provider._stopFuture = null;
    provider._recoveryRequired = false;
    provider._isSending = false;
    provider._hasError = false;
    provider._errorMessage = '';
    provider._genBuffer.clear();
    provider._stopRequested = provider._isDisposed;
    provider._notifyIfActive();
    if (provider._isDisposed &&
        identical(provider._closeFuture, originalClose)) {
      provider._closeFuture = Future<void>.value();
      provider._closeObservationFailed = false;
      provider._closeWaiter = null;
    }
    return RuntimeRecoveryOutcome.recovered;
  } catch (error) {
    provider._recoveryRequired = true;
    provider._stopRequested = true;
    AppLogger.instance.warning(
      'Generation recovery unconfirmed (${error.runtimeType})',
    );
    return RuntimeRecoveryOutcome.terminationUnconfirmed;
  }
}
