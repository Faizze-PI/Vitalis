/// Retained transport records, not a second runtime ownership lock.
/// Only an acknowledged owner unload may retire these handle references.
class RuntimeCleanupQuarantine {
  RuntimeCleanupQuarantine({required this.releaseHandle});
  final void Function(int) releaseHandle;
  final _owners = <int, Object?>{};

  bool get hasRequests => _owners.isNotEmpty;
  int? get firstRequestId => _owners.isEmpty ? null : _owners.keys.first;
  bool contains(int requestId) => _owners.containsKey(requestId);
  bool canAccess(Object? owner) =>
      _owners.values.every((candidate) => identical(candidate, owner));

  void retain(int requestId, Object? owner) {
    if (requestId < 0 ||
        (_owners.containsKey(requestId) &&
            !identical(_owners[requestId], owner))) {
      throw StateError('Invalid retained native cleanup identity');
    }
    _owners[requestId] = owner;
  }

  List<int> confirmOwnerUnload(Object? owner) {
    final retired = <int>[];
    for (final requestId in _owners.keys.toList()) {
      if (!identical(_owners[requestId], owner)) continue;
      releaseHandle(requestId);
      _owners.remove(requestId);
      retired.add(requestId);
    }
    return retired;
  }
}
