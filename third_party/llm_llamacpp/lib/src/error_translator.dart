import 'package:llm_core/llm_core.dart' show ModelLoadException;
import 'package:llm_llamacpp/src/exceptions.dart';

/// Translates error messages from isolate workers into appropriate exceptions.
///
/// Centralized error handling for the supported text inference runtime.
class InferenceErrorTranslator {
  InferenceErrorTranslator._();

  /// Translates an inference error message into an appropriate exception.
  ///
  /// [error] - The error message from the isolate.
  /// [modelPath] - Optional model path for context.
  /// [prompt] - Optional prompt that caused the error (for tokenization errors).
  /// [contextSize] - Optional context size (for context creation errors).
  /// [batchSize] - Optional batch size (for context creation errors).
  ///
  /// Returns an appropriate exception based on the error message content.
  static Exception translateInferenceError(
    String error, {
    String? modelPath,
    String? prompt,
    int? contextSize,
    int? batchSize,
  }) {
    if (error.contains('Failed to load model') ||
        error.contains('Failed to load LoRA adapter')) {
      return ModelLoadException(error, modelPath: modelPath);
    } else if (error.contains('Failed to tokenize')) {
      return TokenizationException(message: error, prompt: prompt);
    } else if (error.contains('Failed to create context')) {
      return ContextCreationException(
        message: error,
        contextSize: contextSize,
        batchSize: batchSize,
      );
    } else {
      return InferenceException(
        message: error,
        details: 'Model: ${modelPath ?? "unknown"}',
      );
    }
  }
}
