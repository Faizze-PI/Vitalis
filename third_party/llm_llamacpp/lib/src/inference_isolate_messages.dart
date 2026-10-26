part of 'persistent_inference_isolate.dart';

class _InferenceRequestMessage {
  _InferenceRequestMessage({
    required this.requestId,
    required this.modelPath,
    required this.prompt,
    required this.stopTokens,
    required this.contextSize,
    required this.batchSize,
    required this.nGpuLayers,
    required this.options,
    this.threads,
    this.promptThreads,
    this.loraPath,
    this.loraScale = 1.0,
    this.messages,
    this.thinking,
    this.cleanupFault,
  });

  final int requestId;
  final String modelPath;
  final String prompt;
  final List<IsolateMessage>? messages;
  final bool? thinking;
  final List<String> stopTokens;
  final int contextSize;
  final int batchSize;
  final int? threads;
  final int? promptThreads;
  final int nGpuLayers;
  final GenerationOptions options;
  final String? loraPath;
  final double loraScale;
  final RuntimeCleanupFault? cleanupFault;
}

class _PrepareRequestMessage {
  _PrepareRequestMessage({
    required this.requestId,
    required this.modelPath,
    required this.contextSize,
    required this.batchSize,
    required this.nGpuLayers,
    this.threads,
    this.promptThreads,
  });

  final int requestId;
  final String modelPath;
  final int contextSize;
  final int batchSize;
  final int nGpuLayers;
  final int? threads;
  final int? promptThreads;
}

class _CancelRequestMessage {
  _CancelRequestMessage(this.requestId);
  final int requestId;
}

class _UnloadRequestMessage {
  _UnloadRequestMessage(this.requestId);
  final int requestId;
}

class _TokenizeRequestMessage {
  _TokenizeRequestMessage({
    required this.requestId,
    required this.messages,
    this.thinking,
  });
  final int requestId;
  final List<IsolateMessage> messages;
  final bool? thinking;
}

class _TokenCount {
  _TokenCount(this.value);
  final int value;
}

class _CancellationHandle {
  _CancellationHandle(this.address);
  final int address;
}

class _Prepared {
  _Prepared({required this.modelLoadMicros, required this.contextInitMicros});
  final int modelLoadMicros;
  final int contextInitMicros;
}

/// Internal response wrapper for sending data back from the helper isolate.
class _IsolateResponse {
  _IsolateResponse({
    required this.requestId,
    required this.payload,
    required this.isComplete,
    this.cleanupConfirmed = true,
  });

  final int requestId;
  final dynamic payload;
  final bool isComplete;
  final bool cleanupConfirmed;
}
