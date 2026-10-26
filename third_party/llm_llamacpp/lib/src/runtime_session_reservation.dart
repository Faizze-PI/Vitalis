import 'dart:async';

import 'package:llm_llamacpp/src/exceptions.dart';

enum RuntimeOperationKind {
  interactive,
  warmup,
  tuning,
  verification,
  modelSwitch,
  disposal,
}

enum RuntimeReservationState { idle, reserved, recoveryRequired, recovering }

enum RuntimeRecoveryOutcome { recovered, terminationUnconfirmed }

/// Immutable diagnostics, not an ownership capability. IDs contain no paths
/// and cannot be passed back as native owner objects.
final class RuntimeOperationSnapshot {
  const RuntimeOperationSnapshot({
    required this.state,
    required this.kind,
    required this.ownerId,
    required this.contextOwnerId,
    required this.hasRetainedContext,
    required this.sessionGeneration,
    required this.nativeRequestId,
    required this.cancellationRequested,
    required this.recoveryOutcome,
    required this.initializationPending,
    required this.initializationRecoveryRequired,
    this.cancellationHandleAvailable = false,
    this.cancellationRecoveryRequired = false,
  });
  final RuntimeReservationState state;
  final RuntimeOperationKind? kind;
  final int? ownerId;
  final int? contextOwnerId;
  final bool hasRetainedContext;

  /// Advances on an explicit reservation or newly claimed context. This is
  /// an ownership epoch, not a model-load or token counter.
  final int sessionGeneration;
  final int? nativeRequestId;
  final bool cancellationRequested;
  final bool cancellationHandleAvailable;
  final RuntimeRecoveryOutcome? recoveryOutcome;
  final bool initializationPending;
  final bool initializationRecoveryRequired;
  final bool cancellationRecoveryRequired;

  bool get hasNativeWork => nativeRequestId != null || initializationPending;
  bool get requiresRecovery =>
      initializationRecoveryRequired ||
      cancellationRecoveryRequired ||
      state == RuntimeReservationState.recoveryRequired ||
      state == RuntimeReservationState.recovering;
}

/// Ownership survives a failed cleanup. Only the owner can attempt recovery;
/// completing an unrelated request never clears this quarantine.
class RuntimeSessionReservation {
  Object? _owner;
  RuntimeOperationKind? _kind;
  RuntimeReservationState _state = RuntimeReservationState.idle;
  Future<RuntimeRecoveryOutcome>? _recovery;
  Object? _contextOwner;
  bool _hasContext = false;
  bool _sessionPending = false;
  final _ownerIds = Expando<int>();
  int _nextOwnerId = 0;
  int _sessionGeneration = 0;
  RuntimeRecoveryOutcome? _lastRecoveryOutcome;

  int? _identity(Object? owner) {
    if (owner == null) return null;
    return _ownerIds[owner] ??= ++_nextOwnerId;
  }

  RuntimeOperationSnapshot snapshot({
    int? nativeRequestId,
    Object? activeOwner,
    RuntimeOperationKind? activeKind,
    bool cancellationRequested = false,
    bool cancellationHandleAvailable = false,
    bool initializationPending = false,
    bool initializationRecoveryRequired = false,
    bool cancellationRecoveryRequired = false,
  }) => RuntimeOperationSnapshot(
    state: _state == RuntimeReservationState.idle && activeKind != null
        ? RuntimeReservationState.reserved
        : _state,
    kind: _kind ?? activeKind,
    ownerId: _identity(_owner ?? (activeKind == null ? null : activeOwner)),
    contextOwnerId: _hasContext ? _identity(_contextOwner) : null,
    hasRetainedContext: _hasContext,
    sessionGeneration: _sessionGeneration,
    nativeRequestId: nativeRequestId,
    cancellationRequested: cancellationRequested,
    cancellationHandleAvailable: cancellationHandleAvailable,
    recoveryOutcome: _lastRecoveryOutcome,
    initializationPending: initializationPending,
    initializationRecoveryRequired: initializationRecoveryRequired,
    cancellationRecoveryRequired: cancellationRecoveryRequired,
  );

  bool ownsContext(Object? owner) =>
      _hasContext && identical(_contextOwner, owner);

  void claimContext(Object? owner) {
    if (!canAccess(owner)) throw InferenceRuntimeBusy();
    if (needsRecovery) throw InferenceRecoveryRequired();
    if (!_hasContext) _sessionGeneration++;
    _contextOwner = owner;
    _hasContext = true;
  }

  /// Called only after native unload acknowledgement, never merely on Stop.
  void releaseContext(Object? owner) {
    if (!ownsContext(owner)) throw InferenceRuntimeBusy();
    _contextOwner = null;
    _hasContext = false;
  }

  RuntimeReservationState get state => _state;
  RuntimeOperationKind? get kind => _kind;
  bool get isHeld => _owner != null;
  bool get needsRecovery =>
      _state == RuntimeReservationState.recoveryRequired ||
      _state == RuntimeReservationState.recovering;

  bool canAccess(Object? owner) =>
      (_owner == null || identical(_owner, owner)) &&
      (!_hasContext || identical(_contextOwner, owner));

  /// A failed cleanup may quarantine only its own reservation/context.
  /// Rejection is non-mutating, including another owner's active context.
  bool requireOwnedRecovery(Object owner) {
    if (!canAccess(owner) || (!identical(_owner, owner) && !ownsContext(owner)))
      return false;
    if (needsRecovery) return true;
    _owner = owner;
    _kind ??= RuntimeOperationKind.disposal;
    _state = RuntimeReservationState.recoveryRequired;
    return true;
  }

  void acquire(Object owner, RuntimeOperationKind kind) {
    if (needsRecovery) throw InferenceRecoveryRequired();
    if (isHeld || !canAccess(owner)) throw InferenceRuntimeBusy();
    _owner = owner;
    _sessionGeneration++;
    _sessionPending = true;
    _lastRecoveryOutcome = null;
    _kind = kind;
    _state = RuntimeReservationState.reserved;
  }

  void finish(Object owner, {required bool terminationConfirmed}) {
    if (!identical(_owner, owner)) throw InferenceRuntimeBusy();
    _sessionPending = false;
    if (_state != RuntimeReservationState.reserved) {
      throw InferenceRecoveryRequired();
    }
    if (!terminationConfirmed) {
      _state = RuntimeReservationState.recoveryRequired;
      return;
    }
    _clear();
  }

  Future<RuntimeRecoveryOutcome> recover(
    Object owner,
    Future<bool> Function() confirmCleanup,
  ) {
    if (!identical(_owner, owner)) {
      return Future.error(InferenceRuntimeBusy());
    }
    final running = _recovery;
    if (running != null) return running;
    if (_state != RuntimeReservationState.recoveryRequired) {
      return Future.error(InferenceRuntimeBusy());
    }
    _state = RuntimeReservationState.recovering;
    final completion = Completer<RuntimeRecoveryOutcome>();
    _recovery = completion.future;
    // Install shared ownership before invoking even a synchronously reentrant
    // cleanup adapter. Errors are a typed unconfirmed result, never readiness.
    unawaited(() async {
      try {
        if (await confirmCleanup()) {
          _lastRecoveryOutcome = RuntimeRecoveryOutcome.recovered;
          // Native cleanup can settle while the enclosing action is unwinding.
          // Keep its lease until finish(), excluding every competing owner.
          if (_sessionPending) {
            _state = RuntimeReservationState.reserved;
          } else {
            _clear();
          }
          completion.complete(RuntimeRecoveryOutcome.recovered);
        } else {
          _lastRecoveryOutcome = RuntimeRecoveryOutcome.terminationUnconfirmed;
          _state = RuntimeReservationState.recoveryRequired;
          completion.complete(RuntimeRecoveryOutcome.terminationUnconfirmed);
        }
      } catch (_) {
        // Native failure details belong to the request diagnostics; this layer
        // deliberately returns no exception payload or private model path.
        _state = RuntimeReservationState.recoveryRequired;
        _lastRecoveryOutcome = RuntimeRecoveryOutcome.terminationUnconfirmed;
        completion.complete(RuntimeRecoveryOutcome.terminationUnconfirmed);
      } finally {
        _recovery = null;
      }
    }());
    return completion.future;
  }

  void _clear() {
    _sessionPending = false;
    _owner = null;
    _kind = null;
    _state = RuntimeReservationState.idle;
  }
}
