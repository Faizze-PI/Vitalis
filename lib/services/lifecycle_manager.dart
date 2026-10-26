// FILE: lib/services/lifecycle_manager.dart
// PURPOSE: Abstract interface for disposable, leak-tracked resources
// STATUS: PRODUCTION-HARDENED

/// Contract for any service that holds native resources (isolates, ports,
/// stream subscriptions) and must be torn down explicitly.
abstract class LifecycleManager {
  bool get isDisposed;

  /// Releases all held resources. Idempotent — safe to call multiple times.
  void dispose();
}
