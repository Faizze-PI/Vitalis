import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/persistent_inference_isolate.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cold tokenization Stop waits for helper and allows a later tokenization',
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

      final tokenization = repository.countChatTokens([
        LLMMessage(role: LLMRole.user, content: 'cold tokenization'),
      ]);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline) &&
          !(repository.operationSnapshot.initializationPending &&
              repository.operationSnapshot.nativeRequestId != null)) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final duringInitialization = repository.operationSnapshot;
      expect(duringInitialization.initializationPending, isTrue);
      expect(duringInitialization.nativeRequestId, isNotNull);
      expect(duringInitialization.kind, RuntimeOperationKind.interactive);

      final cancelledTokenization = expectLater(
        tokenization,
        throwsA(isA<InferencePreparationCancelled>()),
      );
      await repository.cancelActiveInference().timeout(
        const Duration(seconds: 30),
      );
      await cancelledTokenization;
      expect(repository.operationSnapshot.hasNativeWork, isFalse);

      await repository.prepare();
      final count = await repository.countChatTokens([
        LLMMessage(role: LLMRole.user, content: 'tokenization after stop'),
      ]);
      expect(count, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
