/// Generation-provider admission to receipt/painted-frame offsets. Excludes
/// earlier tap/user-message persistence; not display-panel latency.
class ResponseFrameTiming {
  const ResponseFrameTiming({
    required this.responseIdentity,
    this.nativeRequestId,
    this.firstReceivedTextMicros,
    this.firstRenderedFrameMicros,
  });
  final Object responseIdentity;
  final int? nativeRequestId;
  final int? firstReceivedTextMicros;
  final int? firstRenderedFrameMicros;
}

class ResponseFrameTimingTracker {
  ResponseFrameTimingTracker(this.readMonotonicMicros);
  final int Function() readMonotonicMicros;
  Object? _identity;
  int _started = 0;
  int? _received;
  int? _rendered;
  int? _nativeRequest;
  bool _eligible = false;
  Object? get identity => _identity;
  ResponseFrameTiming? get snapshot => _identity == null
      ? null
      : ResponseFrameTiming(
          responseIdentity: _identity!,
          nativeRequestId: _nativeRequest,
          firstReceivedTextMicros: _received,
          firstRenderedFrameMicros: _rendered,
        );
  void begin() {
    _started = readMonotonicMicros();
    _identity = Object();
    _received = null;
    _rendered = null;
    _nativeRequest = null;
    _eligible = true;
  }

  void receivedText() {
    if (!_eligible || _received != null) return;
    final elapsed = readMonotonicMicros() - _started;
    if (elapsed >= 0) _received = elapsed;
  }

  void bindNativeRequest(int value) {
    if (_identity != null) _nativeRequest = value;
  }

  bool recordFrame(Object identity) {
    if (!_eligible ||
        !identical(identity, _identity) ||
        _received == null ||
        _rendered != null)
      return false;
    final elapsed = readMonotonicMicros() - _started;
    if (elapsed < _received!) return false;
    _rendered = elapsed;
    return true;
  }

  void invalidate() => _eligible = false;
}
