final class ModelStorageBusy extends StateError {
  ModelStorageBusy() : super('Model storage operation is active');
}

final class ModelIdentityMismatch extends StateError {
  ModelIdentityMismatch()
    : super('The selected file is a different model; import it separately');
}

final class ModelSelectionCancelled extends StateError {
  ModelSelectionCancelled() : super('Model file selection cancelled');
}

final class ModelProbeSafetyStop extends StateError {
  ModelProbeSafetyStop() : super('Model check paused for device safety');
}
