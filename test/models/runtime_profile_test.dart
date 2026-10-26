import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/constants/app_constants.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/model_descriptor.dart';
import 'package:vitalis_app/models/runtime_capabilities.dart';
import 'package:vitalis_app/models/runtime_profile.dart';

void main() {
  test('automatic profile keeps one CPU free and remains bounded', () {
    final profile = RuntimeProfile.forSettings(
      ModelSettings(),
      processorCount: 12,
    );
    expect(profile.generationThreads, 11);
    expect(profile.promptThreads, 11);
    expect(profile.contextSize, AppConstants.defaultContextSize);
    expect(profile.gpuLayers, 0);
  });

  test('advanced overrides are clamped and unavailable GPU stays off', () {
    final profile = RuntimeProfile.forSettings(
      ModelSettings(
        contextSizeOverride: 1,
        generationThreadsOverride: 100,
        promptThreadsOverride: 0,
        batchSizeOverride: 99999,
        accelerationPreference: AccelerationPreference.experimentalGpu,
      ),
      processorCount: 1,
    );
    expect(profile.contextSize, AppConstants.minimumContextSize);
    expect(profile.generationThreads, 1);
    expect(profile.promptThreads, 1);
    expect(profile.batchSize, AppConstants.nativeMaximumBatchSize);
    expect(profile.gpuLayers, 0);
  });

  test('compatibility probe is conservative when telemetry is unknown', () {
    final profile = RuntimeProfile.forCompatibilityProbe(
      const ModelDescriptor(
        id: 'model',
        displayName: 'Model',
        source: 'test',
        compatibilityStatus: 'unknown',
        contextTrain: 32768,
      ),
      const RuntimeCapabilities(
        logicalProcessors: 12,
        deviceFingerprint: 'unknown',
        abis: [],
        packagedBackends: {'cpu'},
      ),
    );
    expect(profile.contextSize, 4096);
    expect(profile.batchSize, 64);
    expect(profile.generationThreads, 1);
    expect(profile.gpuLayers, 0);
  });

  test('compatibility probe honors model and memory limits', () {
    final profile = RuntimeProfile.forCompatibilityProbe(
      const ModelDescriptor(
        id: 'model',
        displayName: 'Model',
        source: 'test',
        compatibilityStatus: 'unknown',
        contextTrain: 2048,
      ),
      const RuntimeCapabilities(
        logicalProcessors: 8,
        performanceProcessors: 4,
        deviceFingerprint: 'device',
        abis: ['arm64-v8a'],
        packagedBackends: {'cpu'},
        availableMemoryBytes: 8 * 1024 * 1024 * 1024,
        thermalStatus: 0,
        lowMemory: false,
      ),
    );
    expect(profile.contextSize, 2048);
    expect(profile.batchSize, 128);
    expect(profile.generationThreads, 4);
  });
}
