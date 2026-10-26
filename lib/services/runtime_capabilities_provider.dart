import 'dart:io';

import 'package:flutter/services.dart';

import '../models/runtime_capabilities.dart';

abstract interface class RuntimeCapabilitiesProvider {
  Future<RuntimeCapabilities> snapshot();
}

class AndroidRuntimeCapabilitiesProvider
    implements RuntimeCapabilitiesProvider {
  const AndroidRuntimeCapabilitiesProvider({
    MethodChannel? channel,
    bool? isAndroid,
    int? logicalProcessors,
  }) : _channel = channel ?? const MethodChannel('vitalis/device_safety'),
       _isAndroid = isAndroid,
       _logicalProcessors = logicalProcessors;

  final MethodChannel _channel;
  final bool? _isAndroid;
  final int? _logicalProcessors;

  @override
  Future<RuntimeCapabilities> snapshot() async {
    if (!(_isAndroid ?? (Platform.isAndroid || Platform.isWindows))) {
      return conservativeDesktopCapabilities();
    }
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>('snapshot');
      if (value == null) return conservativeDesktopCapabilities();
      return parseAndroidRuntimeCapabilities(
        value,
        fallbackLogicalProcessors:
            _logicalProcessors ?? Platform.numberOfProcessors,
      );
    } on PlatformException {
      return conservativeDesktopCapabilities();
    } on MissingPluginException {
      return conservativeDesktopCapabilities();
    }
  }

  RuntimeCapabilities conservativeDesktopCapabilities() => RuntimeCapabilities(
    logicalProcessors: (_logicalProcessors ?? Platform.numberOfProcessors)
        .clamp(1, 32),
    performanceProcessors: null,
    deviceFingerprint: '${Platform.operatingSystem}-unknown',
    abis: const [],
    packagedBackends: const {'cpu'},
  );
}

RuntimeCapabilities parseAndroidRuntimeCapabilities(
  Map<String, dynamic> value, {
  required int fallbackLogicalProcessors,
}) => RuntimeCapabilities(
  logicalProcessors:
      value['logicalProcessors'] as int? ?? fallbackLogicalProcessors,
  performanceProcessors: value['performanceProcessors'] as int?,
  deviceFingerprint: value['deviceFingerprint'] as String? ?? 'android-unknown',
  abis: (value['supportedAbis'] as List?)?.cast<String>() ?? const [],
  packagedBackends:
      (value['packagedBackends'] as List?)?.cast<String>().toSet() ??
      const {'cpu'},
  availableMemoryBytes: value['availableMemoryBytes'] as int?,
  totalMemoryBytes: value['totalMemoryBytes'] as int?,
  processRssBytes: value['processRssBytes'] as int?,
  thermalStatus: value['thermalStatus'] as int?,
  lowMemory: value['lowMemory'] as bool?,
);
