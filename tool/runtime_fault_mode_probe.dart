import 'package:llm_llamacpp/src/runtime_cleanup_fault.dart';

/// Compile separately under debug/product/profile defines to verify the
/// test-only switch cannot enable fault dispatch in delivery modes.
void main(List<String> arguments) {
  if (arguments.length != 1 || !['true', 'false'].contains(arguments.single)) {
    throw ArgumentError('Expected one boolean fault-mode expectation');
  }
  final expected = arguments.single == 'true';
  if (RuntimeCleanupFault.enabled != expected) {
    const requested = bool.fromEnvironment('VITALIS_RUNTIME_FAULT_TESTS');
    const product = bool.fromEnvironment('dart.vm.product');
    const profile = bool.fromEnvironment('dart.vm.profile');
    throw StateError(
      'Compiled fault mode differs: requested=$requested product=$product '
      'profile=$profile expected=$expected',
    );
  }
}
