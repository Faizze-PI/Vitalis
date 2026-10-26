import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'embedding rejection leaves active real-model generation untouched',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final owner = LlamaCppChatRepository.withModelPath(
        path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      final competitor = LlamaCppChatRepository.withModelPath(path);
      addTearDown(() async {
        await owner.close();
        await competitor.close();
      });
      var exercised = false;
      var completions = 0;
      final output = StringBuffer();
      await for (final chunk in owner.streamChatWithGenerationOptions(
        'ownership-fixture',
        messages: [
          LLMMessage(role: LLMRole.user, content: 'Describe a garden briefly.'),
        ],
        generationOptions: const GenerationOptions(maxTokens: 32),
      )) {
        output.write(chunk.message?.content ?? '');
        if (!exercised && (chunk.message?.content ?? '').isNotEmpty) {
          exercised = true;
          final before = owner.operationSnapshot;
          for (final repository in [owner, competitor]) {
            await expectLater(
              repository.embed(model: 'fixture', messages: ['fixture']),
              throwsA(isA<InferenceCapabilityUnsupported>()),
            );
            await expectLater(
              repository.batchEmbed(model: 'fixture', messages: ['fixture']),
              throwsA(isA<InferenceCapabilityUnsupported>()),
            );
          }
          expect(owner.operationSnapshot.contextOwnerId, before.contextOwnerId);
          expect(
            owner.operationSnapshot.nativeRequestId,
            before.nativeRequestId,
          );
        }
        if (chunk.done == true) completions++;
      }
      expect(exercised, isTrue);
      expect(output, isNotEmpty);
      expect(completions, 1);
      expect(owner.lastMetrics?.generatedTokens, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
