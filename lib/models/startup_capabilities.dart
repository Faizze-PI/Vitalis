/// Model verification is independent of database and device-safety readiness.
enum StartupModelReadiness { unknown, checking, missing, invalid, ready }

/// Immutable permissions derived from established startup prerequisites.
/// UI presentation is secondary: providers must enforce these permissions too.
final class StartupCapabilities {
  const StartupCapabilities({
    required this.databaseReady,
    required this.migrationReady,
    required this.safetyReady,
    required this.modelReadiness,
    this.disposed = false,
  });

  final bool databaseReady;
  final bool migrationReady;
  final bool safetyReady;
  final StartupModelReadiness modelReadiness;
  final bool disposed;

  bool get canBrowse => !disposed && databaseReady && migrationReady;
  bool get canRecoverModels => canBrowse;
  bool get canInfer =>
      canBrowse && safetyReady && modelReadiness == StartupModelReadiness.ready;
  bool get canMutateContent => canInfer;
  bool get readOnly => canBrowse && !canMutateContent;

  StartupCapabilities withModelReadiness(StartupModelReadiness readiness) =>
      StartupCapabilities(
        databaseReady: databaseReady,
        migrationReady: migrationReady,
        safetyReady: safetyReady,
        modelReadiness: readiness,
        disposed: disposed,
      );
}
