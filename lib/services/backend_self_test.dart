import '../models/runtime_profile.dart';
import 'runtime_auto_tuner.dart';

class BackendSelfTestResult {
  const BackendSelfTestResult({
    required this.passed,
    required this.backend,
    required this.offloadedLayers,
    this.failureReason,
  });

  final bool passed;
  final String backend;
  final int offloadedLayers;
  final String? failureReason;
}

typedef BackendProbe =
    Future<RuntimeBenchmarkResult> Function(
      RuntimeProfile profile,
      TuningCancellationToken cancellation,
    );

class BackendSelfTest {
  const BackendSelfTest();

  Future<BackendSelfTestResult> run({
    required String backend,
    required RuntimeProfile cpuProfile,
    required int modelLayerCount,
    required BackendProbe probe,
    required TuningCancellationToken cancellation,
  }) async {
    if (backend != 'vulkan') {
      return const BackendSelfTestResult(
        passed: true,
        backend: 'cpu',
        offloadedLayers: 0,
      );
    }
    final candidates = <int>{
      (modelLayerCount / 4).ceil(),
      (modelLayerCount / 2).ceil(),
      modelLayerCount,
    }.where((layers) => layers > 0).toList()..sort();
    RuntimeBenchmarkResult? best;
    for (final layers in candidates) {
      cancellation.throwIfCancelled();
      try {
        final result = await probe(
          cpuProfile.copyWith(gpuLayers: layers),
          cancellation,
        );
        if (result.safe && result.generatedTokens >= 32) best = result;
      } catch (_) {
        break;
      }
    }
    if (best == null) {
      return const BackendSelfTestResult(
        passed: false,
        backend: 'vulkan',
        offloadedLayers: 0,
        failureReason: 'Vulkan load/inference/cancellation self-test failed',
      );
    }
    return BackendSelfTestResult(
      passed: true,
      backend: 'vulkan',
      offloadedLayers: best.profile.gpuLayers,
    );
  }
}
