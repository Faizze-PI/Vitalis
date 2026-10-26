import 'dart:async';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/runtime_owner_recovery_guard.dart';
import 'package:llm_llamacpp/src/runtime_shutdown_waiter.dart';
import '../services/hardware_sentinel_service.dart';
import 'lifecycle_manager.dart';
import '../models/generation_watchdog_policy.dart';

enum ChatStatus { idle, generating, interrupting, error }

enum ChatFailureCode { generationFailed, cancellationUnacknowledged }

class ChatStateController implements LifecycleManager {
  final HardwareSentinelService _sentinel;
  ChatStatus _status = ChatStatus.idle;
  ChatStatus get status => _status;

  void Function(ChatStatus status)? onStatusChanged;
  void Function(String token)? onToken;
  void Function()? onComplete;
  void Function(String error)? onError;
  void Function(LlamaCppInferenceMetrics metrics)? onMetrics;

  Timer? _noProgressTimer;
  Timer? _maximumDurationTimer;
  StreamSubscription<LLMChunk>? _tokenSub;
  StreamSubscription<bool>? _healthSub;
  final Set<Future<void>> _healthCleanups = {};
  bool _isDisposed = false;
  LlamaCppChatRepository? _activeRepository;
  Future<void>? _cancellationFuture;
  Future<void>? _closeFuture;
  RuntimeShutdownWaiter? _shutdownWaiter;
  RuntimeShutdownWaiter? _nativeRecoveryWaiter;
  RuntimeShutdownWaiter? _healthCloseWaiter;
  String? _cancellationReason;
  int _requestEpoch = 0;
  bool _requiresRecovery = false;
  final RuntimeOwnerRecoveryGuard _ownerRecovery = RuntimeOwnerRecoveryGuard();
  ChatFailureCode? failureCode;

  final GenerationWatchdogPolicy _watchdogPolicy;
  final WatchdogTimerFactory _watchdogTimerFactory;
  final int Function()? _readMonotonicMicros;

  ChatStateController({
    required HardwareSentinelService sentinel,
    GenerationWatchdogPolicy watchdogPolicy =
        GenerationWatchdogPolicy.conservative,
    WatchdogTimerFactory watchdogTimerFactory = Timer.new,
    int Function()? readMonotonicMicros,
    @Deprecated('Inject GenerationWatchdogPolicy instead')
    Duration? timeoutOverride,
  }) : _sentinel = sentinel,
       _watchdogTimerFactory = watchdogTimerFactory,
       _readMonotonicMicros = readMonotonicMicros,
       _watchdogPolicy = timeoutOverride == null
           ? watchdogPolicy
           : GenerationWatchdogPolicy(
               noProgressTimeout: timeoutOverride,
               maximumRequestDuration: timeoutOverride,
             );

  @override
  bool get isDisposed => _isDisposed;

  bool get isIdle => _status == ChatStatus.idle;
  bool get isGenerating => _status == ChatStatus.generating;
  bool get isInterrupting => _status == ChatStatus.interrupting;
  bool get cleanupFailed => _requiresRecovery;
  String? get unsafeReason => _sentinel.unsafeReasonHeavy();

  Future<void> startGeneration({
    required LlamaCppChatRepository repository,
    required List<LLMMessage> messages,
    required GenerationOptions options,
    bool think = false,
  }) async {
    if (_isDisposed) throw StateError('Controller is disposed');
    if (_ownerRecovery.isRecovering) throw InferenceRuntimeBusy();
    if (_cancellationFuture != null) throw InferenceRuntimeBusy();
    if (_requiresRecovery) throw StateError('runtimeRecoveryRequired');
    if (_status == ChatStatus.error) _status = ChatStatus.idle;
    if (_status != ChatStatus.idle) {
      throw StateError('runtimeBusy');
    }

    final epoch = ++_requestEpoch;
    failureCode = null;
    _activeRepository = repository;
    _status = ChatStatus.generating;
    onStatusChanged?.call(_status);
    if (_isDisposed) throw StateError('Controller is disposed');
    if (epoch != _requestEpoch || _status != ChatStatus.generating) return;

    if (!_armNoProgressWatchdog() ||
        _isDisposed ||
        epoch != _requestEpoch ||
        _status != ChatStatus.generating)
      return;
    try {
      final maximumTimer = _watchdogTimerFactory(
        _watchdogPolicy.maximumRequestDuration,
        () {
          if (_isDisposed ||
              epoch != _requestEpoch ||
              _status != ChatStatus.generating)
            return;
          unawaited(
            _emergencyHalt('Generation reached its maximum allowed duration.'),
          );
        },
      );
      if (_isDisposed ||
          epoch != _requestEpoch ||
          _status != ChatStatus.generating) {
        maximumTimer.cancel();
        return;
      }
      _maximumDurationTimer = maximumTimer;
    } catch (_) {
      await _emergencyHalt('Generation monitoring became unavailable.');
      return;
    }

    void safetyUnavailable() {
      if (_isDisposed ||
          epoch != _requestEpoch ||
          _status != ChatStatus.generating)
        return;
      // An ended/failed observation is unknown, never evidence of safety.
      unawaited(_emergencyHalt('Safety telemetry became unavailable.'));
    }

    try {
      _healthSub = _sentinel.onHealthChanged.listen(
        (isSafe) {
          if (_isDisposed ||
              epoch != _requestEpoch ||
              _status != ChatStatus.generating ||
              isSafe)
            return;
          String? reason;
          try {
            reason = _sentinel.unsafeReasonHeavy();
          } catch (_) {
            // Sensor payloads are private; loss of observation still stops
            // the owned request through acknowledged cancellation.
            safetyUnavailable();
            return;
          }
          unawaited(
            _emergencyHalt(
              reason ?? 'System health check failed during generation.',
            ),
          );
        },
        onError: (Object error, StackTrace stack) => safetyUnavailable(),
        onDone: safetyUnavailable,
      );
    } catch (_) {
      // A subscription adapter can fail synchronously. Do not start native
      // generation or release its borrowed owner before cleanup acknowledges.
      await _emergencyHalt('Safety telemetry became unavailable.');
      return;
    }
    if (_isDisposed ||
        epoch != _requestEpoch ||
        _status != ChatStatus.generating)
      return;

    try {
      final stream = repository.streamChatWithGenerationOptions(
        'vitalis',
        messages: messages,
        think: think,
        generationOptions: options,
      );

      final progress = RuntimeProgressTracker();
      _tokenSub = stream.listen(
        (chunk) {
          if (!_isDisposed &&
              epoch == _requestEpoch &&
              _status == ChatStatus.generating) {
            if (chunk is LlamaCppProgressChunk) {
              if (progress.accept(chunk.progress)) _armNoProgressWatchdog();
            } else if (chunk.message?.content case final token?) {
              if (!_armNoProgressWatchdog()) return;
              onToken?.call(token);
            }
          }
        },
        onDone: () {
          if (_isDisposed ||
              epoch != _requestEpoch ||
              _status != ChatStatus.generating)
            return;
          final metrics = repository.lastMetrics;
          _cleanup();
          if (_status == ChatStatus.generating) {
            final completionEpoch = _requestEpoch;
            _status = ChatStatus.idle;
            onStatusChanged?.call(_status);
            if (_isDisposed ||
                completionEpoch != _requestEpoch ||
                _status != ChatStatus.idle)
              return;
            if (metrics != null) onMetrics?.call(metrics);
            if (_isDisposed ||
                completionEpoch != _requestEpoch ||
                _status != ChatStatus.idle)
              return;
            onComplete?.call();
          }
        },
        onError: (error) {
          if (_isDisposed || epoch != _requestEpoch) return;
          unawaited(_emergencyHalt('Generation failed: $error'));
        },
        cancelOnError: false,
      );
    } catch (e) {
      await _emergencyHalt('Failed to start generation: $e');
    }
  }

  Future<void> cancelInference() => _cancelRequest();

  Future<void> _cancelRequest({String? reason, bool recovering = false}) {
    _cancellationReason ??= reason;
    final pending = _cancellationFuture;
    if (pending != null) return pending;
    if (_activeRepository == null) return Future.value();
    final completion = Completer<void>();
    _cancellationFuture = completion.future;
    void release() {
      _cancellationFuture = null;
      _cancellationReason = null;
    }

    unawaited(
      _performCancellation(recovering: recovering).then(
        (_) {
          release();
          completion.complete();
        },
        onError: (Object error, StackTrace stack) {
          release();
          completion.completeError(error, stack);
        },
      ),
    );
    return completion.future;
  }

  Future<void> _performCancellation({required bool recovering}) async {
    final repository = _activeRepository!;
    _status = ChatStatus.interrupting;
    _cleanup(releaseRepository: false, drainTokenStream: true);
    onStatusChanged?.call(_status);
    try {
      final waiter = _shutdownWaiter ??= RuntimeShutdownWaiter(
        timeout: _watchdogPolicy.cancellationAcknowledgementTimeout,
        timerFactory: _watchdogTimerFactory,
        readMonotonicMicros: _readMonotonicMicros,
        onUnconfirmed: () {
          _requiresRecovery = true;
          if (repository.operationSnapshot.hasNativeWork) {
            repository.retainOwnedRecovery();
          }
        },
        shutdown: () async {
          await repository.cancelActiveInference();
          // Keep draining terminal events; expiry never cancels this actor.
          await _tokenSub?.cancel();
          _tokenSub = null;
          await Future.wait<void>(_healthCleanups.toList(), eagerError: false);
        },
      );
      await waiter.wait(retryFailedOperation: recovering);
      if (_nativeRecoveryWaiter != null ||
          (recovering && repository.operationSnapshot.requiresRecovery)) {
        if (!recovering) throw InferenceRecoveryRequired();
        final nativeWaiter = _nativeRecoveryWaiter ??= RuntimeShutdownWaiter(
          timeout: _watchdogPolicy.cancellationAcknowledgementTimeout,
          timerFactory: _watchdogTimerFactory,
          readMonotonicMicros: _readMonotonicMicros,
          shutdown: () async {
            if (await repository.recoverOwnedSession() !=
                RuntimeRecoveryOutcome.recovered)
              throw InferenceRecoveryRequired();
          },
        );
        await nativeWaiter.wait(retryFailedOperation: true);
      }
      final snapshot = repository.operationSnapshot;
      if (snapshot.hasNativeWork || snapshot.requiresRecovery) {
        repository.retainOwnedRecovery();
        throw InferenceRecoveryRequired();
      }
    } catch (_) {
      _requiresRecovery = true;
      failureCode = ChatFailureCode.cancellationUnacknowledged;
      _status = ChatStatus.error;
      onStatusChanged?.call(_status);
      onError?.call(
        'Native cancellation was not acknowledged. Runtime recovery is required.',
      );
      return;
    }
    _activeRepository = null;
    _shutdownWaiter = null;
    _nativeRecoveryWaiter = null;
    _requiresRecovery = false;
    final metrics = repository.lastMetrics;
    if (!_isDisposed && metrics != null) onMetrics?.call(metrics);
    final reason = _cancellationReason;
    failureCode = reason == null ? null : ChatFailureCode.generationFailed;
    _status = reason == null ? ChatStatus.idle : ChatStatus.error;
    onStatusChanged?.call(_status);
    if (reason != null) onError?.call(reason);
  }

  void cancel() {
    if (_status == ChatStatus.idle) return;
    unawaited(cancelInference());
  }

  /// Retry only the request retained by this controller after failed cleanup.
  /// Native context ownership remains with the borrowed repository/service.
  Future<RuntimeRecoveryOutcome> recoverOwnedCleanup() => _ownerRecovery.run(
    recoveryAllowed:
        _requiresRecovery &&
        (_activeRepository != null || _healthCloseWaiter != null) &&
        _cancellationFuture == null,
    recover: () async {
      final originalClose = _closeFuture;
      final retainedRepository = _activeRepository;
      if (retainedRepository == null) {
        try {
          await _healthCloseWaiter!.wait();
        } catch (_) {
          return RuntimeRecoveryOutcome.terminationUnconfirmed;
        }
        if (_healthCleanups.isNotEmpty) {
          return RuntimeRecoveryOutcome.terminationUnconfirmed;
        }
        _requiresRecovery = false;
        _healthCloseWaiter = null;
        if (_isDisposed && identical(_closeFuture, originalClose)) {
          _closeFuture = Future<void>.value();
        }
        return RuntimeRecoveryOutcome.recovered;
      }
      try {
        await _cancelRequest(recovering: true);
      } catch (_) {
        // Consumer callbacks cannot turn an unconfirmed recovery into idle.
        // New work is excluded by the shared recovery guard throughout this.
        _activeRepository = retainedRepository;
        _requiresRecovery = true;
        failureCode = ChatFailureCode.cancellationUnacknowledged;
        _status = ChatStatus.error;
        return RuntimeRecoveryOutcome.terminationUnconfirmed;
      }
      if (_requiresRecovery ||
          _activeRepository != null ||
          _healthCleanups.isNotEmpty) {
        return RuntimeRecoveryOutcome.terminationUnconfirmed;
      }
      if (_isDisposed && identical(_closeFuture, originalClose)) {
        // Existing observers retain the historical failed Future.
        _closeFuture = Future<void>.value();
      }
      return RuntimeRecoveryOutcome.recovered;
    },
  );

  Future<void> _emergencyHalt(String reason) => _cancelRequest(reason: reason);

  void _cleanup({
    bool releaseRepository = true,
    bool drainTokenStream = false,
  }) {
    _requestEpoch++;
    _noProgressTimer?.cancel();
    _noProgressTimer = null;
    _maximumDurationTimer?.cancel();
    _maximumDurationTimer = null;
    final healthCleanup = _healthSub?.cancel();
    _healthSub = null;
    if (healthCleanup != null) {
      _healthCleanups.add(healthCleanup);
      unawaited(
        healthCleanup.then<void>(
          (_) => _healthCleanups.remove(healthCleanup),
          onError: (Object _, StackTrace __) {
            // Retain failed cleanup for close() and block optimistic reuse.
            _requiresRecovery = true;
            failureCode = ChatFailureCode.cancellationUnacknowledged;
          },
        ),
      );
    }
    if (!drainTokenStream) {
      _tokenSub?.cancel();
      _tokenSub = null;
    }
    if (releaseRepository) _activeRepository = null;
  }

  bool _armNoProgressWatchdog() {
    _noProgressTimer?.cancel();
    _noProgressTimer = null;
    final epoch = _requestEpoch;
    try {
      final timer = _watchdogTimerFactory(
        _watchdogPolicy.noProgressTimeout,
        () {
          if (_isDisposed ||
              epoch != _requestEpoch ||
              _status != ChatStatus.generating)
            return;
          unawaited(
            _emergencyHalt(
              'Generation stopped making progress and was cancelled safely.',
            ),
          );
        },
      );
      // Injected schedulers may synchronously expire while constructing a
      // timer. Never attach that late timer to an already-retired request.
      if (_isDisposed ||
          epoch != _requestEpoch ||
          _status != ChatStatus.generating) {
        timer.cancel();
        return false;
      }
      _noProgressTimer = timer;
      return true;
    } catch (_) {
      // Scheduling failure cannot leave an unmonitored request active or
      // expose the chunk that attempted to rearm its watchdog. Keep the owner
      // until the existing cancellation/cleanup operation acknowledges.
      unawaited(_emergencyHalt('Generation monitoring became unavailable.'));
      return false;
    }
  }

  /// Stop this controller's request without retiring the borrowed model owner.
  /// Failed cleanup stays observable; disposal never implies native termination.
  Future<void> close() {
    final pending = _closeFuture;
    if (pending != null) return pending;
    final completion = Completer<void>();
    _closeFuture = completion.future;
    _isDisposed = true;
    onStatusChanged = null;
    onToken = null;
    onComplete = null;
    onError = null;
    onMetrics = null;
    final stopping = _cancelRequest();
    _cleanup(releaseRepository: false, drainTokenStream: true);
    unawaited(() async {
      try {
        await stopping;
        // A pending sensor must not hide an expired owned Stop operation.
        // Its original cleanup remains retained for explicit recovery.
        if (_requiresRecovery) throw InferenceRecoveryRequired();
        if (_healthCleanups.isNotEmpty) {
          _healthCloseWaiter ??= RuntimeShutdownWaiter(
            timeout: _watchdogPolicy.cancellationAcknowledgementTimeout,
            timerFactory: _watchdogTimerFactory,
            readMonotonicMicros: _readMonotonicMicros,
            onUnconfirmed: () => _requiresRecovery = true,
            shutdown: () =>
                Future.wait<void>(_healthCleanups.toList(), eagerError: false),
          );
          await _healthCloseWaiter!.wait();
          _healthCloseWaiter = null;
        }
        if (_requiresRecovery) throw InferenceRecoveryRequired();
        completion.complete();
      } catch (_, stack) {
        _requiresRecovery = true;
        failureCode = ChatFailureCode.cancellationUnacknowledged;
        completion.completeError(InferenceRecoveryRequired(), stack);
      }
    }());
    return completion.future;
  }

  @override
  void dispose() {
    // Keep close() awaitable even for callers constrained to synchronous dispose.
    unawaited(
      close().then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {
          // The failed shared close future remains observable to its owner.
          _requiresRecovery = true;
        },
      ),
    );
  }
}
