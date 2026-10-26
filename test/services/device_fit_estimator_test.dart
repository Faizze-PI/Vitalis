import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/hub_model.dart';
import 'package:vitalis_app/services/device_fit_estimator.dart';

void main() {
  const estimator = DeviceFitEstimator();
  const variant = GgufVariant(
    repository: 'publisher/model',
    revision: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    displayName: 'model-Q4_K_M',
    files: [GgufFile(name: 'model.gguf', sizeBytes: 1000000000)],
  );

  HubModelSummary model(int? parameters) => HubModelSummary(
    id: 'publisher/model',
    revision: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    tags: const ['gguf'],
    downloads: 0,
    gated: false,
    parameterCount: parameters,
  );

  test('exactly 4B parameters is not the large-model warning boundary', () {
    final result = estimator.assess(
      model: model(4000000000),
      variant: variant,
      availableMemoryBytes: 8000000000,
      usableStorageBytes: 8000000000,
    );
    expect(result.requiresLargeModelWarning, isFalse);
  });

  test('more than 4B parameters requires a warning but is not blocked', () {
    final result = estimator.assess(
      model: model(4000000001),
      variant: variant,
      availableMemoryBytes: 8000000000,
      usableStorageBytes: 8000000000,
    );
    expect(result.requiresLargeModelWarning, isTrue);
    expect(result.level, DeviceFitLevel.likely);
  });

  test('insufficient storage is a hard incompatibility', () {
    final result = estimator.assess(
      model: model(1000000000),
      variant: variant,
      availableMemoryBytes: 8000000000,
      usableStorageBytes: 1500000000,
    );
    expect(result.level, DeviceFitLevel.insufficientDisk);
  });
}
