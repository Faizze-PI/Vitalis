import 'package:llm_llamacpp/src/inference_output_timing.dart';

/// A simple message representation that can be passed between isolates.
///
/// This is a lightweight alternative to LLMMessage that avoids any
/// complex types that might not serialize well across isolate boundaries.
class IsolateMessage {
  const IsolateMessage({required this.role, required this.content});

  final String role;
  final String content;
}

/// Token message sent during inference streaming.
class InferenceToken {
  InferenceToken(this.token);
  final String token;
}

/// Applied context values queried from native getters, not echoed requests.
class InferenceRuntimeConfiguration {
  const InferenceRuntimeConfiguration({
    required this.contextSize,
    required this.batchSize,
    required this.generationThreads,
    required this.promptThreads,
  });
  final int contextSize;
  final int batchSize;
  final int generationThreads;
  final int promptThreads;
}

/// Completion message indicating inference is finished.
class InferenceComplete {
  InferenceComplete({
    required this.promptTokens,
    required this.generatedTokens,
    this.modelLoadMicros = 0,
    this.contextInitMicros = 0,
    this.promptEvalMicros = 0,
    this.generationMicros = 0,
    this.timeToFirstTokenMicros,
    this.outputTiming,
    this.configuration,
    this.reason = InferenceCompletionReason.endOfGeneration,
  });
  final int promptTokens;
  final int generatedTokens;
  final int modelLoadMicros;
  final int contextInitMicros;
  final int promptEvalMicros;
  final int generationMicros;

  /// Compatibility alias for first emitted text from helper request start.
  /// This is not an end-to-end UI-visible measurement.
  final int? timeToFirstTokenMicros;
  final InferenceOutputTiming? outputTiming;
  final InferenceRuntimeConfiguration? configuration;
  final InferenceCompletionReason reason;
}

enum InferenceCompletionReason {
  endOfGeneration,
  stopSequence,
  outputLimit,
  cancelled,
}

class InferenceCancelled {
  InferenceCancelled({
    required this.acknowledgementMicros,
    this.promptTokens = 0,
    this.generatedTokens = 0,
    this.modelLoadMicros = 0,
    this.contextInitMicros = 0,
    this.promptEvalMicros = 0,
    this.generationMicros = 0,
    this.timeToFirstTokenMicros,
    this.outputTiming,
    this.configuration,
  });
  final int acknowledgementMicros;
  final int promptTokens;
  final int generatedTokens;
  final int modelLoadMicros;
  final int contextInitMicros;
  final int promptEvalMicros;
  final int generationMicros;

  /// Compatibility alias for first emitted text from helper request start.
  final int? timeToFirstTokenMicros;
  final InferenceOutputTiming? outputTiming;
  final InferenceRuntimeConfiguration? configuration;

  InferenceCancelled withAcknowledgement(int value) => InferenceCancelled(
    acknowledgementMicros: value,
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

/// Error message sent when inference fails.
class InferenceError {
  InferenceError(this.error);
  final String error;
}

/// Decoding ended, but native resources remain owned until recovery succeeds.
class InferenceCleanupRequired extends InferenceError {
  InferenceCleanupRequired(this.step)
    : super('Native request cleanup remains unconfirmed ($step)');
  final String step;
}
