// ============================================================
// Backend Exceptions
// ============================================================

/// A scheduling conflict, not evidence that a model is corrupt or incompatible.
class InferenceRuntimeBusy extends StateError {
  InferenceRuntimeBusy() : super('Inference runtime is busy');
}

class InferenceRepositoryDisposed extends StateError {
  InferenceRepositoryDisposed() : super('Inference repository is disposed');
}

/// A deliberately unshipped capability, not corrupt model data or runtime busy.
class InferenceCapabilityUnsupported extends UnsupportedError {
  InferenceCapabilityUnsupported(this.capability)
    : super('$capability are unavailable in the VITALIS text runtime');

  final String capability;
}

class InferenceRecoveryRequired extends StateError {
  InferenceRecoveryRequired()
    : super('Native termination is unconfirmed; owner recovery is required');
}

/// Preparation stopped; a caller must re-establish model/context readiness.
class InferencePreparationCancelled extends StateError {
  InferencePreparationCancelled() : super('Model preparation was cancelled');
}

/// Thrown when llama.cpp backend initialization fails.
class BackendInitException implements Exception {
  BackendInitException({required this.message, this.details});

  /// Error message.
  final String message;

  /// Additional error details, if available.
  final String? details;

  @override
  String toString() {
    if (details != null) {
      return 'BackendInitException: $message\nDetails: $details';
    }
    return 'BackendInitException: $message';
  }
}

/// Thrown when inference fails.
class InferenceException implements Exception {
  InferenceException({required this.message, this.details});

  /// Error message.
  final String message;

  /// Additional error details, if available.
  final String? details;

  @override
  String toString() {
    if (details != null) {
      return 'InferenceException: $message\nDetails: $details';
    }
    return 'InferenceException: $message';
  }
}

/// Thrown when context creation fails.
class ContextCreationException implements Exception {
  ContextCreationException({
    required this.message,
    this.contextSize,
    this.batchSize,
  });

  /// Error message.
  final String message;

  /// The context size that was requested.
  final int? contextSize;

  /// The batch size that was requested.
  final int? batchSize;

  @override
  String toString() {
    final buffer = StringBuffer('ContextCreationException: $message');
    if (contextSize != null || batchSize != null) {
      buffer.write('\nRequested:');
      if (contextSize != null) {
        buffer.write(' contextSize=$contextSize');
      }
      if (batchSize != null) {
        buffer.write(' batchSize=$batchSize');
      }
    }
    return buffer.toString();
  }
}

// ============================================================
// LoRA Exceptions
// ============================================================

/// Thrown when a LoRA adapter fails to load.
class LoraLoadException implements Exception {
  LoraLoadException({required this.path, required this.message});

  /// Path to the LoRA file that failed to load.
  final String path;

  /// Error message.
  final String message;

  @override
  String toString() {
    return "LoraLoadException: $message\nPath: '$path'";
  }
}

// ============================================================
// Tokenization Exceptions
// ============================================================

/// Thrown when tokenization fails.
class TokenizationException implements Exception {
  TokenizationException({required this.message, this.prompt, this.details});

  /// Error message.
  final String message;

  /// The prompt that failed to tokenize (may be truncated).
  final String? prompt;

  /// Additional error details, if available.
  final String? details;

  @override
  String toString() {
    final buffer = StringBuffer('TokenizationException: $message');
    if (prompt != null) {
      final truncated = prompt!.length > 100
          ? '${prompt!.substring(0, 100)}...'
          : prompt!;
      buffer.write('\nPrompt: $truncated');
    }
    if (details != null) {
      buffer.write('\nDetails: $details');
    }
    return buffer.toString();
  }
}
