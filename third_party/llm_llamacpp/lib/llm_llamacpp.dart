/// llama.cpp backend implementation for LLM interactions.
///
/// This package provides local on-device inference using llama.cpp with GGUF models.
/// Supports Android, iOS, macOS, Windows, and Linux.
///
/// ## Usage
///
/// ```dart
/// import 'package:llm_llamacpp/llm_llamacpp.dart';
///
/// final chatRepo = LlamaCppChatRepository.withModelPath(
///   '/path/to/validated-model.gguf',
/// );
///
/// final stream = chatRepo.streamChat('model', messages: [
///   LLMMessage(role: LLMRole.user, content: 'Hello!')
/// ]);
/// await for (final chunk in stream) {
///   print(chunk.message?.content ?? '');
/// }
///
/// // Cleanup
/// chatRepo.dispose();
/// ```
///
/// ## LoRA Adapter Support
///
/// This package supports LoRA (Low-Rank Adaptation) adapters for fine-tuning:
///
/// ```dart
/// // Load a LoRA adapter
/// final chatRepo = LlamaCppChatRepository.withModelPath(
///   '/path/to/model.gguf',
///   loraPath: lora.path,
///   loraScale: 0.8,
/// );
///
/// // Or set/switch LoRA at runtime
/// chatRepo.setLora('/path/to/other-lora.gguf', scale: 0.5);
/// chatRepo.clearLora();
/// ```
///
library;

export 'src/native_log.dart';
export 'src/inference_output_timing.dart' show InferenceOutputTiming;
export 'src/runtime_progress.dart';
export 'src/verified_thinking_templates.dart';
export 'src/isolate_messages.dart' show InferenceRuntimeConfiguration;

// Re-export core types for convenience
export 'package:llm_core/llm_core.dart';

// Text runtime
export 'src/llamacpp_chat_repository.dart';

// Model management
export 'src/llamacpp_model.dart' show LlamaCppModel, ModelLoadOptions;

export 'src/backend_info.dart';
export 'src/exceptions.dart';
export 'src/runtime_session_reservation.dart'
    show
        RuntimeOperationKind,
        RuntimeReservationState,
        RuntimeRecoveryOutcome,
        RuntimeOperationSnapshot;

// LoRA adapter support
export 'src/lora_adapter.dart';

// Model loading
export 'src/model_loader.dart';

// GGUF metadata
export 'src/gguf_metadata.dart';

// Note: Prompt templates are now handled internally via llama_chat_apply_template()\n// which uses the template embedded in the GGUF model file.

// Generation options
export 'src/generation_options.dart';
export 'src/runtime_watchdog_policy.dart';

// Tool call parsing
export 'src/tool_call_parser.dart';
