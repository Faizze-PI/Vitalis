import 'package:flutter/foundation.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import '../models/model_descriptor.dart';
import '../models/model_storage_error.dart';
import '../models/model_verification_phase.dart';

enum ModelRecoveryState {
  verifying,
  succeeded,
  runtimeBusy,
  storageBusy,
  recoveryRequired,
  cancelled,
  safetyStopped,
  failed,
}

/// Provider-owned verification only: never selects, deletes or substitutes models.
final class ModelRecoveryController extends ChangeNotifier {
  ModelRecoveryController(this.verify);
  final Future<ModelDescriptor> Function(String) verify;
  final _pending = <String, Future<ModelDescriptor>>{};
  final _states = <String, ModelRecoveryState>{};
  final _phases = <String, ModelVerificationPhase>{};
  bool _disposed = false;

  ModelRecoveryState? stateFor(String id) => _states[id];
  ModelVerificationPhase? phaseFor(String id) => _phases[id];

  ModelVerificationPhaseSink phaseReporter(String id) {
    final operation = _pending[id];
    return (phase) {
      if (_disposed || operation == null || !identical(_pending[id], operation))
        return;
      _phases[id] = phase;
      notifyListeners();
    };
  }

  Future<ModelDescriptor> recover(String id) =>
      recoverUsing(id, () => verify(id));

  Future<ModelDescriptor> recoverUsing(
    String id,
    Future<ModelDescriptor> Function() action,
  ) {
    if (_disposed)
      return Future.error(StateError('Model recovery is disposed'));
    final existing = _pending[id];
    if (existing != null) return existing;
    _states[id] = ModelRecoveryState.verifying;
    _phases.remove(id);
    final operation = Future<ModelDescriptor>.microtask(() => _run(id, action));
    _pending[id] = operation;
    notifyListeners();
    return operation;
  }

  Future<ModelDescriptor> _run(
    String id,
    Future<ModelDescriptor> Function() action,
  ) async {
    try {
      if (_disposed) throw StateError('Model recovery is disposed');
      final model = await action();
      if (model.id != id) throw StateError('Recovery model identity mismatch');
      if (!_disposed) _states[id] = ModelRecoveryState.succeeded;
      return model;
    } on ModelProbeSafetyStop {
      if (!_disposed) _states[id] = ModelRecoveryState.safetyStopped;
      rethrow;
    } on ModelSelectionCancelled {
      if (!_disposed) _states[id] = ModelRecoveryState.cancelled;
      rethrow;
    } on ModelStorageBusy {
      if (!_disposed) _states[id] = ModelRecoveryState.storageBusy;
      rethrow;
    } on InferenceRuntimeBusy {
      if (!_disposed) _states[id] = ModelRecoveryState.runtimeBusy;
      rethrow;
    } on InferenceRecoveryRequired {
      if (!_disposed) _states[id] = ModelRecoveryState.recoveryRequired;
      rethrow;
    } catch (_) {
      if (!_disposed) _states[id] = ModelRecoveryState.failed;
      rethrow;
    } finally {
      _pending.remove(id);
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
