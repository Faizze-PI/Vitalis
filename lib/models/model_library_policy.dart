abstract final class ModelLibraryPolicy {
  static const int downloadJobEntropyBytes = 16; // hardcode: HC-049
  static const int largeModelParameterThreshold =
      4000000000; // hardcode: HC-029
  static const double downloadStorageHeadroom = 1.15; // hardcode: HC-026
  static const double atomicInstallStorageMultiplier = 2.15; // hardcode: HC-026
  static const double runtimeFileMemoryMultiplier = 1.25; // hardcode: HC-024
  static const int runtimeMemoryOverheadBytes = 768 * 1024 * 1024;
  static const int maximumTransferAttempts = 4; // hardcode: HC-026
  static const int maximumRetryAfterSeconds = 60; // hardcode: HC-026
  static const List<int> bundledRetryBackoffSeconds = [2, 4, 8, 16];
}

/// Canonical immutable Hugging Face artifact URL accepted by every transfer
/// adapter. Initial URLs are deliberately query-free so credentials and other
/// mutable request state can never enter a durable manifest.
abstract final class HubArtifactUriPolicy {
  static Uri resolve({
    required String repository,
    required String revision,
    required String artifactName,
  }) => Uri(
    scheme: 'https',
    host: 'huggingface.co',
    pathSegments: [
      ...repository.split('/'),
      'resolve',
      revision,
      ...artifactName.split('/'),
    ],
  );
}

abstract final class CompatibilityProbePolicy {
  static const Duration generationDeadline = Duration(
    seconds: 30,
  ); // hardcode: HC-024
  static const int maximumContextTokens = 4096; // hardcode: HC-024
  static const int reservedOutputTokens = 64; // hardcode: HC-024
  static const int conservativeBatchSize = 64; // hardcode: HC-024
  static const int knownSafeBatchSize = 128; // hardcode: HC-024
  static const int maximumThreads = 4; // hardcode: HC-024
}
