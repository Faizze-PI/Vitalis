import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/runtime_owner_recovery_guard.dart';
import 'package:llm_llamacpp/src/runtime_shutdown_waiter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import '../utils/app_logger.dart';
import '../constants/app_constants.dart';
import 'hardware_sentinel_service.dart';
import 'lifecycle_manager.dart';
import '../models/runtime_profile.dart';
import '../models/model_settings.dart';
import '../models/runtime_capabilities.dart';
import 'model_registry_service.dart';
import 'runtime_auto_tuner.dart';
import 'runtime_capabilities_provider.dart';
import 'runtime_profile_store.dart';
import 'runtime_benchmark_workload.dart';
import 'backend_self_test.dart';

part 'model_warmup_recovery.dart';

enum RuntimeTuningStatus { idle, scheduled, tuning, ready, cancelled, failed }

enum ModelWarmupOutcome {
  ready,
  busy,
  unavailable,
  unsafe,
  disposed,
  failed,
  recoveryRequired,
}

typedef LlamaRepositoryFactory =
    LlamaCppChatRepository Function({
      required String modelPath,
      required int contextSize,
      required int batchSize,
      required int threads,
      required int promptThreads,
      required int gpuLayers,
      required bool supportsThinking,
      required RuntimeOperationKind runtimeOperationKind,
    });
typedef AppVersionResolver = Future<String> Function();

/// Owns the single persistent native model/context used by interactive chat.
class ModelWarmupService extends ChangeNotifier implements LifecycleManager {
  final HardwareSentinelService _sentinel;
  LlamaCppChatRepository? _repository;
  bool _warmedUp = false;
  bool _warmingUp = false;
  bool _isDisposed = false;
  bool _notifierDisposed = false;
  int? _effectiveContextSize;
  bool _gpuRejected = false;
  String? _activeModelPath;
  final RuntimeCapabilitiesProvider _capabilitiesProvider;
  final RuntimeProfileStore _profileStore;
  final ModelRegistryService _modelRegistry;
  final RuntimeAutoTuner _autoTuner;
  final BackendSelfTest _backendSelfTest;
  final LlamaRepositoryFactory _repositoryFactory;
  final AppVersionResolver _appVersionResolver;
  final int _processorCount;
  final DateTime Function() _clock;
  RuntimeTuningStatus _tuningStatus = RuntimeTuningStatus.idle;
  RuntimeProfile? _effectiveProfile;
  DateTime? _lastTunedAt;
  String? _fallbackReason;
  Future<void>? _tuningFuture;
  TuningCancellationToken? _tuningCancellation;
  LlamaCppChatRepository? _tuningRepository;
  String? _tuningModelId;
  RuntimeBenchmarkWorkload? _tuningWorkload;
  Future<void>? _closeFuture;
  RuntimeShutdownWaiter? _closeWaiter;
  bool _closeObservationFailed = false;
  final Duration shutdownTimeout;
  final RuntimeWatchdogTimerFactory shutdownTimerFactory;
  final int Function()? readShutdownMonotonicMicros;
  Future<void>? _tuningStopFuture;
  RuntimeShutdownWaiter? _tuningStopWaiter;
  bool _tuningStopObservationFailed = false;
  Future<void>? _unloadFuture;
  Future<LlamaCppChatRepository>? _preparationFuture;
  LlamaCppChatRepository? _preparingRepository;
  bool _cleanupFailed = false;
  final _ownerRecovery = RuntimeOwnerRecoveryGuard();
  Future<RuntimeRecoveryOutcome>? _recoveryObservation;
  bool _recoveryObservationFailed = false;

  bool get requiresRecovery => _cleanupFailed || _recoveryObservationFailed;
  bool get isRecovering =>
      _ownerRecovery.isRecovering || _recoveryObservation != null;

  bool get isWarmedUp => _warmedUp;
  bool get isWarmingUp => _warmingUp;
  LlamaCppChatRepository? get repository => _repository;
  int? get effectiveContextSize => _effectiveContextSize;
  RuntimeProfile? get effectiveProfile => _effectiveProfile;
  RuntimeTuningStatus get tuningStatus => _tuningStatus;
  DateTime? get lastTunedAt => _lastTunedAt;
  String? get fallbackReason => _fallbackReason;

  @override
  bool get isDisposed => _isDisposed;

  ModelWarmupService({
    required HardwareSentinelService sentinel,
    RuntimeCapabilitiesProvider? capabilitiesProvider,
    RuntimeProfileStore? profileStore,
    ModelRegistryService? modelRegistry,
    RuntimeAutoTuner autoTuner = const RuntimeAutoTuner(),
    BackendSelfTest backendSelfTest = const BackendSelfTest(),
    LlamaRepositoryFactory? repositoryFactory,
    AppVersionResolver? appVersionResolver,
    int? processorCount,
    DateTime Function()? clock,
    this.shutdownTimeout = RuntimeWatchdogDefaults.noProgressTimeout,
    this.shutdownTimerFactory = Timer.new,
    this.readShutdownMonotonicMicros,
  }) : _sentinel = sentinel,
       _capabilitiesProvider =
           capabilitiesProvider ?? const AndroidRuntimeCapabilitiesProvider(),
       _profileStore = profileStore ?? SharedPreferencesRuntimeProfileStore(),
       _modelRegistry = modelRegistry ?? ModelRegistryService(),
       _autoTuner = autoTuner,
       _backendSelfTest = backendSelfTest,
       _repositoryFactory = repositoryFactory ?? _defaultRepositoryFactory,
       _appVersionResolver = appVersionResolver ?? _defaultAppVersion,
       _processorCount = processorCount ?? Platform.numberOfProcessors,
       _clock = clock ?? DateTime.now;

  static LlamaCppChatRepository _defaultRepositoryFactory({
    required String modelPath,
    required int contextSize,
    required int batchSize,
    required int threads,
    required int promptThreads,
    required int gpuLayers,
    required bool supportsThinking,
    required RuntimeOperationKind runtimeOperationKind,
  }) => LlamaCppChatRepository.withModelPath(
    modelPath,
    contextSize: contextSize,
    batchSize: batchSize,
    threads: threads,
    promptThreads: promptThreads,
    nGpuLayers: gpuLayers,
    runtimeOperationKind: runtimeOperationKind,
    supportsThinkingControl: supportsThinking,
  );

  static Future<String> _defaultAppVersion() async {
    final package = await PackageInfo.fromPlatform();
    return '${package.version}+${package.buildNumber}';
  }

  Future<ModelWarmupOutcome> warmup({String? modelId}) async {
    if (_isDisposed) return ModelWarmupOutcome.disposed;
    if (_warmingUp) return ModelWarmupOutcome.busy;

    if (!_sentinel.isSafeForHeavyOperation()) {
      AppLogger.instance.infoSync(
        'Warmup skipped — device not safe for heavy operation',
      );
      return ModelWarmupOutcome.unsafe;
    }

    _warmingUp = true;

    try {
      final installed = (await _modelRegistry.listModels())
          .where((model) => model.isInstalled)
          .toList();
      final candidates = modelId == null
          ? installed
          : installed.where((model) => model.id == modelId).toList();
      if (candidates.isEmpty) {
        AppLogger.instance.infoSync('Warmup skipped — no model path set');
        return ModelWarmupOutcome.unavailable;
      }
      final selected = candidates.first;
      if (_warmedUp &&
          _repository != null &&
          !_repository!.isDisposed &&
          selected.localPath == _activeModelPath) {
        return ModelWarmupOutcome.ready;
      }
      final settings = ModelSettings(modelId: selected.id);
      final profile = await resolveProfile(settings);
      await ensureProfile(profile, modelId: selected.id);
      AppLogger.instance.infoSync(
        'Model initialization complete (context=$_effectiveContextSize)',
      );
      return ModelWarmupOutcome.ready;
    } catch (error) {
      AppLogger.instance.errorSync(
        'Model warmup failed (${error.runtimeType})',
      );
      // The failing owner retains its context. Shutdown/recovery must prove
      // termination; a failed warmup is not permission to drop references.
      if (_cleanupFailed || error is InferenceRecoveryRequired) {
        return ModelWarmupOutcome.recoveryRequired;
      }
      if (_isDisposed) return ModelWarmupOutcome.disposed;
      if (error is InferenceRuntimeBusy) return ModelWarmupOutcome.busy;
      return ModelWarmupOutcome.failed;
    } finally {
      _warmingUp = false;
    }
  }

  @override
  void dispose() {
    if (!_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
    unawaited(close());
  }

  /// Reject work immediately, but retain owned resources until native cleanup
  /// acknowledges. All callers observe the same success or failure.
  Future<void> close() {
    final pending = _closeFuture;
    if (pending != null) return pending;
    final completion = Completer<void>();
    _closeFuture = completion.future;
    _closeObservationFailed = false;
    _isDisposed = true;
    _warmingUp = false;
    _warmedUp = false;
    _tuningCancellation?.cancel();
    if (!_notifierDisposed) {
      _notifierDisposed = true;
      super.dispose();
    }
    // Synchronous Provider disposal cannot await. Observe errors here while
    // keeping the original failed future available to awaitable callers.
    unawaited(
      completion.future.then<void>(
        (_) {},
        onError: (Object error, StackTrace _) {
          AppLogger.instance.warning(
            'Model service cleanup unconfirmed (${error.runtimeType})',
          );
        },
      ),
    );
    final recovery = _ownerRecovery.pending;
    final waiter = RuntimeShutdownWaiter(
      timeout: shutdownTimeout,
      timerFactory: shutdownTimerFactory,
      readMonotonicMicros: readShutdownMonotonicMicros,
      onUnconfirmed: _retainUnconfirmedClose,
      shutdown: () => recovery == null
          ? _finishClose()
          : _finishCloseAfterRecovery(recovery),
    );
    _closeWaiter = waiter;
    unawaited(
      Future<void>.sync(waiter.wait).then<void>(
        completion.complete,
        onError: (Object error, StackTrace stack) {
          _retainUnconfirmedClose();
          completion.completeError(error, stack);
        },
      ),
    );
    return completion.future;
  }

  void _retainUnconfirmedClose() {
    _closeObservationFailed = true;
    _cleanupFailed = true;
  }

  Future<void> _finishCloseAfterRecovery(
    Future<RuntimeRecoveryOutcome> recovery,
  ) async {
    if (await recovery != RuntimeRecoveryOutcome.recovered) {
      throw InferenceRecoveryRequired();
    }
    await _finishClose();
  }

  /// Retire this service's retained owners, without activating a model or
  /// reviving a disposed service. Failed actors remain historical failures.
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
        // The recovery guard retains the raw actor across observation expiry;
        // another observer joins it rather than issuing duplicate native work.
        outcome = await _recoverOwnedCleanupActor();
      },
    );
    unawaited(
      Future<void>.sync(waiter.wait).then<void>(
        (_) {
          if (outcome == RuntimeRecoveryOutcome.recovered && !_cleanupFailed) {
            _recoveryObservationFailed = false;
          }
          _recoveryObservation = null;
          completion.complete(outcome);
        },
        onError: (Object _, StackTrace __) {
          _recoveryObservationFailed = true;
          _recoveryObservation = null;
          completion.complete(RuntimeRecoveryOutcome.terminationUnconfirmed);
        },
      ),
    );
    return completion.future;
  }

  Future<RuntimeRecoveryOutcome> _recoverOwnedCleanupActor() =>
      _ownerRecovery.run(
        recoveryAllowed: requiresRecovery,
        recover: () async {
          final originalClose = _closeFuture;
          final originalTuningStop = _tuningStopFuture;
          final retainedActors = [_closeWaiter, _tuningStopWaiter];
          for (final retained
              in retainedActors.whereType<RuntimeShutdownWaiter>()) {
            try {
              await retained.wait();
            } catch (_) {
              if (retained.hasPendingOperation) {
                return RuntimeRecoveryOutcome.terminationUnconfirmed;
              }
            }
          }
          return _recoverModelServiceCleanup(
            this,
            originalClose: originalClose,
            originalTuningStop: originalTuningStop,
          );
        },
      );

  Future<void> _finishClose() async {
    final unloading = _unloadFuture;
    if (unloading != null) await unloading;
    await cancelTuning();
    final preparation = _preparationFuture;
    if (preparation != null) {
      try {
        await preparation;
      } catch (_) {
        // Preparation may fail normally or reject a late disposed result.
        // Native cleanup failures are separately retained below.
        if (_cleanupFailed) throw InferenceRecoveryRequired();
      }
    }
    if (_cleanupFailed) throw InferenceRecoveryRequired();
    final preparing = _preparingRepository;
    if (preparing != null) await _closeRepository(preparing);
    final repository = _repository;
    if (repository != null) await _closeRepository(repository);
    if (_cleanupFailed) throw InferenceRecoveryRequired();
    _repository = null;
    _activeModelPath = null;
    _effectiveContextSize = null;
    _effectiveProfile = null;
  }

  Future<void> _closeRepository(LlamaCppChatRepository repository) async {
    try {
      await repository.close();
      if (identical(_preparingRepository, repository)) {
        _preparingRepository = null;
      }
    } catch (_) {
      _cleanupFailed = true;
      rethrow;
    }
  }

  void _checkAvailable() {
    if (_isDisposed) throw StateError('Model service is disposed');
    if (requiresRecovery) throw InferenceRecoveryRequired();
  }

  void _notifyIfActive() {
    if (!_isDisposed) notifyListeners();
  }

  Future<RuntimeProfile> resolveProfile(ModelSettings settings) async {
    _checkAvailable();
    final capabilities = await _capabilitiesProvider.snapshot();
    _checkAvailable();
    final descriptor = await _modelRegistry.findById(settings.modelId);
    _checkAvailable();
    final base = RuntimeProfile.forSettings(
      settings,
      processorCount: _processorCount,
      maximumContextSize:
          descriptor?.contextTrain ?? AppConstants.nativeMaximumContextSize,
    );
    if (settings.tuningMode == TuningMode.advanced) {
      _effectiveProfile = base;
      return base;
    }
    final key = await _profileKey(settings, capabilities);
    if (settings.accelerationPreference ==
            AccelerationPreference.experimentalGpu &&
        capabilities.supportsBackend('vulkan')) {
      final gpuKey = await _profileKey(
        settings,
        capabilities,
        backend: 'vulkan',
      );
      final gpu = await _profileStore.read(gpuKey);
      _checkAvailable();
      if (gpu != null && gpu.profile.gpuLayers > 0) {
        _effectiveProfile = gpu.profile.copyWith(
          reservedOutputTokens: settings.maxTokens,
          thinkingMode: settings.thinkingMode,
        );
        _lastTunedAt = gpu.tunedAt;
        _fallbackReason = gpu.fallbackReason;
        _tuningStatus = RuntimeTuningStatus.ready;
        _notifyIfActive();
        return _effectiveProfile!;
      }
    }
    final cached = await _profileStore.read(key);
    _checkAvailable();
    if (cached != null) {
      _effectiveProfile = cached.profile.copyWith(
        reservedOutputTokens: settings.maxTokens,
        thinkingMode: settings.thinkingMode,
      );
      _lastTunedAt = cached.tunedAt;
      _fallbackReason = cached.fallbackReason;
      _tuningStatus = RuntimeTuningStatus.ready;
      _notifyIfActive();
      return _effectiveProfile!;
    }
    final conservative = _conservativeProfile(
      base,
      capabilities,
      modelContext: descriptor?.contextTrain,
    );
    _effectiveProfile = conservative;
    _fallbackReason = capabilities.hasKnownSafeTelemetry
        ? 'Automatic benchmark pending'
        : 'Important device telemetry is unavailable';
    _tuningStatus = RuntimeTuningStatus.scheduled;
    _notifyIfActive();
    return conservative;
  }

  Future<void> cancelTuning() {
    final pending = _tuningStopFuture;
    if (pending != null) return pending;
    final completion = Completer<void>();
    _tuningStopFuture = completion.future;
    _tuningStopObservationFailed = false;
    _tuningCancellation?.cancel();
    final waiter = RuntimeShutdownWaiter(
      timeout: shutdownTimeout,
      timerFactory: shutdownTimerFactory,
      readMonotonicMicros: readShutdownMonotonicMicros,
      onUnconfirmed: _retainUnconfirmedTuningStop,
      shutdown: () async {
        await _tuningRepository?.cancelActiveInference();
        await _tuningFuture;
        if (_cleanupFailed) throw InferenceRecoveryRequired();
      },
    );
    _tuningStopWaiter = waiter;
    unawaited(
      Future<void>.sync(waiter.wait).then<void>(
        completion.complete,
        onError: (Object error, StackTrace stack) {
          _retainUnconfirmedTuningStop();
          completion.completeError(error, stack);
        },
      ),
    );
    return completion.future;
  }

  void _retainUnconfirmedTuningStop() {
    _tuningStopObservationFailed = true;
    _cleanupFailed = true;
  }

  Future<void> unloadModel(String modelId) {
    try {
      _checkAvailable();
      if (_preparationFuture != null || _unloadFuture != null) {
        throw InferenceRuntimeBusy();
      }
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    final completion = Completer<void>();
    _unloadFuture = completion.future;
    unawaited(
      _unloadModel(modelId).then<void>(
        (_) {
          _unloadFuture = null;
          completion.complete();
        },
        onError: (Object error, StackTrace stack) {
          _unloadFuture = null;
          completion.completeError(error, stack);
        },
      ),
    );
    return completion.future;
  }

  Future<void> _unloadModel(String modelId) async {
    await cancelTuning();
    final descriptor = await _modelRegistry.findById(modelId);
    if (descriptor?.localPath == null ||
        descriptor!.localPath != _activeModelPath) {
      return;
    }
    final repository = _repository;
    if (repository != null) await _closeRepository(repository);
    _repository = null;
    _activeModelPath = null;
    _effectiveContextSize = null;
    _warmedUp = false;
    _notifyIfActive();
  }

  void scheduleAutoTune(ModelSettings settings) {
    if (settings.tuningMode != TuningMode.automatic ||
        _tuningFuture != null ||
        _preparationFuture != null ||
        _unloadFuture != null ||
        requiresRecovery ||
        _isDisposed) {
      return;
    }
    // Establish stop intent before the first asynchronous discovery/preparation.
    final cancellation = TuningCancellationToken();
    _tuningStopFuture = null;
    _tuningStopWaiter = null;
    _tuningStopObservationFailed = false;
    _tuningCancellation = cancellation;
    _tuningWorkload = null;
    final operation = _performAutoTune(settings, cancellation);
    _tuningFuture = operation;
    unawaited(
      operation.then<void>(
        (_) {
          _tuningFuture = null;
          _tuningCancellation = null;
        },
        onError: (Object _, StackTrace __) {
          // Keep the failed owned operation observable by shutdown callers.
          _cleanupFailed = true;
          _tuningStatus = RuntimeTuningStatus.failed;
          _notifyIfActive();
        },
      ),
    );
  }

  Future<void> resetAutoProfile(ModelSettings settings) async {
    _checkAvailable();
    final capabilities = await _capabilitiesProvider.snapshot();
    await _profileStore.invalidate(await _profileKey(settings, capabilities));
    _lastTunedAt = null;
    _fallbackReason = 'Automatic benchmark pending';
    _tuningStatus = RuntimeTuningStatus.scheduled;
    _notifyIfActive();
  }

  Future<LlamaCppChatRepository> ensureProfile(
    RuntimeProfile profile, {
    required String modelId,
  }) {
    try {
      _checkAvailable();
      if (_preparationFuture != null ||
          _tuningFuture != null ||
          _unloadFuture != null) {
        throw InferenceRuntimeBusy();
      }
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    final completion = Completer<LlamaCppChatRepository>();
    _preparationFuture = completion.future;
    unawaited(
      _ensureProfile(profile, modelId: modelId).then<void>(
        (repository) {
          _preparationFuture = null;
          completion.complete(repository);
        },
        onError: (Object error, StackTrace stack) {
          _preparationFuture = null;
          completion.completeError(error, stack);
        },
      ),
    );
    return completion.future;
  }

  Future<LlamaCppChatRepository> _ensureProfile(
    RuntimeProfile profile, {
    required String modelId,
  }) async {
    final model = await _modelRegistry.requireInstalled(modelId);
    _checkAvailable();
    final modelPath = model.localPath!;
    final current = _repository;
    final effectiveGpuLayers = _gpuRejected ? 0 : profile.gpuLayers;
    if (current != null &&
        !current.isDisposed &&
        _activeModelPath == modelPath &&
        current.contextSize == profile.contextSize &&
        current.batchSize == profile.batchSize &&
        current.threads == profile.generationThreads &&
        (current.promptThreads ?? current.threads) == profile.promptThreads &&
        current.nGpuLayers == effectiveGpuLayers) {
      // Owner recovery can unload a context without retiring its repository.
      // Native preparation reuses an already loaded compatible context.
      await current.prepare(kind: RuntimeOperationKind.warmup);
      _checkAvailable();
      return current;
    }
    final supportsThinking = await _supportsThinkingControl(modelPath);
    _checkAvailable();
    // A replacement must not load into another repository's retained context.
    // Keep the previous reference until its native unload acknowledges.
    if (current != null) await _closeRepository(current);
    _checkAvailable();
    _repository = null;
    _activeModelPath = null;
    _warmedUp = false;
    late LlamaCppChatRepository candidate;
    late int allocatedContext;
    try {
      final prepared = await _prepareWithContextProbe(
        modelPath: modelPath,
        requestedContext: profile.contextSize,
        modelContext: model.contextTrain,
        batchSize: profile.batchSize,
        threads: profile.generationThreads,
        promptThreads: profile.promptThreads,
        gpuLayers: effectiveGpuLayers,
        supportsThinking: supportsThinking,
      );
      candidate = prepared.repository;
      allocatedContext = prepared.contextSize;
    } catch (error) {
      _checkAvailable();
      if (error is InferenceRuntimeBusy || error is InferenceRecoveryRequired) {
        rethrow;
      }
      if (effectiveGpuLayers == 0) rethrow;
      _gpuRejected = true;
      final prepared = await _prepareWithContextProbe(
        modelPath: modelPath,
        requestedContext: profile.contextSize,
        modelContext: model.contextTrain,
        batchSize: profile.batchSize,
        threads: profile.generationThreads,
        promptThreads: profile.promptThreads,
        gpuLayers: 0,
        supportsThinking: supportsThinking,
      );
      final fallback = prepared.repository;
      if (_isDisposed) {
        await _closeRepository(fallback);
        throw StateError('Model service is disposed');
      }
      _repository = fallback;
      _preparingRepository = null;
      _activeModelPath = modelPath;
      _effectiveContextSize = prepared.contextSize;
      _effectiveProfile = profile.copyWith(
        contextSize: prepared.contextSize,
        gpuLayers: 0,
      );
      _warmedUp = true;
      AppLogger.instance.warningFailure(
        'Experimental GPU initialization failed; using CPU',
        error,
      );
      return fallback;
    }
    if (_isDisposed) {
      await _closeRepository(candidate);
      throw StateError('Model service is disposed');
    }
    _repository = candidate;
    _preparingRepository = null;
    _activeModelPath = modelPath;
    _effectiveContextSize = allocatedContext;
    _effectiveProfile = profile.copyWith(contextSize: allocatedContext);
    _warmedUp = true;
    return candidate;
  }

  Future<bool> _supportsThinkingControl(String modelPath) async =>
      VerifiedThinkingTemplates.supports(
        (await _modelRegistry.findByPath(modelPath))?.chatTemplate,
      );

  RuntimeProfile _conservativeProfile(
    RuntimeProfile base,
    RuntimeCapabilities capabilities, {
    int? modelContext,
  }) {
    final modelMaximum = modelContext ?? base.contextSize;
    final memory = capabilities.availableMemoryBytes;
    final safeContext = memory == null
        ? AppConstants.conservativeUnknownContextSize
        : ((memory * AppConstants.contextMemoryBudgetFraction) ~/
                  AppConstants.conservativeKvBytesPerToken)
              .clamp(AppConstants.minimumContextSize, modelMaximum);
    final threads = capabilities.hasKnownSafeTelemetry
        ? capabilities.performanceProcessors!.clamp(
            1,
            capabilities.logicalProcessors,
          )
        : 1;
    return base.copyWith(
      contextSize: base.contextSize.clamp(
        AppConstants.minimumContextSize,
        safeContext,
      ),
      generationThreads: threads,
      promptThreads: threads,
      batchSize: 128,
      gpuLayers: 0,
    );
  }

  Future<({LlamaCppChatRepository repository, int contextSize})>
  _prepareWithContextProbe({
    required String modelPath,
    required int requestedContext,
    required int? modelContext,
    required int batchSize,
    required int threads,
    required int promptThreads,
    required int gpuLayers,
    required bool supportsThinking,
  }) async {
    final upper = requestedContext.clamp(
      AppConstants.minimumContextSize,
      modelContext ?? requestedContext,
    );
    final candidates = <int>[];
    var context = upper;
    while (true) {
      candidates.add(context);
      if (context <= AppConstants.minimumContextSize) break;
      context = (context ~/ 2).clamp(AppConstants.minimumContextSize, upper);
    }
    Object? lastError;
    for (final contextSize in candidates) {
      _checkAvailable();
      final repository = _repositoryFactory(
        modelPath: modelPath,
        contextSize: contextSize,
        batchSize: batchSize,
        threads: threads,
        promptThreads: promptThreads,
        gpuLayers: gpuLayers,
        supportsThinking: supportsThinking,
        runtimeOperationKind: RuntimeOperationKind.interactive,
      );
      _preparingRepository = repository;
      try {
        await repository.prepare(kind: RuntimeOperationKind.warmup);
        return (repository: repository, contextSize: contextSize);
      } catch (error) {
        lastError = error;
        await _closeRepository(repository);
        if (error is InferenceRuntimeBusy ||
            error is InferenceRecoveryRequired) {
          rethrow;
        }
      }
    }
    throw StateError(
      'No safe context allocation succeeded: ${lastError.runtimeType}',
    );
  }

  Future<RuntimeProfileKey> _profileKey(
    ModelSettings settings,
    RuntimeCapabilities capabilities, {
    String backend = 'cpu',
  }) async {
    final appVersion = await _appVersionResolver();
    final descriptor = await _modelRegistry.findById(settings.modelId);
    return RuntimeProfileKey(
      appVersion: appVersion,
      modelSha256: descriptor?.sha256 ?? 'unknown',
      deviceFingerprint: capabilities.deviceFingerprint,
      backendVersion: 'llama.cpp-b10727-ab0b3bd3',
      backend: backend,
      templateFingerprint: descriptor?.chatTemplate == null
          ? 'unknown'
          : sha256.convert(utf8.encode(descriptor!.chatTemplate!)).toString(),
    );
  }

  Future<void> _performAutoTune(
    ModelSettings settings,
    TuningCancellationToken cancellation,
  ) async {
    StreamSubscription<bool>? safety;
    var terminating = false;
    void stopForSafety({bool telemetryFailed = false}) {
      if (terminating || !identical(_tuningCancellation, cancellation)) return;
      _fallbackReason = telemetryFailed
          ? 'Automatic tuning stopped: safety telemetry unavailable'
          : 'Automatic tuning stopped by device safety';
      cancellation.cancel();
      // Uses the same acknowledged owner-scoped shutdown as user Stop.
      // Never await the operation from its own safety callback/finalizer.
      unawaited(
        cancelTuning().then<void>(
          (_) {},
          onError: (Object error, StackTrace _) {
            AppLogger.instance.warning(
              'Tuning safety shutdown unconfirmed (${error.runtimeType})',
            );
          },
        ),
      );
    }

    try {
      if (!_sentinel.isSafeForHeavyOperation()) return;
      safety = _sentinel.onHealthChanged.listen(
        (safe) {
          if (!safe) stopForSafety();
        },
        onError: (Object _, StackTrace __) =>
            stopForSafety(telemetryFailed: true),
        onDone: () => stopForSafety(telemetryFailed: true),
      );
      final capabilities = await _capabilitiesProvider.snapshot();
      _checkTuningSafety(cancellation);
      if (capabilities.isSevere) return;
      // Tuning owns the only native model context while it runs. This avoids
      // doubling mobile memory by retaining the interactive context alongside a
      // benchmark context. A user request cancels tuning and reloads this context.
      final interactive = _repository;
      if (interactive != null) await _closeRepository(interactive);
      _repository = null;
      _activeModelPath = null;
      _effectiveContextSize = null;
      _warmedUp = false;
      cancellation.throwIfCancelled();
      final descriptor = await _modelRegistry.findById(settings.modelId);
      cancellation.throwIfCancelled();
      final conservative = _conservativeProfile(
        RuntimeProfile.forSettings(
          settings,
          processorCount: _processorCount,
          maximumContextSize:
              descriptor?.contextTrain ?? AppConstants.nativeMaximumContextSize,
        ),
        capabilities,
        modelContext: descriptor?.contextTrain,
      );
      _tuningModelId = settings.modelId;
      _tuningStatus = RuntimeTuningStatus.tuning;
      _notifyIfActive();
      final winner = await _autoTuner.tune(
        conservative: conservative,
        capabilities: capabilities,
        cancellation: cancellation,
        benchmark: _benchmark,
      );
      final key = await _profileKey(settings, capabilities);
      cancellation.throwIfCancelled();
      final committed = await _profileStore.writeIfCurrent(
        key,
        winner.profile,
        isCurrent: () =>
            !cancellation.isCancelled &&
            !_isDisposed &&
            _sentinel.isSafeForHeavyOperation(),
      );
      if (!committed) {
        _checkTuningSafety(cancellation);
        throw const RuntimeProfilePersistenceFailure();
      }
      _effectiveProfile = winner.profile;
      _lastTunedAt = _clock().toUtc();
      _fallbackReason = null;
      _tuningStatus = RuntimeTuningStatus.ready;
      _notifyIfActive();
      await _runRequestedBackendSelfTest(
        settings,
        capabilities,
        winner.profile,
        cancellation,
      );
    } on TuningCancelled {
      _tuningStatus = RuntimeTuningStatus.cancelled;
      _notifyIfActive();
    } catch (error) {
      if (_cleanupFailed) rethrow;
      if (cancellation.isCancelled) {
        _tuningStatus = RuntimeTuningStatus.cancelled;
        _notifyIfActive();
        return;
      }
      _fallbackReason = 'Automatic tuning failed (${error.runtimeType})';
      _tuningStatus = RuntimeTuningStatus.failed;
      _notifyIfActive();
    } finally {
      terminating = true;
      try {
        await safety?.cancel();
      } finally {
        final tuning = _tuningRepository;
        if (tuning != null) await _closeRepository(tuning);
        if (_cleanupFailed) throw InferenceRecoveryRequired();
        _tuningRepository = null;
        _tuningModelId = null;
        _tuningWorkload = null;
      }
    }
  }

  void _checkTuningSafety(TuningCancellationToken cancellation) {
    cancellation.throwIfCancelled();
    if (!_sentinel.isSafeForHeavyOperation()) {
      cancellation.cancel();
      _fallbackReason = 'Automatic tuning stopped by device safety';
      throw const TuningCancelled();
    }
  }

  Future<void> _runRequestedBackendSelfTest(
    ModelSettings settings,
    RuntimeCapabilities capabilities,
    RuntimeProfile cpuProfile,
    TuningCancellationToken cancellation,
  ) async {
    if (settings.accelerationPreference !=
            AccelerationPreference.experimentalGpu ||
        !capabilities.supportsBackend('vulkan')) {
      return;
    }
    final descriptor = await _modelRegistry.findById(settings.modelId);
    final gpuKey = await _profileKey(settings, capabilities, backend: 'vulkan');
    cancellation.throwIfCancelled();
    final result = await _backendSelfTest.run(
      backend: 'vulkan',
      cpuProfile: cpuProfile,
      modelLayerCount: descriptor?.blockCount ?? 32,
      probe: _benchmark,
      cancellation: cancellation,
    );
    cancellation.throwIfCancelled();
    if (result.passed) {
      final profile = cpuProfile.copyWith(gpuLayers: result.offloadedLayers);
      await _profileStore.write(gpuKey, profile);
      _effectiveProfile = profile;
      return;
    }
    await _profileStore.write(
      gpuKey,
      cpuProfile.copyWith(gpuLayers: 0),
      fallbackReason: result.failureReason,
    );
    _gpuRejected = true;
    _fallbackReason = result.failureReason;
  }

  Future<RuntimeBenchmarkResult> _benchmark(
    RuntimeProfile profile,
    TuningCancellationToken cancellation,
  ) async {
    _checkTuningSafety(cancellation);
    final modelId = _tuningModelId;
    if (modelId == null) throw StateError('No tuning model selected');
    final path = (await _modelRegistry.requireInstalled(modelId)).localPath!;
    _checkTuningSafety(cancellation);
    final supportsThinking = await _supportsThinkingControl(path);
    _checkTuningSafety(cancellation);
    final repository = _repositoryFactory(
      modelPath: path,
      contextSize: profile.contextSize,
      batchSize: profile.batchSize,
      threads: profile.generationThreads,
      promptThreads: profile.promptThreads,
      gpuLayers: profile.gpuLayers,
      supportsThinking: supportsThinking,
      runtimeOperationKind: RuntimeOperationKind.tuning,
    );
    _tuningRepository = repository;
    try {
      await repository.prepare();
      _checkTuningSafety(cancellation);
      final think = profile.thinkingMode == ThinkingMode.on;
      Future<int> count(String prompt) => repository.countChatTokens([
        LLMMessage(role: LLMRole.user, content: prompt),
      ], think: think);
      final workload = _tuningWorkload ??=
          await RuntimeBenchmarkWorkload.create(
            countPromptTokens: count,
            checkCurrent: () => _checkTuningSafety(cancellation),
            contextSize: profile.contextSize,
          );
      if (await count(workload.prompt) != RuntimeBenchmarkPolicy.promptTokens) {
        throw const RuntimeBenchmarkWorkloadUnavailable();
      }
      _checkTuningSafety(cancellation);
      await for (final _ in repository.streamChatWithGenerationOptions(
        'runtime-tuning',
        messages: [LLMMessage(role: LLMRole.user, content: workload.prompt)],
        think: think,
        generationOptions: const GenerationOptions(
          maxTokens: RuntimeBenchmarkPolicy.outputTokens,
        ),
      )) {
        if (!_sentinel.isSafeForHeavyOperation()) cancellation.cancel();
        if (cancellation.isCancelled) {
          await repository.cancelActiveInference();
          throw const TuningCancelled();
        }
      }
      cancellation.throwIfCancelled();
      final metrics = repository.lastMetrics;
      final safe = _sentinel.isSafeForHeavyOperation();
      if (metrics == null) throw StateError('Native benchmark metrics missing');
      if (metrics.promptTokens != RuntimeBenchmarkPolicy.promptTokens ||
          metrics.generatedTokens != RuntimeBenchmarkPolicy.outputTokens) {
        throw const RuntimeBenchmarkWorkloadUnavailable();
      }
      final applied = metrics.configuration;
      if (applied == null ||
          applied.contextSize != profile.contextSize ||
          applied.batchSize != profile.batchSize ||
          applied.generationThreads != profile.generationThreads ||
          applied.promptThreads != profile.promptThreads) {
        throw const RuntimeBenchmarkConfigurationUnavailable();
      }
      return RuntimeBenchmarkResult(
        profile: profile,
        promptTokensPerSecond: metrics.promptTokensPerSecond,
        generationTokensPerSecond: metrics.generatedTokensPerSecond,
        generatedTokens: metrics.generatedTokens,
        safe: safe,
        failureReason: safe ? null : _sentinel.unsafeReasonHeavy(),
      );
    } finally {
      await _closeRepository(repository);
      if (_cleanupFailed) throw InferenceRecoveryRequired();
      if (identical(_tuningRepository, repository)) _tuningRepository = null;
    }
  }
}
