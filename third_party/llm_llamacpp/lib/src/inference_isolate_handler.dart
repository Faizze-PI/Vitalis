part of 'persistent_inference_isolate.dart';

class _SessionTimings {
  const _SessionTimings(this.modelLoadMicros, this.contextInitMicros);
  final int modelLoadMicros;
  final int contextInitMicros;
}

class _RuntimeProgressEmitter {
  _RuntimeProgressEmitter(this.requestId, this.port);
  final int requestId;
  final SendPort port;
  final Stopwatch clock = Stopwatch()..start();
  void report(RuntimeProgressPhase phase, int completedUnits) {
    port.send(
      _IsolateResponse(
        requestId: requestId,
        payload: RuntimeProgress(
          requestId: requestId,
          phase: phase,
          completedUnits: completedUnits,
          elapsedMicroseconds: clock.elapsedMicroseconds,
        ),
        isComplete: false,
      ),
    );
  }
}

class _NativeInferenceSession {
  _NativeInferenceSession(this.bindings, this.bridge);

  final LlamaBindings bindings;
  final NativeRuntimeBridge bridge;
  ffi.Pointer<llama_model> model = ffi.nullptr;
  ffi.Pointer<ffi.Void> modelAccessLease = ffi.nullptr;
  ffi.Pointer<llama_context> context = ffi.nullptr;
  String? modelPath;
  int? gpuLayers;
  int? contextSize;
  int? batchSize;
  int? threads;
  int? promptThreads;
  int? activeRequestId;
  ffi.Pointer<ffi.Void>? cancelToken;
  List<int> cachedTokens = const [];
  RuntimeRequestFinalizer? pendingCleanup;

  ffi.Pointer<llama_vocab> get vocab {
    if (model.address == 0) throw StateError('No model loaded');
    return bindings.llama_model_get_vocab(model);
  }

  _SessionTimings ensure({
    required String path,
    required int requestedContextSize,
    required int requestedBatchSize,
    required int requestedGpuLayers,
    int? requestedThreads,
    int? requestedPromptThreads,
    void Function(RuntimeProgressPhase, int)? onProgress,
    ffi.Pointer<ffi.Void>? preparationCancelToken,
  }) {
    void checkCancellation() {
      if (preparationCancelToken != null &&
          bridge.isCancelRequested(preparationCancelToken)) {
        throw InferencePreparationCancelled();
      }
    }

    if (pendingCleanup != null) throw InferenceRecoveryRequired();
    checkCancellation();
    var modelLoadMicros = 0;
    var contextInitMicros = 0;
    final effectiveThreads =
        requestedThreads ?? (Platform.numberOfProcessors - 1).clamp(1, 8);
    final effectivePromptThreads = requestedPromptThreads ?? effectiveThreads;
    if (effectiveThreads <= 0 || effectivePromptThreads <= 0) {
      throw ArgumentError('Runtime thread counts must be positive');
    }
    final modelChanged =
        model.address == 0 ||
        modelPath != path ||
        gpuLayers != requestedGpuLayers;

    if (modelChanged) {
      dispose();
      onProgress?.call(RuntimeProgressPhase.modelLoading, 0);
      final timer = Stopwatch()..start();
      final params = bindings.llama_model_default_params()
        ..n_gpu_layers = requestedGpuLayers;
      if (preparationCancelToken != null) {
        params.progress_callback = bridge.modelLoadCancelCallback;
        params.progress_callback_user_data = preparationCancelToken;
      }
      final pathPointer = path.toNativeUtf8();
      try {
        modelAccessLease = bridge.acquireModelRead(modelPath: path);
        if (modelAccessLease.address == 0) throw InferenceRuntimeBusy();
        model = bindings.llama_load_model_from_file(pathPointer.cast(), params);
      } finally {
        calloc.free(pathPointer);
        if (model.address == 0 && modelAccessLease.address != 0) {
          bridge.releaseModelAccess(modelAccessLease);
          modelAccessLease = ffi.nullptr;
        }
      }
      timer.stop();
      modelLoadMicros = timer.elapsedMicroseconds;
      checkCancellation();
      if (model.address == 0) throw StateError('Failed to load selected model');
      modelPath = path;
      gpuLayers = requestedGpuLayers;
      onProgress?.call(RuntimeProgressPhase.modelLoading, 1);
    }

    final contextChanged =
        context.address == 0 ||
        contextSize != requestedContextSize ||
        batchSize != requestedBatchSize ||
        threads != effectiveThreads ||
        promptThreads != effectivePromptThreads;
    if (contextChanged) {
      checkCancellation();
      onProgress?.call(RuntimeProgressPhase.contextCreating, 0);
      if (context.address != 0) bindings.llama_free(context);
      context = ffi.nullptr;
      final timer = Stopwatch()..start();
      final params = bindings.llama_context_default_params()
        ..n_ctx = requestedContextSize
        ..n_batch = requestedBatchSize
        ..n_threads = effectiveThreads
        ..n_threads_batch = effectivePromptThreads;
      context = bindings.llama_new_context_with_model(model, params);
      timer.stop();
      contextInitMicros = timer.elapsedMicroseconds;
      checkCancellation();
      if (context.address == 0) {
        throw StateError(
          'Failed to allocate a $requestedContextSize-token context',
        );
      }
      contextSize = requestedContextSize;
      batchSize = requestedBatchSize;
      threads = effectiveThreads;
      promptThreads = effectivePromptThreads;
      cachedTokens = const [];
    }
    onProgress?.call(RuntimeProgressPhase.contextCreating, 1);
    checkCancellation();
    return _SessionTimings(modelLoadMicros, contextInitMicros);
  }

  ffi.Pointer<ffi.Void> beginRequest(
    int requestId, {
    ffi.Pointer<ffi.Void>? existingToken,
  }) {
    if (activeRequestId != null) throw StateError('Inference runtime is busy');
    activeRequestId = requestId;
    cancelToken = existingToken ?? bridge.createCancelToken();
    if (cancelToken!.address == 0) {
      activeRequestId = null;
      throw StateError('Failed to allocate native cancellation token');
    }
    bridge.setContextCancelToken(context, cancelToken!);
    return cancelToken!;
  }

  void cancel(int requestId) {
    final token = cancelToken;
    if (activeRequestId == requestId && token != null) {
      bridge.requestCancel(token);
    }
  }

  bool get isCancelled {
    final token = cancelToken;
    return token != null && bridge.isCancelRequested(token);
  }

  bool get isCancellationAcknowledged {
    final token = cancelToken;
    return token != null && bridge.isCancelAcknowledged(token);
  }

  void endRequest() {
    if (context.address != 0) {
      bridge.clearContextCancelToken(context);
    }
    final token = cancelToken;
    if (token != null) bridge.destroyCancelToken(token);
    cancelToken = null;
    activeRequestId = null;
  }

  void resetMemory() {
    if (context.address != 0) {
      bindings.llama_memory_clear(bindings.llama_get_memory(context), true);
    }
  }

  int preparePrompt(List<int> promptTokens) {
    var common = 0;
    final maximum = promptTokens.length < cachedTokens.length
        ? promptTokens.length
        : cachedTokens.length;
    while (common < maximum && promptTokens[common] == cachedTokens[common]) {
      common++;
    }
    if (common == 0) {
      resetMemory();
    } else if (common < cachedTokens.length) {
      final removed = bindings.llama_memory_seq_rm(
        bindings.llama_get_memory(context),
        0,
        common,
        -1,
      );
      if (!removed) {
        resetMemory();
        common = 0;
      }
    }
    cachedTokens = promptTokens.take(common).toList(growable: false);
    return common;
  }

  void commit(List<int> promptTokens, List<int> generatedTokens) {
    cachedTokens = [...promptTokens, ...generatedTokens];
  }

  void invalidateCache() {
    cachedTokens = const [];
    resetMemory();
  }

  void dispose() {
    final retained = pendingCleanup;
    if (retained != null) {
      if (retained.retry() != RuntimeCleanupOutcome.confirmed) {
        throw InferenceRecoveryRequired();
      }
      pendingCleanup = null;
    }
    endRequest();
    if (context.address != 0) bindings.llama_free(context);
    if (model.address != 0) bindings.llama_free_model(model);
    if (modelAccessLease.address != 0) {
      bridge.releaseModelAccess(modelAccessLease);
      modelAccessLease = ffi.nullptr;
    }
    context = ffi.nullptr;
    model = ffi.nullptr;
    modelPath = null;
    gpuLayers = null;
    contextSize = null;
    batchSize = null;
    threads = null;
    promptThreads = null;
    cachedTokens = const [];
  }
}

void _handlePrepareRequest(
  _PrepareRequestMessage request,
  SendPort mainSendPort,
  _NativeInferenceSession session,
) {
  final clock = Stopwatch()..start();
  final token = session.bridge.createCancelToken();
  Object terminal = InferenceError('Preparation outcome was not established');
  final finalizer = RuntimeRequestFinalizer(
    publish: (outcome) => mainSendPort.send(
      _IsolateResponse(
        requestId: request.requestId,
        payload: outcome,
        isComplete: true,
      ),
    ),
  );
  finalizer.add(RuntimeCleanupStep.cache, () {
    if (terminal is InferenceCancelled) session.invalidateCache();
  });
  finalizer.add(RuntimeCleanupStep.cancellation, () {
    if (token.address != 0) session.bridge.destroyCancelToken(token);
  });
  try {
    if (token.address == 0) {
      throw StateError('Failed to allocate preparation cancellation token');
    }
    session.bridge.retainCancelToken(token);
    mainSendPort.send(
      _IsolateResponse(
        requestId: request.requestId,
        payload: _CancellationHandle(token.address),
        isComplete: false,
      ),
    );
    final progress = _RuntimeProgressEmitter(request.requestId, mainSendPort);
    final timings = session.ensure(
      path: request.modelPath,
      requestedContextSize: request.contextSize,
      requestedBatchSize: request.batchSize,
      requestedGpuLayers: request.nGpuLayers,
      requestedThreads: request.threads,
      requestedPromptThreads: request.promptThreads,
      onProgress: progress.report,
      preparationCancelToken: token,
    );
    terminal = _Prepared(
      modelLoadMicros: timings.modelLoadMicros,
      contextInitMicros: timings.contextInitMicros,
    );
  } on InferencePreparationCancelled {
    terminal = _cancelledResult(clock);
  } catch (error) {
    terminal = InferenceError(NativeLog.redact('$error'));
  } finally {
    if (finalizer.finish(terminal) != RuntimeCleanupOutcome.confirmed) {
      session.pendingCleanup = finalizer;
      mainSendPort.send(
        _IsolateResponse(
          requestId: request.requestId,
          payload: InferenceCleanupRequired(
            finalizer.failedStep?.name ?? 'preparation_publication',
          ),
          isComplete: true,
          cleanupConfirmed: false,
        ),
      );
    }
  }
}

void _handleTokenizeRequest(
  _TokenizeRequestMessage request,
  SendPort mainSendPort,
  _NativeInferenceSession session,
) {
  try {
    if (session.model.address == 0) throw StateError('No model prepared');
    final prompt = applyNativeChatTemplate(
      session.bindings,
      session.model,
      request.messages,
      thinking: request.thinking,
    );
    final promptByteLength = utf8.encode(prompt).length;
    final promptPointer = prompt.toNativeUtf8();
    final probe = calloc<ffi.Int32>(1);
    final result = session.bindings.llama_tokenize(
      session.vocab,
      promptPointer.cast(),
      promptByteLength,
      probe,
      1,
      true,
      true,
    );
    calloc.free(probe);
    calloc.free(promptPointer);
    final count = result < 0 ? -result : result;
    mainSendPort.send(
      _IsolateResponse(
        requestId: request.requestId,
        payload: _TokenCount(count),
        isComplete: true,
      ),
    );
  } catch (error) {
    mainSendPort.send(
      _IsolateResponse(
        requestId: request.requestId,
        payload: InferenceError(error.toString()),
        isComplete: true,
      ),
    );
  }
}

void _handleInferenceRequest(
  _InferenceRequestMessage request,
  SendPort mainSendPort,
  ffi.DynamicLibrary lib,
  LlamaBindings bindings,
  _NativeInferenceSession session,
) {
  ffi.Pointer<ffi.Int32>? tokensPointer;
  ffi.Pointer<llama_sampler>? sampler;
  ffi.Pointer<llama_adapter_lora>? loraAdapter;
  ffi.Pointer<ffi.Void>? loadingToken;
  InferenceRuntimeConfiguration? configuration;
  final requestClock = Stopwatch()..start();
  final outputTiming = InferenceOutputTimingRecorder(
    request.requestId,
    () => requestClock.elapsedMicroseconds,
  );
  var committed = false;
  final progress = _RuntimeProgressEmitter(request.requestId, mainSendPort);
  final cleanupFault = RuntimeCleanupFaultController(request.cleanupFault);
  Object terminal = InferenceError(
    'Native request outcome was not established',
  );
  final finalizer = RuntimeRequestFinalizer(
    publish: (outcome) {
      progress.report(RuntimeProgressPhase.requestCleanup, 1);
      mainSendPort.send(
        _IsolateResponse(
          requestId: request.requestId,
          payload: outcome,
          isComplete: true,
        ),
      );
    },
  );
  finalizer.add(RuntimeCleanupStep.sampler, () {
    cleanupFault.beforeCleanup(RuntimeCleanupStep.sampler);
    if (sampler != null) bindings.llama_sampler_free(sampler!);
    sampler = null;
  });
  finalizer.add(RuntimeCleanupStep.promptAllocation, () {
    cleanupFault.beforeCleanup(RuntimeCleanupStep.promptAllocation);
    if (tokensPointer != null) calloc.free(tokensPointer!);
    tokensPointer = null;
  });
  finalizer.add(RuntimeCleanupStep.adapter, () {
    cleanupFault.beforeCleanup(RuntimeCleanupStep.adapter);
    if (loraAdapter != null) {
      bindings.llama_clear_adapter_lora(session.context);
      bindings.llama_adapter_lora_free(loraAdapter!);
      loraAdapter = null;
    }
  });
  finalizer.add(RuntimeCleanupStep.cache, () {
    cleanupFault.beforeCleanup(RuntimeCleanupStep.cache);
    if (!committed) session.invalidateCache();
  });
  finalizer.add(RuntimeCleanupStep.cancellation, () {
    cleanupFault.beforeCleanup(RuntimeCleanupStep.cancellation);
    if (loadingToken != null) {
      session.bridge.destroyCancelToken(loadingToken!);
      loadingToken = null;
    }
    session.endRequest();
  });

  try {
    loadingToken = session.bridge.createCancelToken();
    if (loadingToken!.address == 0) {
      loadingToken = null;
      throw StateError('Failed to allocate native cancellation token');
    }
    // Keep the token outside the session during ensure: replacing a model
    // disposes the old session, which must not release the new loading token.
    session.bridge.retainCancelToken(loadingToken!);
    mainSendPort.send(
      _IsolateResponse(
        requestId: request.requestId,
        payload: _CancellationHandle(loadingToken!.address),
        isComplete: false,
      ),
    );
    final timings = session.ensure(
      path: request.modelPath,
      requestedContextSize: request.contextSize,
      requestedBatchSize: request.batchSize,
      requestedGpuLayers: request.nGpuLayers,
      requestedThreads: request.threads,
      requestedPromptThreads: request.promptThreads,
      onProgress: progress.report,
      preparationCancelToken: loadingToken,
    );
    session.beginRequest(request.requestId, existingToken: loadingToken);
    loadingToken = null; // Session now owns the helper's token reference.
    configuration = InferenceRuntimeConfiguration(
      contextSize: bindings.llama_n_ctx(session.context),
      batchSize: bindings.llama_n_batch(session.context),
      generationThreads: bindings.llama_n_threads(session.context),
      promptThreads: bindings.llama_n_threads_batch(session.context),
    );

    if (request.loraPath != null) {
      final path = request.loraPath!.toNativeUtf8();
      try {
        loraAdapter = bindings.llama_adapter_lora_init(
          session.model,
          path.cast(),
        );
      } finally {
        calloc.free(path);
      }
      if (loraAdapter!.address == 0 ||
          bindings.llama_set_adapter_lora(
                session.context,
                loraAdapter!,
                request.loraScale,
              ) !=
              0) {
        throw StateError('Failed to apply LoRA adapter');
      }
    }

    final prompt = request.messages != null && request.messages!.isNotEmpty
        ? applyNativeChatTemplate(
            bindings,
            session.model,
            request.messages!,
            thinking: request.thinking,
          )
        : request.prompt;
    // llama_tokenize takes UTF-8 bytes, not Dart UTF-16 code units.
    final promptByteLength = utf8.encode(prompt).length;
    var capacity = promptByteLength + 256;
    tokensPointer = calloc<ffi.Int32>(capacity);
    final promptPointer = prompt.toNativeUtf8();
    var promptTokens = bindings.llama_tokenize(
      session.vocab,
      promptPointer.cast(),
      promptByteLength,
      tokensPointer!,
      capacity,
      true,
      true,
    );
    if (promptTokens < 0) {
      calloc.free(tokensPointer!);
      tokensPointer = null;
      capacity = -promptTokens;
      tokensPointer = calloc<ffi.Int32>(capacity);
      promptTokens = bindings.llama_tokenize(
        session.vocab,
        promptPointer.cast(),
        promptByteLength,
        tokensPointer!,
        capacity,
        true,
        true,
      );
    }
    calloc.free(promptPointer);
    if (promptTokens < 0) throw StateError('Failed to tokenize prompt');

    final availableOutput = request.contextSize - promptTokens;
    if (availableOutput <= 0) {
      throw StateError(
        'Prompt requires $promptTokens tokens but the context holds '
        '${request.contextSize}',
      );
    }
    final maxOutputTokens = request.options.maxTokens.clamp(1, availableOutput);

    final promptTokenList = List<int>.generate(
      promptTokens,
      (index) => tokensPointer![index],
      growable: false,
    );
    final cachedPrefixLength = session.preparePrompt(promptTokenList);
    final promptTimer = Stopwatch()..start();
    final remainingPromptTokens = promptTokens - cachedPrefixLength;
    var promptDecodeResult = 0;
    progress.report(RuntimeProgressPhase.promptEvaluating, cachedPrefixLength);
    // llama.cpp treats a batch larger than n_batch as a fatal invariant
    // violation. A formatted chat prompt can legitimately be larger than the
    // conservative runtime batch (for example the fixed 256-token tuning
    // workload with a 128-token batch), so decode it in ordered native-sized
    // chunks instead of submitting it as one process-fatal request.
    for (final chunk in promptDecodeChunks(
      tokenCount: remainingPromptTokens,
      batchSize: request.batchSize,
    )) {
      if (session.isCancelled) {
        promptDecodeResult = 2;
        break;
      }
      promptDecodeResult = bindings.llama_decode(
        session.context,
        bindings.llama_batch_get_one(
          tokensPointer! + cachedPrefixLength + chunk.offset,
          chunk.length,
        ),
      );
      if (promptDecodeResult != 0) break;
      progress.report(
        RuntimeProgressPhase.promptEvaluating,
        cachedPrefixLength + chunk.offset + chunk.length,
      );
    }
    promptTimer.stop();
    if (session.isCancelled || promptDecodeResult == 2) {
      if (!session.isCancellationAcknowledged) {
        throw StateError('Native cancellation was not acknowledged');
      }
      terminal = _cancelledResult(
        requestClock,
        outputTiming: outputTiming.snapshot,
        configuration: configuration,
        promptTokens: promptTokens,
        modelLoadMicros: timings.modelLoadMicros,
        contextInitMicros: timings.contextInitMicros,
        promptEvalMicros: promptTimer.elapsedMicroseconds,
      );
      return;
    }
    if (promptDecodeResult != 0) {
      throw StateError('Prompt evaluation failed ($promptDecodeResult)');
    }

    sampler = _configureSampler(bindings, session.vocab, request.options);
    final generationTimer = Stopwatch()..start();
    final result = _generateTokens(
      bindings,
      session.model,
      session.context,
      sampler!,
      session.vocab,
      request.options,
      maxOutputTokens,
      request.stopTokens,
      request.requestId,
      mainSendPort,
      () => session.isCancelled,
      progress.report,
      outputTiming,
    );
    generationTimer.stop();

    if (result.reason == InferenceCompletionReason.cancelled) {
      if (!session.isCancellationAcknowledged) {
        throw StateError('Native cancellation was not acknowledged');
      }
      terminal = _cancelledResult(
        requestClock,
        configuration: configuration,
        promptTokens: promptTokens,
        generatedTokens: result.generatedTokens,
        modelLoadMicros: timings.modelLoadMicros,
        contextInitMicros: timings.contextInitMicros,
        promptEvalMicros: promptTimer.elapsedMicroseconds,
        generationMicros: generationTimer.elapsedMicroseconds,
        timeToFirstTokenMicros: result.timeToFirstTokenMicros,
        outputTiming: outputTiming.snapshot,
      );
      return;
    }
    session.commit(promptTokenList, result.tokens);
    committed = true;
    terminal = InferenceComplete(
      configuration: configuration,
      promptTokens: promptTokens,
      generatedTokens: result.generatedTokens,
      modelLoadMicros: timings.modelLoadMicros,
      contextInitMicros: timings.contextInitMicros,
      promptEvalMicros: promptTimer.elapsedMicroseconds,
      generationMicros: generationTimer.elapsedMicroseconds,
      timeToFirstTokenMicros: result.timeToFirstTokenMicros,
      outputTiming: outputTiming.snapshot,
      reason: result.reason,
    );
  } on InferencePreparationCancelled {
    terminal = _cancelledResult(
      requestClock,
      outputTiming: outputTiming.snapshot,
    );
  } catch (error) {
    terminal = InferenceError(NativeLog.redact('$error'));
  } finally {
    progress.report(RuntimeProgressPhase.requestCleanup, 0);
    if (finalizer.finish(terminal) != RuntimeCleanupOutcome.confirmed) {
      session.pendingCleanup = finalizer;
      mainSendPort.send(
        _IsolateResponse(
          requestId: request.requestId,
          payload: InferenceCleanupRequired(
            finalizer.failedStep?.name ?? 'publication',
          ),
          isComplete: true,
          cleanupConfirmed: false,
        ),
      );
    }
  }
}

InferenceCancelled _cancelledResult(
  Stopwatch clock, {
  int promptTokens = 0,
  int generatedTokens = 0,
  int modelLoadMicros = 0,
  int contextInitMicros = 0,
  int promptEvalMicros = 0,
  int generationMicros = 0,
  int? timeToFirstTokenMicros,
  InferenceOutputTiming? outputTiming,
  InferenceRuntimeConfiguration? configuration,
}) {
  return InferenceCancelled(
    acknowledgementMicros: clock.elapsedMicroseconds,
    promptTokens: promptTokens,
    generatedTokens: generatedTokens,
    modelLoadMicros: modelLoadMicros,
    contextInitMicros: contextInitMicros,
    promptEvalMicros: promptEvalMicros,
    generationMicros: generationMicros,
    timeToFirstTokenMicros: timeToFirstTokenMicros,
    outputTiming: outputTiming,
    configuration: configuration,
  );
}
