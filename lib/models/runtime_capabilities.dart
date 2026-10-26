import 'dart:convert';

class RuntimeCapabilities {
  const RuntimeCapabilities({
    required this.logicalProcessors,
    this.performanceProcessors,
    required this.deviceFingerprint,
    required this.abis,
    required this.packagedBackends,
    this.availableMemoryBytes,
    this.totalMemoryBytes,
    this.processRssBytes,
    this.thermalStatus,
    this.lowMemory,
  });

  final int logicalProcessors;
  final int? performanceProcessors;
  final String deviceFingerprint;
  final List<String> abis;
  final Set<String> packagedBackends;
  final int? availableMemoryBytes;
  final int? totalMemoryBytes;
  final int? processRssBytes;
  final int? thermalStatus;
  final bool? lowMemory;

  bool get hasKnownSafeTelemetry =>
      availableMemoryBytes != null &&
      thermalStatus != null &&
      lowMemory != null &&
      performanceProcessors != null;

  bool get isSevere =>
      thermalStatus != null && thermalStatus! >= 3 || lowMemory == true;

  bool supportsBackend(String backend) => packagedBackends.contains(backend);
}

class RuntimeProfileKey {
  const RuntimeProfileKey({
    required this.appVersion,
    required this.modelSha256,
    required this.deviceFingerprint,
    required this.backendVersion,
    required this.backend,
    required this.templateFingerprint,
  });

  final String appVersion;
  final String modelSha256;
  final String deviceFingerprint;
  final String backendVersion;
  final String backend;
  final String templateFingerprint;

  String get storageKey => base64Url.encode(
    utf8.encode(
      [
        appVersion,
        modelSha256,
        deviceFingerprint,
        backendVersion,
        backend,
        templateFingerprint,
      ].join('|'),
    ),
  );
}
