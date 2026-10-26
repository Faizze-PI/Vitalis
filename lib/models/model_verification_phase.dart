enum ModelVerificationPhase {
  hashing,
  metadata,
  waitingForRuntime,
  inferenceCheck,
}

typedef ModelVerificationPhaseSink = void Function(ModelVerificationPhase);
