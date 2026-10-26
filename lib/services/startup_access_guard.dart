import 'package:flutter/foundation.dart';
import '../models/startup_capabilities.dart';

enum StartupAccessOperation { browse, mutateContent, inference, recoverModels }

final class StartupAccessDenied extends StateError {
  StartupAccessDenied(this.operation)
    : super('Startup prerequisites unavailable (${operation.name})');
  final StartupAccessOperation operation;
}

/// Checks the current snapshot at admission, not a captured earlier permission.
/// Owned cleanup and already-admitted persistence must remain able to finish.
final class StartupAccessGuard {
  const StartupAccessGuard(this.snapshot, {this.changes});
  final StartupCapabilities Function() snapshot;
  final Listenable? changes;

  void require(StartupAccessOperation operation) {
    if (!allows(operation)) throw StartupAccessDenied(operation);
  }

  bool allows(StartupAccessOperation operation) {
    final current = snapshot();
    return switch (operation) {
      StartupAccessOperation.browse => current.canBrowse,
      StartupAccessOperation.mutateContent => current.canMutateContent,
      StartupAccessOperation.inference => current.canInfer,
      StartupAccessOperation.recoverModels => current.canRecoverModels,
    };
  }
}
