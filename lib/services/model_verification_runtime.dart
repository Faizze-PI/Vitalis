import 'dart:async';

import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/runtime_owner_recovery_guard.dart';

/// Retains the verification owner until its complete shutdown acknowledges.
/// Rejected admission never authorizes cleanup of another native session.
final class ModelVerificationRuntime {
  LlamaCppChatRepository? _owner;
  bool _cleanupFailed = false;
  final _recovery = RuntimeOwnerRecoveryGuard();
  bool _disposed = false;
  bool _admitted = false;
  Completer<void>? _finished;
  Future<void>? _closeFuture;

  bool get requiresRecovery => _cleanupFailed;
  bool get isRecovering => _recovery.isRecovering;

  void checkAvailable() {
    if (_disposed) throw InferenceRepositoryDisposed();
    if (isRecovering) throw InferenceRuntimeBusy();
    if (_cleanupFailed) throw InferenceRecoveryRequired();
    if (_owner != null) throw InferenceRuntimeBusy();
  }

  Future<T> run<T>(
    LlamaCppChatRepository repository,
    Future<T> Function() action,
  ) async {
    checkAvailable();
    _owner = repository;
    final finished = Completer<void>();
    _finished = finished;
    try {
      return await repository.withExclusiveSession(() async {
        _admitted = true;
        try {
          if (_disposed) throw InferenceRepositoryDisposed();
          return await action();
        } finally {
          await _closeOwner(repository);
        }
      }, kind: RuntimeOperationKind.verification);
    } finally {
      _admitted = false;
      if (!_cleanupFailed) _owner = null;
      finished.complete();
    }
  }

  Future<void> _closeOwner(LlamaCppChatRepository repository) async {
    try {
      await repository.close();
    } catch (_) {
      // Failed resource cleanup is not proof of invalid model bytes.
      _cleanupFailed = true;
      throw InferenceRecoveryRequired();
    }
  }

  /// Scope disposal rejects new work immediately and joins owned termination.
  /// Closing the repository invokes its shared cancellation/drain operation.
  Future<void> close() {
    final pending = _closeFuture;
    if (pending != null) return pending;
    _disposed = true;
    return _closeFuture = _finishClose();
  }

  Future<void> _finishClose() async {
    final recovery = _recovery.pending;
    if (recovery != null &&
        await recovery != RuntimeRecoveryOutcome.recovered) {
      throw InferenceRecoveryRequired();
    }
    final owner = _owner;
    if (_admitted && owner != null) await _closeOwner(owner);
    await _finished?.future;
    if (_cleanupFailed) throw InferenceRecoveryRequired();
  }

  Future<RuntimeRecoveryOutcome> recoverOwnedCleanup() => _recovery.run(
    recoveryAllowed: _cleanupFailed && (_finished?.isCompleted ?? true),
    recover: () async {
      final owner = _owner;
      if (owner == null) return RuntimeRecoveryOutcome.terminationUnconfirmed;
      final outcome = await owner.recoverAfterClose();
      if (outcome == RuntimeRecoveryOutcome.recovered) {
        _owner = null;
        _cleanupFailed = false;
      }
      return outcome;
    },
  );
}
