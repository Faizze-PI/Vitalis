import 'package:flutter/material.dart';
import '../models/model_verification_phase.dart';
import '../services/model_recovery_controller.dart';

/// Pure status text: no skeleton/empty placeholder or animated progress needed.
class ModelRecoveryStatusLabel extends StatelessWidget {
  const ModelRecoveryStatusLabel({super.key, required this.state, this.phase});
  final ModelRecoveryState? state;
  final ModelVerificationPhase? phase;

  static String message(
    ModelRecoveryState? state,
    ModelVerificationPhase? phase,
  ) => switch (state) {
    ModelRecoveryState.verifying => switch (phase) {
      ModelVerificationPhase.hashing => 'Checking model files…',
      ModelVerificationPhase.metadata => 'Reading model information…',
      ModelVerificationPhase.waitingForRuntime =>
        'Checking runtime availability…',
      ModelVerificationPhase.inferenceCheck => 'Testing local inference…',
      null => 'Preparing verification…',
    },
    ModelRecoveryState.succeeded =>
      'Verified. Use for this chat is a separate action.',
    ModelRecoveryState.runtimeBusy =>
      'Runtime busy. Try verification again when it is idle.',
    ModelRecoveryState.storageBusy =>
      'Model storage busy. Retry after the current install or removal finishes.',
    ModelRecoveryState.recoveryRequired =>
      'Runtime recovery required before verification can continue.',
    ModelRecoveryState.cancelled =>
      'File selection cancelled. Your model is unchanged.',
    ModelRecoveryState.safetyStopped =>
      'Model check paused for device safety. Try again when the device is ready.',
    ModelRecoveryState.failed =>
      'Verification could not finish. Your chat assignments are unchanged.',
    null => '',
  };

  @override
  Widget build(BuildContext context) => state == null
      ? const SizedBox.shrink()
      : Semantics(
          liveRegion: true,
          child: Text(
            message(state, phase),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        );
}
