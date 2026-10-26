part of 'persistent_inference_isolate.dart';

class _GenerationResult {
  const _GenerationResult({
    required this.generatedTokens,
    required this.reason,
    this.timeToFirstTokenMicros,
    this.tokens = const [],
  });

  final int generatedTokens;
  final InferenceCompletionReason reason;
  final int? timeToFirstTokenMicros;
  final List<int> tokens;
}

_GenerationResult _generateTokens(
  LlamaBindings bindings,
  ffi.Pointer<llama_model> model,
  ffi.Pointer<llama_context> ctx,
  ffi.Pointer<llama_sampler> sampler,
  ffi.Pointer<llama_vocab> vocab,
  GenerationOptions options,
  int maxOutputTokens,
  List<String> stopTokens,
  int requestId,
  SendPort mainSendPort,
  bool Function() isCancelled,
  void Function(RuntimeProgressPhase, int) onProgress,
  InferenceOutputTimingRecorder outputTiming,
) {
  const initialBufferSize = 256; // hardcode: HC-041
  var pieceBuffer = calloc<ffi.Char>(initialBufferSize);
  var pieceBufferSize = initialBufferSize;
  var generatedTokens = 0;
  final newTokenPointer = calloc<ffi.Int32>(1);
  final byteAccumulator = <int>[];
  final pendingText = StringBuffer();
  var reason = InferenceCompletionReason.outputLimit;
  final generatedTokenIds = <int>[];

  void emitSafeText({bool flush = false}) {
    final text = pendingText.toString();
    pendingText.clear();
    final stopIndex = stopTokens
        .map(text.indexOf)
        .where((index) => index >= 0)
        .fold<int?>(null, (earliest, index) {
          return earliest == null || index < earliest ? index : earliest;
        });
    if (stopIndex != null) {
      if (stopIndex > 0) {
        outputTiming.emitted();
        mainSendPort.send(
          _IsolateResponse(
            requestId: requestId,
            payload: InferenceToken(text.substring(0, stopIndex)),
            isComplete: false,
          ),
        );
      }
      reason = InferenceCompletionReason.stopSequence;
      return;
    }
    final retained = flush ? 0 : retainedStopPrefixLength(text, stopTokens);
    final emitLength = text.length - retained;
    if (emitLength > 0) {
      outputTiming.emitted();
      mainSendPort.send(
        _IsolateResponse(
          requestId: requestId,
          payload: InferenceToken(text.substring(0, emitLength)),
          isComplete: false,
        ),
      );
    }
    if (retained > 0) pendingText.write(text.substring(emitLength));
  }

  try {
    while (generatedTokens < maxOutputTokens) {
      if (isCancelled()) {
        reason = InferenceCompletionReason.cancelled;
        break;
      }
      final newToken = bindings.llama_sampler_sample(sampler, ctx, -1);
      outputTiming.sampled();
      // The locked llama.cpp sample API already accepts this token into the
      // sampler history. Accepting it again doubles stateful penalties.
      if (bindings.llama_vocab_is_eog(vocab, newToken)) {
        reason = InferenceCompletionReason.endOfGeneration;
        break;
      }
      // Count sampled non-EOG tokens, including stop markers and a token whose
      // text is emitted before cancellation interrupts its decode. Cache IDs
      // remain separate: only successfully decoded tokens can be committed.
      generatedTokens++;

      var pieceLength = bindings.llama_token_to_piece(
        vocab,
        newToken,
        pieceBuffer,
        pieceBufferSize,
        0,
        true,
      );
      if (pieceLength < 0) {
        pieceBufferSize = -pieceLength;
        calloc.free(pieceBuffer);
        pieceBuffer = calloc<ffi.Char>(pieceBufferSize);
        pieceLength = bindings.llama_token_to_piece(
          vocab,
          newToken,
          pieceBuffer,
          pieceBufferSize,
          0,
          true,
        );
      }
      if (pieceLength > 0) {
        byteAccumulator.addAll(
          pieceBuffer.cast<ffi.Uint8>().asTypedList(pieceLength),
        );
        try {
          final piece = const Utf8Decoder().convert(byteAccumulator);
          byteAccumulator.clear();
          if (piece.isNotEmpty) {
            pendingText.write(piece);
            emitSafeText();
            if (reason == InferenceCompletionReason.stopSequence) break;
          }
        } on FormatException {
          // A token may contain only part of a UTF-8 scalar.
        }
      }

      newTokenPointer[0] = newToken;
      final decodeResult = bindings.llama_decode(
        ctx,
        bindings.llama_batch_get_one(newTokenPointer, 1),
      );
      if (decodeResult == 2 || isCancelled()) {
        reason = InferenceCompletionReason.cancelled;
        break;
      }
      if (decodeResult != 0) {
        throw StateError('Token decode failed ($decodeResult)');
      }
      generatedTokenIds.add(newToken);
      onProgress(RuntimeProgressPhase.tokenDecoding, generatedTokenIds.length);
    }

    if (reason != InferenceCompletionReason.cancelled &&
        reason != InferenceCompletionReason.stopSequence) {
      if (byteAccumulator.isNotEmpty) {
        pendingText.write(
          const Utf8Decoder(allowMalformed: true).convert(byteAccumulator),
        );
      }
      emitSafeText(flush: true);
    }
    return _GenerationResult(
      generatedTokens: generatedTokens,
      reason: reason,
      timeToFirstTokenMicros: outputTiming.snapshot.firstEmittedTextMicros,
      tokens: generatedTokenIds,
    );
  } finally {
    calloc.free(pieceBuffer);
    calloc.free(newTokenPointer);
  }
}
