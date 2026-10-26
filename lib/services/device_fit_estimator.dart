import '../models/hub_model.dart';
import '../models/model_library_policy.dart';

class DeviceFitEstimator {
  const DeviceFitEstimator();

  DeviceFitAssessment assess({
    required HubModelSummary model,
    required GgufVariant variant,
    required int? availableMemoryBytes,
    required int? usableStorageBytes,
  }) {
    final fileBytes = variant.totalBytes;
    final large = model.isLargeModel;
    if (fileBytes == null) {
      return DeviceFitAssessment(
        level: DeviceFitLevel.unknown,
        reason: 'The Hub did not report the complete file size.',
        estimatedMemoryBytes: null,
        requiresLargeModelWarning: large,
      );
    }
    final requiredStorage =
        (fileBytes * ModelLibraryPolicy.atomicInstallStorageMultiplier).ceil();
    if (usableStorageBytes != null && usableStorageBytes < requiredStorage) {
      return DeviceFitAssessment(
        level: DeviceFitLevel.insufficientDisk,
        reason: 'Not enough free storage for download and atomic validation.',
        estimatedMemoryBytes: null,
        requiresLargeModelWarning: large,
      );
    }
    final estimatedMemory =
        (fileBytes * ModelLibraryPolicy.runtimeFileMemoryMultiplier +
                ModelLibraryPolicy.runtimeMemoryOverheadBytes)
            .ceil();
    if (availableMemoryBytes == null) {
      return DeviceFitAssessment(
        level: large ? DeviceFitLevel.memoryRisk : DeviceFitLevel.unknown,
        reason:
            'Available memory is unknown; conservative settings will be used.',
        estimatedMemoryBytes: estimatedMemory,
        requiresLargeModelWarning: large,
      );
    }
    final ratio = estimatedMemory / availableMemoryBytes;
    final level = ratio > 0.9
        ? DeviceFitLevel.memoryRisk
        : ratio > 0.65
        ? DeviceFitLevel.slow
        : large
        ? DeviceFitLevel.likely
        : DeviceFitLevel.recommended;
    return DeviceFitAssessment(
      level: level,
      reason: switch (level) {
        DeviceFitLevel.memoryRisk =>
          'The model may exceed safely available memory.',
        DeviceFitLevel.slow =>
          'The model should run, but memory pressure or slower output is likely.',
        DeviceFitLevel.likely =>
          'The model appears to fit, but it is larger than 4B parameters.',
        _ => 'The selected quantization appears suitable for this device.',
      },
      estimatedMemoryBytes: estimatedMemory,
      requiresLargeModelWarning: large,
    );
  }
}
