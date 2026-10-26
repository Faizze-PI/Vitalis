import 'package:llm_llamacpp/src/runtime_request_finalizer.dart';

/// Explicit fault injection for the product native test gate only.
/// Normal builds cannot dispatch faults, even through the internal API.
final class RuntimeCleanupFault {
  const RuntimeCleanupFault({required this.step, required this.failures});
  // hardcode: HC-047. Explicit test-only compile mode; false in normal builds.
  static const enabled =
      bool.fromEnvironment('VITALIS_RUNTIME_FAULT_TESTS') &&
      !bool.fromEnvironment('dart.vm.product') &&
      !bool.fromEnvironment('dart.vm.profile');
  final RuntimeCleanupStep step;
  final int failures;

  void validate() {
    if (!enabled) throw UnsupportedError('Native fault tests are disabled');
    if (failures <= 0) throw ArgumentError('Fault count must be positive');
  }
}

/// Lives in the helper request, not in process-global state.
final class RuntimeCleanupFaultController {
  RuntimeCleanupFaultController(RuntimeCleanupFault? fault)
    : _fault = fault,
      _remaining = fault?.failures ?? 0 {
    fault?.validate();
  }
  final RuntimeCleanupFault? _fault;
  int _remaining;

  void beforeCleanup(RuntimeCleanupStep step) {
    if (_fault?.step != step || _remaining == 0) return;
    _remaining--;
    throw StateError('Injected native cleanup failure: ${step.name}');
  }
}
