part of 'llamacpp_chat_repository.dart';

Stream<LLMChunk> _streamChatImpl(
  LlamaCppChatRepository repo,
  String model,
  List<LLMMessage> messages,
  bool think,
  List<LLMTool> tools,
  dynamic extra,
  LLMChatOptions? options,
  GenerationOptions? generationOptions,
) async* {
  final genOptions = generationOptions ?? const GenerationOptions();
  Validation.validateModelName(model);
  Validation.validateMessages(messages);

  final String modelPath;
  if (repo._model != null) {
    modelPath = repo._model!.path;
  } else if (repo._modelPath != null) {
    modelPath = repo._modelPath!;
  } else {
    throw const ModelLoadException(
      'No model loaded. Call loadModel() first, use LlamaCppChatRepository.withModel(), or use LlamaCppChatRepository.withModelPath().',
    );
  }

  if (repo._model != null && repo.contextSize > repo._model!.contextSizeTrain) {
    LlamaCppChatRepository._log.warning(
      'Requested context size (${repo.contextSize}) exceeds model training context size (${repo._model!.contextSizeTrain}). '
      'This may cause issues or be truncated.',
    );
  }

  final hasImages = messages.any(
    (msg) => msg.images != null && msg.images!.isNotEmpty,
  );
  if (hasImages) {
    throw VisionNotSupportedException(
      model,
      'Vision/image support is not yet fully implemented in llm_llamacpp. '
      'Vision models can be loaded and used for text inference, but image input processing requires additional multimodal bindings.',
    );
  }

  final effectiveTools = options?.tools.isNotEmpty == true
      ? options!.tools
      : tools;
  final effectiveExtra = options?.extra ?? extra;
  final effectiveToolAttempts = options?.toolAttempts;
  final currentAttempts = effectiveToolAttempts ?? repo.maxToolAttempts;

  LlamaCppChatRepository._log.fine(
    'streamChat called with ${effectiveTools.length} tools, attempt ${repo.maxToolAttempts - currentAttempts + 1}',
  );
  LlamaCppChatRepository._log.fine('Messages count: ${messages.length}');

  final isolateMessages = messages
      .map(
        (msg) => IsolateMessage(
          role: switch (msg.role) {
            LLMRole.system => 'system',
            LLMRole.user => 'user',
            LLMRole.assistant => 'assistant',
            LLMRole.tool => 'tool',
          },
          content: msg.content ?? '',
        ),
      )
      .toList();

  LlamaCppChatRepository._log.fine(
    'Sending ${isolateMessages.length} messages for native template formatting',
  );

  repo._retainModelFileOwnership();
  final inferenceStream = PersistentInferenceIsolate.instance.runInference(
    owner: repo._runtimeOwner,
    modelPath: modelPath,
    prompt: '',
    stopTokens: const ['<|im_end|>', '<|endoftext|>'],
    contextSize: repo.contextSize,
    batchSize: repo.batchSize,
    threads: repo.threads,
    promptThreads: repo.promptThreads,
    nGpuLayers: repo.nGpuLayers,
    options: genOptions,
    loraPath: repo._loraPath,
    loraScale: repo._loraScale,
    messages: isolateMessages,
    thinking: repo.supportsThinkingControl ? think : null,
    kind: repo.runtimeOperationKind,
    onTerminal: repo._recordTerminalMetrics,
  );

  try {
    final streamHandler = ToolCallStreamHandler(
      logger: LlamaCppChatRepository._log,
      tools: effectiveTools,
    );

    await for (final message in inferenceStream) {
      // Drain terminal native events during shutdown without publishing late
      // output or completion to a repository whose consumer has disposed it.
      if (repo._disposed) continue;
      if (message is RuntimeProgress) {
        yield LlamaCppProgressChunk(message);
      } else if (message is InferenceToken) {
        final token = message.token;
        if (token.isEmpty) continue;
        final result = streamHandler.processToken(token);
        if (result.shouldYield && result.content != null) {
          yield LLMChunk(
            model: model,
            createdAt: DateTime.now(),
            message: LLMChunkMessage(
              content: result.content,
              role: LLMRole.assistant,
            ),
            done: false,
          );
        }
      } else if (message is InferenceCancelled) {
        yield LLMChunk(
          model: model,
          createdAt: DateTime.now(),
          message: LLMChunkMessage(content: null, role: LLMRole.assistant),
          done: true,
          promptEvalCount: message.promptTokens,
          evalCount: message.generatedTokens,
        );
      } else if (message is InferenceComplete) {
        // Each yield can synchronously retire this repository in its consumer.
        // Recheck before continuing the same native completion branch.
        if (repo._disposed) continue;
        LlamaCppChatRepository._log.fine(
          'Inference complete. Accumulated content (${streamHandler.accumulatedContent.length} chars)',
        );

        final remainingContent = streamHandler.finalize(
          hasTools: effectiveTools.isNotEmpty,
        );
        if (remainingContent != null) {
          yield LLMChunk(
            model: model,
            createdAt: DateTime.now(),
            message: LLMChunkMessage(
              content: remainingContent,
              role: LLMRole.assistant,
            ),
            done: false,
          );
        }
        if (repo._disposed) continue;

        final collectedToolCalls = streamHandler.collectedToolCalls;
        yield LLMChunk(
          model: model,
          createdAt: DateTime.now(),
          message: LLMChunkMessage(
            content: null,
            role: LLMRole.assistant,
            toolCalls: collectedToolCalls.isEmpty ? null : collectedToolCalls,
          ),
          done: true,
          promptEvalCount: message.promptTokens,
          evalCount: message.generatedTokens,
        );
        if (repo._disposed) continue;

        if (collectedToolCalls.isNotEmpty && effectiveTools.isNotEmpty) {
          LlamaCppChatRepository._log.info(
            'Executing ${collectedToolCalls.length} tool calls...',
          );
          if (currentAttempts > 0) {
            final workingMessages = List<LLMMessage>.from(messages);
            workingMessages.add(
              LLMMessage(
                role: LLMRole.assistant,
                content: streamHandler.accumulatedContent,
              ),
            );

            final toolMessages = await ToolExecutor.executeTools(
              collectedToolCalls,
              effectiveTools,
              effectiveExtra,
              LlamaCppChatRepository._log,
            );
            if (repo._disposed) continue;
            workingMessages.addAll(toolMessages);

            LlamaCppChatRepository._log.fine(
              'Continuing conversation with tool results...',
            );
            final nextOptions =
                options?.copyWith(toolAttempts: currentAttempts - 1) ??
                StreamChatOptions(
                  tools: effectiveTools,
                  extra: effectiveExtra,
                  toolAttempts: currentAttempts - 1,
                );
            yield* repo.streamChatWithGenerationOptions(
              model,
              messages: workingMessages,
              tools: effectiveTools,
              extra: effectiveExtra,
              options: nextOptions,
              generationOptions: genOptions,
            );
          } else {
            LlamaCppChatRepository._log.warning(
              'Max tool attempts reached, not continuing',
            );
          }
        }
        break;
      } else if (message is InferenceCleanupRequired) {
        throw InferenceRecoveryRequired();
      } else if (message is InferenceError) {
        LlamaCppChatRepository._log.severe('Inference error: ${message.error}');
        throw InferenceErrorTranslator.translateInferenceError(
          message.error,
          modelPath: repo._model?.path,
          prompt: '(${messages.length} messages)',
          contextSize: repo.contextSize,
          batchSize: repo.batchSize,
        );
      } else if (message is InferenceCancelled) {
        return;
      } else if (message is InferenceError) {
        throw StateError(message.error);
      }
    }
  } finally {
    // Persistent isolate stays alive
  }
}
