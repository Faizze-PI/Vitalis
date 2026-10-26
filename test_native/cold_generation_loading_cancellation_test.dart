import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/persistent_inference_isolate.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cold generation exposes cancellation before native model loading',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final repository = LlamaCppChatRepository.withModelPath(
        path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      addTearDown(() async {
        await repository.close();
        PersistentInferenceIsolate.instance.dispose();
      });
      bool? handleAtLoading;
      Future<void>? stopping;
      await for (final event in repository.streamChatWithGenerationOptions(
        'cold-loading-stop',
        messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
        generationOptions: const GenerationOptions(maxTokens: 1),
      )) {
        if (event is LlamaCppProgressChunk &&
            event.progress.phase == RuntimeProgressPhase.modelLoading &&
            event.progress.completedUnits == 0) {
          handleAtLoading =
              repository.operationSnapshot.cancellationHandleAvailable;
          stopping = repository.cancelActiveInference();
        }
      }
      await stopping;
      expect(
        handleAtLoading,
        isTrue,
        reason:
            'Stop needs a native handle while model loading blocks the helper',
      );
      expect(repository.lastMetrics?.completionReason, 'cancelled');
      expect(repository.lastMetrics?.promptTokens, 0);
      expect(repository.lastMetrics?.generatedTokens, 0);
      await repository.prepare();
      await for (final _ in repository.streamChatWithGenerationOptions(
        'after-cold-loading-stop',
        messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
        generationOptions: const GenerationOptions(maxTokens: 1),
      )) {}
      expect(repository.lastMetrics?.generatedTokens, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
