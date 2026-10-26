/// Monotonic offsets from helper request handling, including model/context and
/// prompt work. Emission means sending nonempty text, not UI rendering.
class InferenceOutputTiming {
  const InferenceOutputTiming({
    required this.requestId,
    this.firstSampledTokenMicros,
    this.firstEmittedTextMicros,
  });
  final int requestId;

  /// Includes an EOG sample even if no text is emitted.
  final int? firstSampledTokenMicros;
  final int? firstEmittedTextMicros;
}

class InferenceOutputTimingRecorder {
  InferenceOutputTimingRecorder(this.requestId, this.readRequestMicros);
  final int requestId;
  final int Function() readRequestMicros;
  int? _sampled;
  int? _emitted;
  void sampled() {
    _sampled ??= readRequestMicros();
  }

  void emitted() {
    _emitted ??= readRequestMicros();
  }

  InferenceOutputTiming get snapshot => InferenceOutputTiming(
    requestId: requestId,
    firstSampledTokenMicros: _sampled,
    firstEmittedTextMicros: _emitted,
  );
}
