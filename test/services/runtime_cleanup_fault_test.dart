import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/src/runtime_cleanup_fault.dart';
import 'package:llm_llamacpp/src/runtime_request_finalizer.dart';
import 'package:llm_llamacpp/src/persistent_inference_isolate.dart';
import 'package:llm_llamacpp/src/generation_options.dart';

void main() {
  test(
    'ordinary builds reject fault dispatch before claiming a context',
    () async {
      expect(RuntimeCleanupFault.enabled, isFalse);
      final runtime = PersistentInferenceIsolate.instance;
      final before = runtime.operationSnapshot;
      const fault = RuntimeCleanupFault(
        step: RuntimeCleanupStep.sampler,
        failures: 1,
      );
      expect(fault.validate, throwsUnsupportedError);
      expect(
        () => RuntimeCleanupFaultController(fault),
        throwsUnsupportedError,
      );
      await expectLater(
        runtime
            .runInference(
              modelPath: 'unused-by-rejected-fault',
              prompt: '',
              stopTokens: const [],
              contextSize: 1,
              batchSize: 1,
              nGpuLayers: 0,
              options: const GenerationOptions(maxTokens: 1),
              cleanupFault: fault,
            )
            .drain<void>(),
        throwsUnsupportedError,
      );
      expect(runtime.operationSnapshot.contextOwnerId, before.contextOwnerId);
      expect(runtime.operationSnapshot.hasNativeWork, before.hasNativeWork);
    },
  );

  test('ordinary cleanup has no injected faults', () {
    final controller = RuntimeCleanupFaultController(null);
    for (final step in RuntimeCleanupStep.values) {
      expect(() => controller.beforeCleanup(step), returnsNormally);
    }
  });
}
