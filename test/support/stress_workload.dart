/// Owns a stress scenario until fixture cleanup acknowledges its completion.
class StressWorkload {
  Future<void>? _active;

  Future<void> run(Future<void> Function() body) {
    if (_active != null) throw StateError('Stress workload is still owned');
    return _active = Future<void>.sync(body);
  }

  /// The original test observes its error; cleanup also receives that outcome.
  /// A waiter timing out never makes the underlying work safe to abandon.
  Future<Object?> settle() async {
    final pending = _active;
    if (pending == null) return null;
    try {
      await pending;
      return null;
    } catch (error) {
      return error;
    } finally {
      if (identical(_active, pending)) _active = null;
    }
  }
}
