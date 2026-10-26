// ARCHITECTURE: GenerationProvider owns the generation lifecycle.
// It coordinates context planning and exposes native token metrics.
// Injection: ChatStateController (FSM), ModelWarmupService (LLM pre-heat).
// Exposes: streamText (buffered tokens), isGenerating, showTruncationWarning.
// Note: Uses direct streaming via llm_llamacpp, no isolate-based architecture.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/runtime_owner_recovery_guard.dart';
import 'package:llm_llamacpp/src/runtime_shutdown_waiter.dart';
import '../models/message.dart';
import '../models/persona.dart';
import '../models/note.dart';
import '../models/model_settings.dart';
import '../models/context_plan_result.dart';
import '../services/chat_state_controller.dart';
import '../services/model_warmup_service.dart';
import '../services/context_planner.dart';
import '../services/startup_access_guard.dart';
import '../services/response_frame_timing.dart';
import '../utils/app_logger.dart';

part 'generation_recovery.dart';

class GenerationProvider extends ChangeNotifier {
  final ChatStateController _controller;
  final ModelWarmupService _warmup;
  final StartupAccessGuard? _startupAccess;
  final StringBuffer _genBuffer = StringBuffer();
  final _ownerRecovery = RuntimeOwnerRecoveryGuard();
  final Duration shutdownTimeout;
  final RuntimeWatchdogTimerFactory shutdownTimerFactory;
  final int Function()? readShutdownMonotonicMicros;
  final int Function()? readOutputMonotonicMicros;
  final _responseClock = Stopwatch()..start();
  late final _responseFrameTiming = ResponseFrameTimingTracker(
    () =>
        readOutputMonotonicMicros?.call() ?? _responseClock.elapsedMicroseconds,
  );
  Future<RuntimeRecoveryOutcome>? _recoveryObservation;
  Future<RuntimeRecoveryOutcome>? _retainedRecoveryActor;
  bool _recoveryObservationFailed = false;

  bool _isSending = false;
  bool _isDisposed = false;
  bool _stopRequested = false;
  bool _recoveryRequired = false;
  Future<void>? _preparationFuture;
  Future<void>? _stopFuture;
  Future<void>? _closeFuture;
  RuntimeShutdownWaiter? _closeWaiter;
  bool _closeObservationFailed = false;
  bool _rawCloseConfirmed = false;
  bool _hasError = false;
  String _errorMessage = '';
  int _lastTokenCount = 0;
  double _lastTps = 0.0;
  LlamaCppInferenceMetrics? _lastMetrics;
  ContextPlanResult? _lastContextResult;
  bool _truncationDismissed = false;
  ModelSettings? _lastSettings;

  void Function(String content)? onGenerationComplete;
  void Function(String error)? onError;

  GenerationProvider({
    required ChatStateController controller,
    required ModelWarmupService warmup,
    StartupAccessGuard? startupAccess,
    this.shutdownTimeout = RuntimeWatchdogDefaults.noProgressTimeout,
    this.shutdownTimerFactory = Timer.new,
    this.readShutdownMonotonicMicros,
    this.readOutputMonotonicMicros,
  }) : _controller = controller,
       _startupAccess = startupAccess,
       _warmup = warmup {
    _controller.onToken = _onToken;
    _controller.onComplete = _onGenerationComplete;
    _controller.onError = _onGenerationError;
    _controller.onMetrics = _onMetrics;
    _controller.onStatusChanged = (_) {
      if (!_isDisposed) notifyListeners();
    };
    _startupAccess?.changes?.addListener(_onStartupAccessChanged);
  }

  bool get isSending => _isSending;
  Object? get responseFrameIdentity => _responseFrameTiming.identity;
  ResponseFrameTiming? get lastResponseFrameTiming =>
      _responseFrameTiming.snapshot;
  void recordResponseFrame(Object identity) {
    if (!_isDisposed) _responseFrameTiming.recordFrame(identity);
  }

  void abandonResponseFrameObservation() => _responseFrameTiming.invalidate();

  bool get requiresRecovery =>
      _recoveryRequired ||
      _recoveryObservationFailed ||
      _closeObservationFailed;
  bool get isRecovering =>
      _ownerRecovery.isRecovering || _recoveryObservation != null;

  Future<RuntimeRecoveryOutcome> recoverOwnedCleanup() {
    final pending = _recoveryObservation;
    if (pending != null) return pending;
    if (!requiresRecovery) return Future.error(InferenceRuntimeBusy());
    final completion = Completer<RuntimeRecoveryOutcome>();
    _recoveryObservation = completion.future;
    var outcome = RuntimeRecoveryOutcome.terminationUnconfirmed;
    final waiter = RuntimeShutdownWaiter(
      timeout: shutdownTimeout,
      timerFactory: shutdownTimerFactory,
      readMonotonicMicros: readShutdownMonotonicMicros,
      onUnconfirmed: () => _recoveryObservationFailed = true,
      shutdown: () async {
        final actor = _retainedRecoveryActor ??= _ownerRecovery.run(
          recoveryAllowed: requiresRecovery,
          recover: () => _recoverGenerationCleanup(this),
        );
        outcome = await actor;
      },
    );
    unawaited(
      Future<void>.sync(waiter.wait).then<void>(
        (_) {
          if (outcome == RuntimeRecoveryOutcome.recovered &&
              !_recoveryRequired) {
            _recoveryObservationFailed = false;
          }
          _retainedRecoveryActor = null;
          _recoveryObservation = null;
          completion.complete(outcome);
        },
        onError: (Object _, StackTrace __) {
          // Keep the actor/result for a later explicit observer. Dropping a
          // timed-out Dart waiter is not proof of native termination.
          _recoveryObservationFailed = true;
          _recoveryObservation = null;
          completion.complete(RuntimeRecoveryOutcome.terminationUnconfirmed);
        },
      ),
    );
    return completion.future;
  }

  bool get hasError => _hasError;
  String get errorMessage => _errorMessage;
  ChatStatus get chatStatus => _controller.status;
  int get lastTokenCount => _lastTokenCount;
  double get lastTps => _lastTps;
  LlamaCppInferenceMetrics? get lastMetrics => _lastMetrics;
  double get lastContextUsage => _lastContextResult?.usageRatio ?? 0.0;
  String get streamText => _isSending ? _genBuffer.toString() : '';

  bool get showTruncationWarning =>
      !_truncationDismissed &&
      _lastContextResult != null &&
      _lastContextResult!.wasTruncated;

  bool get truncationDismissed => _truncationDismissed;

  void dismissTruncationWarning() {
    _truncationDismissed = true;
    notifyListeners();
  }

  void clearError() {
    _hasError = false;
    _errorMessage = '';
    notifyListeners();
  }

  void _checkNewOperation() {
    if (_isDisposed) throw StateError('Generation provider is disposed');
    _startupAccess?.require(StartupAccessOperation.inference);
    if (isRecovering) throw InferenceRuntimeBusy();
    if (requiresRecovery) throw InferenceRecoveryRequired();
    if (_isSending || _preparationFuture != null || _stopFuture != null) {
      throw InferenceRuntimeBusy();
    }
  }

  bool get _canContinue => !_isDisposed && !_stopRequested;

  void _onStartupAccessChanged() {
    if (!_canContinue || (!_isSending && _preparationFuture == null)) return;
    try {
      _startupAccess?.require(StartupAccessOperation.inference);
    } catch (error) {
      AppLogger.instance.warning(
        'Generation readiness revoked (${error.runtimeType})',
      );
      // Stop suppresses output synchronously and retains the existing native
      // owner until cancellation/preparation drain acknowledge.
      unawaited(
        stopSending().then<void>(
          (_) => _publishReadinessStop(false),
          onError: (Object _, StackTrace __) => _publishReadinessStop(true),
        ),
      );
    }
  }

  void _publishReadinessStop(bool unconfirmed) {
    if (_isDisposed) return;
    try {
      _setError(
        unconfirmed
            ? 'Generation could not confirm shutdown. Runtime recovery is required.'
            : 'Generation stopped because app readiness changed. Check Model Library before retrying.',
      );
    } catch (error) {
      // Error state was recorded before notifying the optional observer.
      AppLogger.instance.warning(
        'Readiness stop observer failed (${error.runtimeType})',
      );
    }
  }

  void _notifyIfActive() {
    if (!_isDisposed) notifyListeners();
  }

  Future<void> _trackPreparation(Future<void> Function() action) {
    final completion = Completer<void>();
    _preparationFuture = completion.future;
    unawaited(
      Future<void>.sync(action).then<void>(
        (_) {
          _preparationFuture = null;
          completion.complete();
        },
        onError: (Object error, StackTrace stack) {
          _preparationFuture = null;
          completion.completeError(error, stack);
        },
      ),
    );
    return completion.future;
  }

  Future<void> prepareModel(ModelSettings settings) async {
    _checkNewOperation();
    _stopRequested = false;
    await _trackPreparation(() async {
      await _warmup.cancelTuning();
      if (!_canContinue) return;
      _startupAccess?.require(StartupAccessOperation.inference);
      final profile = await _warmup.resolveProfile(settings);
      if (!_canContinue) return;
      _startupAccess?.require(StartupAccessOperation.inference);
      await _warmup.ensureProfile(profile, modelId: settings.modelId);
    });
  }

  Future<void> startGeneration({
    required List<Message> messages,
    required ModelSettings settings,
    Persona? persona,
    List<Note> attachedNotes = const [],
  }) async {
    _checkNewOperation();
    _stopRequested = false;
    _responseFrameTiming.begin();
    _isSending = true;
    _hasError = false;
    try {
      await _trackPreparation(() {
        notifyListeners();
        return _prepareGeneration(
          messages: messages,
          settings: settings,
          persona: persona,
          attachedNotes: attachedNotes,
        );
      });
    } catch (error) {
      if (_canContinue) {
        _isSending = false;
        _setError(
          'Generation preparation failed (${error.runtimeType}). Please retry.',
        );
      }
    }
  }

  Future<void> _prepareGeneration({
    required List<Message> messages,
    required ModelSettings settings,
    Persona? persona,
    required List<Note> attachedNotes,
  }) async {
    await _warmup.cancelTuning();
    if (!_canContinue) return;
    _startupAccess?.require(StartupAccessOperation.inference);

    final reason = _controller.unsafeReason;
    if (reason != null) {
      _isSending = false;
      _setError(reason);
      return;
    }

    _lastSettings = settings;
    final profile = await _warmup.resolveProfile(settings);
    if (!_canContinue) return;
    _startupAccess?.require(StartupAccessOperation.inference);
    late final LlamaCppChatRepository repo;
    try {
      repo = await _warmup.ensureProfile(profile, modelId: settings.modelId);
    } catch (error) {
      if (!_canContinue) return;
      _setError('Model initialization failed (${error.runtimeType}).');
      _isSending = false;
      notifyListeners();
      return;
    }
    if (!_canContinue) return;

    late final ContextPlanResult ctx;
    _startupAccess?.require(StartupAccessOperation.inference);
    try {
      ctx = await ContextPlanner(LlamaContextTokenCounter(repo)).plan(
        systemPrompt: persona?.systemPrompt ?? settings.systemPrompt,
        attachedNotes: attachedNotes,
        messages: messages,
        profile: profile,
      );
    } catch (error) {
      if (!_canContinue) return;
      _setError(
        error is ContextPlanningError
            ? error.message.toString()
            : 'Context preparation failed (${error.runtimeType}). Please retry.',
      );
      _isSending = false;
      notifyListeners();
      return;
    }
    if (!_canContinue) return;
    _lastContextResult = ctx;
    _startupAccess?.require(StartupAccessOperation.inference);
    _truncationDismissed = false;

    _genBuffer.clear();

    await _controller.startGeneration(
      repository: repo,
      messages: _convertToLLMMessages(ctx),
      options: GenerationOptions(
        temperature: settings.temperature,
        topK: settings.topK,
        topP: settings.topP,
        maxTokens: ctx.reservedOutputTokens,
      ),
      think: settings.thinkingMode == ThinkingMode.on,
    );
  }

  void _onToken(String token) {
    if (!_canContinue) return;
    _onStartupAccessChanged();
    if (!_canContinue) return;
    _genBuffer.write(token);
    if (_genBuffer.toString().trim().isNotEmpty)
      _responseFrameTiming.receivedText();
    notifyListeners();
  }

  void _onMetrics(LlamaCppInferenceMetrics metrics) {
    if (_isDisposed) return;
    _lastMetrics = metrics;
    final requestId = metrics.outputTiming?.requestId;
    if (requestId != null) _responseFrameTiming.bindNativeRequest(requestId);
    _lastTokenCount = metrics.generatedTokens;
    _lastTps = metrics.generatedTokensPerSecond;
  }

  void _onGenerationComplete() {
    if (!_canContinue) return;
    _onStartupAccessChanged();
    if (!_canContinue) return;
    try {
      final finalContent = _genBuffer.toString();

      if (finalContent.isNotEmpty) {
        onGenerationComplete?.call(finalContent);
        final settings = _lastSettings;
        if (_canContinue && settings != null) {
          _warmup.scheduleAutoTune(settings);
        }
      } else {
        _setError('No response generated. Tap to retry.');
      }
    } catch (e) {
      AppLogger.instance.error(
        'Error completing generation (${e.runtimeType})',
      );
      _setError('Generation completed but failed to save. Please retry.');
    } finally {
      _genBuffer.clear();
      _isSending = false;
      if (!_isDisposed) notifyListeners();
    }
  }

  void _onGenerationError(String error) {
    if (!_canContinue) return;
    _genBuffer.clear();
    final unacknowledged =
        _controller.failureCode == ChatFailureCode.cancellationUnacknowledged;
    if (unacknowledged) {
      _recoveryRequired = true;
      _stopRequested = true;
    } else {
      _isSending = false;
    }
    _setError(error);
  }

  Future<void> stopSending() {
    final pending = _stopFuture;
    if (pending != null) return pending;
    if (requiresRecovery) return Future.error(InferenceRecoveryRequired());
    if (_isDisposed || (!_isSending && _preparationFuture == null))
      return Future.value();
    _responseFrameTiming.invalidate();
    _stopRequested = true;
    final completion = Completer<void>();
    _stopFuture = completion.future;
    unawaited(() async {
      try {
        await _controller.cancelInference();
        if (_controller.failureCode ==
            ChatFailureCode.cancellationUnacknowledged) {
          throw InferenceRecoveryRequired();
        }
        await _preparationFuture;
        _isSending = false;
        _hasError = false;
        _genBuffer.clear();
        if (!_isDisposed) notifyListeners();
        _stopFuture = null;
        completion.complete();
      } catch (error, stack) {
        // Retain the failed shutdown operation; new requests remain blocked.
        _recoveryRequired = true;
        if (!_isDisposed) notifyListeners();
        completion.completeError(error, stack);
      }
    }());
    return completion.future;
  }

  Future<void> unloadModel(String modelId) async {
    if (_isDisposed) throw StateError('Generation provider is disposed');
    if (isRecovering) throw InferenceRuntimeBusy();
    if (requiresRecovery) throw InferenceRecoveryRequired();
    if (_isSending || _preparationFuture != null) await stopSending();
    if (_isDisposed) return;
    await _warmup.unloadModel(modelId);
  }

  void _setError(String msg) {
    if (_isDisposed) return;
    _responseFrameTiming.invalidate();
    _hasError = true;
    _errorMessage = msg;
    onError?.call(msg);
    if (!_isDisposed) notifyListeners();
  }

  List<LLMMessage> _convertToLLMMessages(ContextPlanResult ctx) {
    return ctx.context.map((m) {
      final role = switch (m['role']) {
        'system' => LLMRole.system,
        'assistant' => LLMRole.assistant,
        _ => LLMRole.user,
      };
      return LLMMessage(role: role, content: m['content'] ?? '');
    }).toList();
  }

  /// Retire the caller and drain its actors, without disposing borrowed warmup.
  /// A failed cleanup remains a failed shared future, not an idle signal.
  Future<void> close() {
    final pending = _closeFuture;
    if (pending != null) return pending;
    final completion = Completer<void>();
    _closeFuture = completion.future;
    final preparing = _preparationFuture;
    final stopping = _stopFuture;
    dispose();
    final recovering = _ownerRecovery.pending;
    final controllerClose = recovering == null
        ? Future<void>.sync(_controller.close)
        : null;
    final waiter = RuntimeShutdownWaiter(
      timeout: shutdownTimeout,
      timerFactory: shutdownTimerFactory,
      readMonotonicMicros: readShutdownMonotonicMicros,
      onUnconfirmed: () => _closeObservationFailed = true,
      shutdown: () async {
        try {
          if (recovering != null &&
              await recovering != RuntimeRecoveryOutcome.recovered) {
            throw InferenceRecoveryRequired();
          }
          // Observe every captured actor even when one fails. A failed waiter is
          // not permission to forget unfinished preparation or native shutdown.
          await Future.wait<void>([
            controllerClose ?? Future<void>.sync(_controller.close),
            if (recovering == null && preparing != null) preparing,
            if (recovering == null && stopping != null) stopping,
          ], eagerError: false);
          // A failed observation is retained separately. This raw actor has
          // awaited actual recovery and all captured shutdown dependencies.
          if (_recoveryRequired || _controller.cleanupFailed) {
            throw InferenceRecoveryRequired();
          }
          _isSending = false;
          _genBuffer.clear();
          _rawCloseConfirmed = true;
        } catch (_) {
          _recoveryRequired = true;
          throw InferenceRecoveryRequired();
        }
      },
    );
    _closeWaiter = waiter;
    unawaited(
      Future<void>.sync(waiter.wait).then<void>(
        completion.complete,
        onError: (Object _, StackTrace stack) {
          _closeObservationFailed = true;
          completion.completeError(InferenceRecoveryRequired(), stack);
        },
      ),
    );
    return completion.future;
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _responseFrameTiming.invalidate();
    _startupAccess?.changes?.removeListener(_onStartupAccessChanged);
    _stopRequested = true;
    onGenerationComplete = null;
    onError = null;
    _controller.onStatusChanged = null;
    super.dispose();
    unawaited(
      close().then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {
          // Async observers can still inspect the same failed close future.
          if (!_closeObservationFailed) _recoveryRequired = true;
        },
      ),
    );
  }
}
