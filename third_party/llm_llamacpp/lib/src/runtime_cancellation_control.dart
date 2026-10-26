/// Transport bookkeeping only. RuntimeSessionReservation remains the single
/// authority for owner access, and native acknowledgement remains mandatory.
class RuntimeCancellationControl {
  RuntimeCancellationControl({
    required this.readMonotonicMicros,
    required this.requestCancel,
    required this.releaseHandle,
  });
  final int Function() readMonotonicMicros;
  final void Function(int) requestCancel;
  final void Function(int) releaseHandle;
  final _requests = <int>{};
  final _handles = <int, int>{};
  final _requestedAt = <int, int>{};

  int get retainedRequestCount => {..._requests, ..._requestedAt.keys}.length;
  bool isRequested(int requestId) => _requestedAt.containsKey(requestId);
  bool hasHandle(int requestId) => _handles.containsKey(requestId);
  void register(int requestId) {
    if (requestId < 0 || !_requests.add(requestId)) {
      throw ArgumentError('Invalid or duplicate runtime request identity');
    }
  }

  bool request(int requestId) {
    if (!_requests.contains(requestId)) return false;
    _requestedAt.putIfAbsent(requestId, readMonotonicMicros);
    final handle = _handles[requestId];
    if (handle != null) requestCancel(handle);
    return true;
  }

  bool attachHandle(int requestId, int address) {
    // Android arm64 heap tags may set the sign bit. Preserve every raw bit.
    if (address == 0) return false;
    if (!_requests.contains(requestId)) {
      releaseHandle(address);
      return false;
    }
    if (_handles.containsKey(requestId)) {
      // Each publication transfers a retained reference. Never replace the
      // original handle or write Stop into a competing context's address.
      releaseHandle(address);
      return false;
    }
    _handles[requestId] = address;
    if (isRequested(requestId)) requestCancel(address);
    return true;
  }

  int? finish(int requestId) {
    if (!_requests.contains(requestId)) return null;
    final started = _requestedAt[requestId];
    final elapsed = started == null ? null : readMonotonicMicros() - started;
    final address = _handles[requestId];
    if (address != null) releaseHandle(address);
    _handles.remove(requestId);
    _requests.remove(requestId);
    _requestedAt.remove(requestId);
    return elapsed;
  }

  void clear() {
    for (final requestId in _requests.toList()) {
      finish(requestId);
    }
  }
}
