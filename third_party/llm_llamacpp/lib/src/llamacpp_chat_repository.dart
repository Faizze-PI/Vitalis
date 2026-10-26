import 'dart:async';
import 'dart:ffi' as ffi;

import 'package:llm_core/llm_core.dart'
    show
        LLMChatRepository,
        LLMChatOptions,
        LLMChunk,
        LLMChunkMessage,
        LLMEmbedding,
        LLMLogger,
        DefaultLLMLogger,
        LLMMessage,
        LLMRole,
        LLMTool,
        ModelLoadException,
        StreamChatOptions,
        Validation,
        VisionNotSupportedException;
import 'package:llm_llamacpp/src/backend_initializer.dart';
import 'package:llm_llamacpp/src/native_runtime_bridge.dart';
import 'package:llm_llamacpp/src/loader/loader.dart';
import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';
import 'package:llm_llamacpp/src/error_translator.dart';
import 'package:llm_llamacpp/src/exceptions.dart';
import 'package:llm_llamacpp/src/generation_options.dart';
import 'package:llm_llamacpp/src/inference_output_timing.dart';
import 'package:llm_llamacpp/src/persistent_inference_isolate.dart';
import 'package:llm_llamacpp/src/runtime_session_reservation.dart';
import 'package:llm_llamacpp/src/runtime_owner_recovery_guard.dart';
import 'package:llm_llamacpp/src/isolate_messages.dart';
import 'package:llm_llamacpp/src/runtime_progress.dart';
import 'package:llm_llamacpp/src/runtime_watchdog_policy.dart';
import 'package:llm_llamacpp/src/runtime_shutdown_waiter.dart';
import 'package:llm_llamacpp/src/llamacpp_model.dart';
import 'package:llm_llamacpp/src/lora_adapter.dart';

import 'package:llm_llamacpp/src/tool_call_stream_handler.dart';
import 'package:llm_llamacpp/src/tool_executor.dart';

part 'llamacpp_chat_repository_impl.dart';
part 'llamacpp_chat_repository_deprecated.dart';

/// Repository for chatting with llama.cpp models locally.
///
/// Implements [LLMChatRepository] for local text generation. VITALIS owns
/// model discovery, validation, downloads, and selection outside this package.
class LlamaCppChatRepository extends LLMChatRepository {
  /// Logger instance for this package.
  static final LLMLogger _log = DefaultLLMLogger('llm_llamacpp');

  LlamaCppChatRepository({
    this.shutdownTimeout = RuntimeWatchdogDefaults.noProgressTimeout,
    this.shutdownTimerFactory = Timer.new,
    this.readShutdownMonotonicMicros,
    this.preparationWatchdogPolicy = RuntimeWatchdogPolicy.modelPreparation,
    this.contextSize = 4096,
    this.batchSize = 512,
    this.threads,
    this.promptThreads,
    this.nGpuLayers = 0,
    this.runtimeOperationKind = RuntimeOperationKind.interactive,
    this.supportsThinkingControl = false,
    this.maxToolAttempts = 90,
    String? loraPath,
    double loraScale = 1.0,
  }) : _loraPath = loraPath,
       _loraScale = loraScale,
       _ownsModel = true;

  LlamaCppChatRepository.withModel(
    LlamaCppModel model,
    LlamaBindings bindings, {
    this.shutdownTimeout = RuntimeWatchdogDefaults.noProgressTimeout,
    this.shutdownTimerFactory = Timer.new,
    this.readShutdownMonotonicMicros,
    this.preparationWatchdogPolicy = RuntimeWatchdogPolicy.modelPreparation,
    this.contextSize = 4096,
    this.batchSize = 512,
    this.threads,
    this.promptThreads,
    this.nGpuLayers = 0,
    this.runtimeOperationKind = RuntimeOperationKind.interactive,
    this.supportsThinkingControl = false,
    this.maxToolAttempts = 90,
    String? loraPath,
    double loraScale = 1.0,
  }) : _model = model,
       _bindings = bindings,
       _backendInitialized = true,
       _loraPath = loraPath,
       _loraScale = loraScale,
       _ownsModel = false;

  LlamaCppChatRepository.withModelPath(
    String modelPath, {
    this.shutdownTimeout = RuntimeWatchdogDefaults.noProgressTimeout,
    this.shutdownTimerFactory = Timer.new,
    this.readShutdownMonotonicMicros,
    this.preparationWatchdogPolicy = RuntimeWatchdogPolicy.modelPreparation,
    this.contextSize = 4096,
    this.batchSize = 512,
    this.threads,
    this.promptThreads,
    this.nGpuLayers = 0,
    this.runtimeOperationKind = RuntimeOperationKind.interactive,
    this.supportsThinkingControl = false,
    this.maxToolAttempts = 90,
    String? loraPath,
    double loraScale = 1.0,
  }) : _modelPath = modelPath,
       _loraPath = loraPath,
       _loraScale = loraScale,
       _ownsModel = false;

  /// The context size (number of tokens).
  final int contextSize;
  final RuntimeWatchdogPolicy preparationWatchdogPolicy;

  /// hardcode: HC-007. Bound waiting using the existing inactivity allowance.
  final Duration shutdownTimeout;
  final RuntimeWatchdogTimerFactory shutdownTimerFactory;
  final int Function()? readShutdownMonotonicMicros;

  /// The batch size for processing.
  final int batchSize;

  /// Number of threads to use (null = auto-detect).
  final int? threads;

  /// Prompt-evaluation threads; null preserves the generation-thread default.
  final int? promptThreads;

  /// Number of layers to offload to GPU.
  final int nGpuLayers;

  /// Diagnostic operation class for repository-owned native requests.
  final RuntimeOperationKind runtimeOperationKind;

  /// Whether the selected model has a verified configurable thinking template.
  final bool supportsThinkingControl;

  /// Maximum number of tool calling attempts.
  final int maxToolAttempts;

  /// Whether this repository owns and should dispose the model.
  final bool _ownsModel;

  LlamaBindings? _bindings;
  LlamaCppModel? _model;
  bool _backendInitialized = false;

  /// Model path for lazy loading (model is loaded in inference isolate, not main isolate)
  /// This is used when the repository is created with withModelPath constructor.
  String? _modelPath;

  // LoRA configuration
  String? _loraPath;
  double _loraScale;
  LlamaCppInferenceMetrics? _lastMetrics;
  final Object _runtimeOwner = Object();
  bool _disposed = false;
  Future<void>? _closeFuture;
  RuntimeShutdownWaiter? _closeWaiter;
  RuntimeShutdownWaiter? _closeRecoveryWaiter;
  final _closeRecovery = RuntimeOwnerRecoveryGuard();
  bool get isDisposed => _disposed;
  bool get cleanupFailed => _cleanupFailed;
  bool _cleanupFailed = false;
  NativeRuntimeBridge? _fileOwnershipBridge;
  final Map<String, ffi.Pointer<ffi.Void>> _fileOwnership = {};

  void _retainModelFileOwnership() {
    final path = _model?.path ?? _modelPath;
    if (path == null) return;
    final identity = NativeRuntimeBridge.modelFileIdentity(path);
    if (_fileOwnership.containsKey(identity)) return;
    final runtime = PersistentInferenceIsolate.instance;
    if (!runtime.canAccess(_runtimeOwner)) throw InferenceRuntimeBusy();
    if (runtime.operationSnapshot.requiresRecovery)
      throw InferenceRecoveryRequired();
    final bridge = _fileOwnershipBridge ??= NativeRuntimeBridge(
      loadLlamaLibrary(),
    );
    final lease = bridge.acquireModelRead(modelPath: identity);
    if (lease.address == 0) throw InferenceRuntimeBusy();
    _fileOwnership[identity] = lease;
  }

  void _releaseModelFileOwnership() {
    final bridge = _fileOwnershipBridge;
    for (final lease in _fileOwnership.values) {
      bridge!.releaseModelAccess(lease);
    }
    _fileOwnership.clear();
    _fileOwnershipBridge = null;
  }

  /// Only these canonical targets are excluded; unrelated inference continues.
  static String modelFileIdentity(String path) =>
      NativeRuntimeBridge.modelFileIdentity(path);

  /// All leases are acquired before invoking the asynchronous mutation.
  static Future<T> withModelFilesMutation<T>(
    Iterable<String> paths,
    Future<T> Function() action,
  ) async {
    final identities = paths.map(NativeRuntimeBridge.modelFileIdentity).toSet();
    if (identities.isEmpty) return action();
    final bridge = NativeRuntimeBridge(loadLlamaLibrary());
    final leases = <ffi.Pointer<ffi.Void>>[];
    try {
      for (final path in identities) {
        final lease = bridge.acquireModelMutation(modelPath: path);
        if (lease.address == 0) throw InferenceRuntimeBusy();
        leases.add(lease);
      }
      return await action();
    } finally {
      for (final lease in leases.reversed) {
        bridge.releaseModelAccess(lease);
      }
    }
  }

  void _checkOpen() {
    if (_disposed) throw InferenceRepositoryDisposed();
  }

  /// Reserves the shared runtime for file mutation only when no retained
  /// context or native request owns it. Does not initialize, cancel or unload
  /// another repository. The reservation covers every asynchronous file step.
  static Future<T> withUnloadedRuntime<T>(Future<T> Function() action) async {
    final runtime = PersistentInferenceIsolate.instance;
    if (runtime.operationSnapshot.initializationPending) {
      throw InferenceRuntimeBusy();
    }
    return runtime.withExclusiveSession(Object(), () async {
      final bridge = NativeRuntimeBridge(loadLlamaLibrary());
      final lease = bridge.acquireModelMutation();
      if (lease.address == 0) throw InferenceRuntimeBusy();
      try {
        return await action();
      } finally {
        bridge.releaseModelAccess(lease);
      }
    }, kind: RuntimeOperationKind.disposal);
  }

  Future<T> withExclusiveSession<T>(
    Future<T> Function() action, {
    RuntimeOperationKind kind = RuntimeOperationKind.interactive,
  }) async {
    _checkOpen();
    return PersistentInferenceIsolate.instance.withExclusiveSession(
      _runtimeOwner,
      () async {
        _retainModelFileOwnership();
        try {
          return await action();
        } finally {
          final snapshot = operationSnapshot;
          if (!snapshot.hasRetainedContext && !snapshot.requiresRecovery)
            _releaseModelFileOwnership();
        }
      },
      kind: kind,
    );
  }

  RuntimeReservationState get reservationState =>
      PersistentInferenceIsolate.instance.reservationState;

  RuntimeOperationSnapshot get operationSnapshot =>
      PersistentInferenceIsolate.instance.operationSnapshot;

  Future<RuntimeRecoveryOutcome> recoverOwnedSession() =>
      PersistentInferenceIsolate.instance.recover(_runtimeOwner);

  /// An expired consumer waiter cannot release this repository's native owner.
  void retainOwnedRecovery() {
    if (!PersistentInferenceIsolate.instance.requireOwnedRecovery(
      _runtimeOwner,
    )) {
      throw InferenceRuntimeBusy();
    }
  }

  /// The currently loaded model, if any.
  LlamaCppModel? get model => _model;

  /// Whether a model is currently loaded.
  bool get isModelLoaded => _model != null;

  String? get loraPath => _loraPath;
  double get loraScale => _loraScale;
  bool get hasLora => _loraPath != null;
  LlamaCppInferenceMetrics? get lastMetrics => _lastMetrics;

  /// Account once on the owned native terminal event, even if the text stream
  /// is paused or cancelled. Never restore metrics from an old stream later.
  void _recordTerminalMetrics(Object? message) {
    if (message is InferenceCancelled) {
      _lastMetrics = LlamaCppInferenceMetrics(
        promptTokens: message.promptTokens,
        generatedTokens: message.generatedTokens,
        modelLoadMicros: message.modelLoadMicros,
        contextInitMicros: message.contextInitMicros,
        promptEvalMicros: message.promptEvalMicros,
        generationMicros: message.generationMicros,
        timeToFirstTokenMicros: message.timeToFirstTokenMicros,
        outputTiming: message.outputTiming,
        completionReason: InferenceCompletionReason.cancelled.name,
        configuration: message.configuration,
        cancellationAcknowledgementMicros: message.acknowledgementMicros,
      );
    } else if (message is InferenceComplete) {
      _lastMetrics = LlamaCppInferenceMetrics(
        promptTokens: message.promptTokens,
        generatedTokens: message.generatedTokens,
        modelLoadMicros: message.modelLoadMicros,
        contextInitMicros: message.contextInitMicros,
        promptEvalMicros: message.promptEvalMicros,
        generationMicros: message.generationMicros,
        timeToFirstTokenMicros: message.timeToFirstTokenMicros,
        outputTiming: message.outputTiming,
        completionReason: message.reason.name,
        configuration: message.configuration,
      );
    }
  }

  Future<void> prepare({RuntimeOperationKind? kind}) async {
    _checkOpen();
    final path = _model?.path ?? _modelPath;
    if (path == null) throw StateError('No model path configured');
    _retainModelFileOwnership();
    await PersistentInferenceIsolate.instance.prepare(
      watchdogPolicy: preparationWatchdogPolicy,
      owner: _runtimeOwner,
      modelPath: path,
      contextSize: contextSize,
      batchSize: batchSize,
      nGpuLayers: nGpuLayers,
      threads: threads,
      promptThreads: promptThreads,
      kind: kind ?? runtimeOperationKind,
    );
  }

  Future<void> cancelActiveInference() =>
      PersistentInferenceIsolate.instance.cancel(null, _runtimeOwner);

  Future<void> unloadPersistentModel() async {
    await PersistentInferenceIsolate.instance.unload(
      owner: _runtimeOwner,
      kind: RuntimeOperationKind.modelSwitch,
    );
    _releaseModelFileOwnership();
  }

  Future<int> countChatTokens(
    List<LLMMessage> messages, {
    bool think = false,
  }) async {
    _checkOpen();
    _retainModelFileOwnership();
    final isolateMessages = messages
        .map(
          (message) => IsolateMessage(
            role: message.role.name,
            content: message.content ?? '',
          ),
        )
        .toList();
    return PersistentInferenceIsolate.instance.countChatTokens(
      isolateMessages,
      thinking: supportsThinkingControl ? think : null,
      owner: _runtimeOwner,
      kind: runtimeOperationKind,
    );
  }

  void setLora(String path, {double scale = 1.0}) {
    _loraPath = path;
    _loraScale = scale;
  }

  void setLoraConfig(LoraConfig config) {
    setLora(config.path, scale: config.scale);
  }

  void clearLora() {
    _loraPath = null;
    _loraScale = 1.0;
  }

  void initializeBackend() {
    _checkOpen();
    _initializeBackendImpl(this);
  }

  Future<void> loadModel(
    String modelPath, {
    ModelLoadOptions options = const ModelLoadOptions(),
  }) async {
    _checkOpen();
    await _loadModelImpl(this, modelPath, options: options);
  }

  void unloadModel() {
    _unloadModelImpl(this);
  }

  @override
  Stream<LLMChunk> streamChat(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    LLMChatOptions? options,
  }) async* {
    yield* streamChatWithGenerationOptions(
      model,
      messages: messages,
      think: think,
      tools: tools,
      extra: extra,
      options: options,
      generationOptions: const GenerationOptions(),
    );
  }

  Stream<LLMChunk> streamChatWithGenerationOptions(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    LLMChatOptions? options,
    GenerationOptions? generationOptions,
  }) async* {
    _checkOpen();
    yield* _streamChatImpl(
      this,
      model,
      messages,
      think,
      tools,
      extra,
      options,
      generationOptions,
    );
  }

  /// VITALIS supports text generation, not embedding extraction. Retain the
  /// inherited interface without loading an independent, unowned native model.
  @override
  Future<List<LLMEmbedding>> embed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  }) async {
    _checkOpen();
    throw InferenceCapabilityUnsupported('embeddings');
  }

  @override
  Future<List<LLMEmbedding>> batchEmbed({
    required String model,
    required List<String> messages,
    Map<String, dynamic> options = const {},
  }) async {
    return embed(model: model, messages: messages, options: options);
  }

  Future<void> close() {
    final pending = _closeFuture;
    if (pending != null) return pending;
    _disposed = true;
    PersistentInferenceIsolate.instance.revokeOwner(_runtimeOwner);
    final completion = Completer<void>();
    _closeFuture = completion.future;
    final waiter = RuntimeShutdownWaiter(
      timeout: shutdownTimeout,
      timerFactory: shutdownTimerFactory,
      readMonotonicMicros: readShutdownMonotonicMicros,
      onUnconfirmed: _retainCleanupFailure,
      shutdown: _closeOwnedResources,
    );
    _closeWaiter = waiter;
    unawaited(
      Future<void>.sync(waiter.wait).then<void>(
        (_) => completion.complete(),
        onError: (Object error, StackTrace stack) {
          _retainCleanupFailure();
          completion.completeError(error, stack);
        },
      ),
    );
    return completion.future;
  }

  void _retainCleanupFailure() {
    _cleanupFailed = true;
    PersistentInferenceIsolate.instance.requireOwnedRecovery(_runtimeOwner);
  }

  Future<void> _closeOwnedResources() async {
    final runtime = PersistentInferenceIsolate.instance;
    if (runtime.canAccess(_runtimeOwner)) await cancelActiveInference();
    await runtime.drainOwner(_runtimeOwner);
    // An expired observer does not authorize implicit owner recovery.
    if (_cleanupFailed) throw InferenceRecoveryRequired();
    if (_ownsModel) {
      // ignore: deprecated_member_use_from_same_package
      unloadModel();
      _backendInitialized = false;
    }
    await runtime.releaseOwnedContext(_runtimeOwner);
    if (_cleanupFailed) throw InferenceRecoveryRequired();
    _releaseModelFileOwnership();
    _model = null;
    _modelPath = null;
    _bindings = null;
  }

  /// Retire a failed disposed owner only after native termination/unload.
  /// The original failed close future stays failed for existing observers.
  Future<RuntimeRecoveryOutcome> recoverAfterClose() => _closeRecovery.run(
    recoveryAllowed: _disposed && _cleanupFailed,
    recover: () async {
      final retained = _closeWaiter;
      try {
        await retained?.wait();
      } catch (_) {
        // Never duplicate cancellation while the original shutdown is live.
        if (retained?.hasPendingOperation ?? false) {
          return RuntimeRecoveryOutcome.terminationUnconfirmed;
        }
      }
      final waiter = _closeRecoveryWaiter ??= RuntimeShutdownWaiter(
        timeout: shutdownTimeout,
        timerFactory: shutdownTimerFactory,
        readMonotonicMicros: readShutdownMonotonicMicros,
        onUnconfirmed: _retainCleanupFailure,
        shutdown: _recoverClosedResources,
      );
      await waiter.wait(retryFailedOperation: true);
      _releaseModelFileOwnership();
      _model = null;
      _modelPath = null;
      _bindings = null;
      _cleanupFailed = false;
      _closeWaiter = null;
      _closeRecoveryWaiter = null;
      _closeFuture = Future<void>.value();
      return RuntimeRecoveryOutcome.recovered;
    },
  );

  Future<void> _recoverClosedResources() async {
    final runtime = PersistentInferenceIsolate.instance;
    if (!runtime.requireOwnedRecovery(_runtimeOwner)) {
      throw InferenceRecoveryRequired();
    }
    // Recovery uses the same owner-scoped cancellation operation as Stop
    // and disposal. A failed control path cannot be bypassed by unloading.
    await cancelActiveInference();
    await runtime.drainOwner(_runtimeOwner);
    if (_ownsModel) {
      // Dispose direct-owned resources while the reservation is quarantined.
      // A local cleanup exception must not follow a released native owner.
      // ignore: deprecated_member_use_from_same_package
      unloadModel();
      _backendInitialized = false;
    }
    final result = await runtime.recover(_runtimeOwner);
    if (result != RuntimeRecoveryOutcome.recovered) {
      throw InferenceRecoveryRequired();
    }
  }

  void dispose() {
    // ChangeNotifier-style callers cannot await. Keep the shared failed future
    // observable through close(), and expose failure without private payloads.
    unawaited(
      close().then<void>(
        (_) {},
        onError: (Object _, StackTrace __) {
          _cleanupFailed = true;
        },
      ),
    );
  }
}

class LlamaCppInferenceMetrics {
  const LlamaCppInferenceMetrics({
    required this.promptTokens,
    required this.generatedTokens,
    required this.modelLoadMicros,
    required this.contextInitMicros,
    required this.promptEvalMicros,
    required this.generationMicros,
    required this.timeToFirstTokenMicros,
    required this.completionReason,
    this.outputTiming,
    this.cancellationAcknowledgementMicros,
    this.configuration,
  });

  final int promptTokens;
  final int generatedTokens;
  final int modelLoadMicros;
  final int contextInitMicros;
  final int promptEvalMicros;
  final int generationMicros;

  /// Compatibility alias for helper first emitted text, including model/context
  /// and prompt work. It excludes Dart dispatch and UI rendering.
  final int? timeToFirstTokenMicros;

  /// Native helper emission is not a rendered-frame or display-panel metric.
  final InferenceOutputTiming? outputTiming;
  final String completionReason;
  final int? cancellationAcknowledgementMicros;
  final InferenceRuntimeConfiguration? configuration;

  double get promptTokensPerSecond => promptEvalMicros <= 0
      ? 0
      : promptTokens * Duration.microsecondsPerSecond / promptEvalMicros;

  double get generatedTokensPerSecond => generationMicros <= 0
      ? 0
      : generatedTokens * Duration.microsecondsPerSecond / generationMicros;
}
