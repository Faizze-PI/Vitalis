enum RuntimeCleanupStep {
  sampler,
  promptAllocation,
  adapter,
  cache,
  cancellation,
}

enum RuntimeCleanupOutcome { confirmed, recoveryRequired }

/// Request-local cleanup only; the runtime reservation owns access.
class RuntimeRequestFinalizer {
  RuntimeRequestFinalizer({required this.publish});
  final void Function(Object) publish;
  final _steps = <RuntimeCleanupStep, void Function()>{};
  Object? _terminal;
  bool _published = false;
  bool _finishing = false;
  RuntimeCleanupStep? failedStep;

  bool get isConfirmed => _published;
  int get pendingStepCount => _steps.length;

  RuntimeCleanupOutcome retry() {
    final terminal = _terminal;
    if (terminal == null)
      throw StateError('No native cleanup outcome to retry');
    return finish(terminal);
  }

  void add(RuntimeCleanupStep step, void Function() cleanup) {
    if (_terminal != null || _steps.containsKey(step)) {
      throw StateError('Invalid native cleanup registration');
    }
    _steps[step] = cleanup;
  }

  RuntimeCleanupOutcome finish(Object terminal) {
    if (_published) return RuntimeCleanupOutcome.confirmed;
    if (_finishing) return RuntimeCleanupOutcome.recoveryRequired;
    _terminal ??= terminal;
    failedStep = null;
    _finishing = true;
    try {
      for (final step in _steps.keys.toList()) {
        try {
          _steps[step]!();
          _steps.remove(step);
        } catch (_) {
          failedStep = step;
          return RuntimeCleanupOutcome.recoveryRequired;
        }
      }
      try {
        publish(_terminal!);
      } catch (_) {
        // Publication failure is not evidence that the receiver acknowledged.
        return RuntimeCleanupOutcome.recoveryRequired;
      }
      _published = true;
      return RuntimeCleanupOutcome.confirmed;
    } finally {
      _finishing = false;
    }
  }
}
