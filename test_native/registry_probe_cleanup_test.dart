import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/services/model_verification_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'verification retains failed cleanup around a real context until recovery',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final lifecycle = ModelVerificationRuntime();
      final owner = _FailOnceOnCancel(path);
      final successor = LlamaCppChatRepository.withModelPath(
        path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      addTearDown(() async {
        if (lifecycle.requiresRecovery) await lifecycle.recoverOwnedCleanup();
        await lifecycle.close();
        await owner.close();
        await successor.close();
      });
      int? held;
      await expectLater(
        lifecycle.run(owner, () async {
          await owner.prepare();
          held = owner.operationSnapshot.contextOwnerId;
          expect(
            await owner.countChatTokens([
              LLMMessage(role: LLMRole.user, content: 'Verification fixture'),
            ]),
            greaterThan(0),
          );
        }),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      expect(lifecycle.requiresRecovery, isTrue);
      expect(owner.isDisposed, isTrue);
      expect(owner.operationSnapshot.contextOwnerId, held);
      await expectLater(
        successor.prepare(),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      expect(
        await lifecycle.recoverOwnedCleanup(),
        RuntimeRecoveryOutcome.recovered,
      );
      expect(lifecycle.requiresRecovery, isFalse);
      expect(owner.operationSnapshot.hasRetainedContext, isFalse);
      await successor.prepare();
      final output = StringBuffer();
      var completions = 0;
      await for (final chunk in successor.streamChatWithGenerationOptions(
        'verification-recovery-fixture',
        messages: [
          LLMMessage(role: LLMRole.user, content: 'Say hello briefly.'),
        ],
        generationOptions: const GenerationOptions(maxTokens: 16),
      )) {
        output.write(chunk.message?.content ?? '');
        if (chunk.done == true) completions++;
      }
      expect(output, isNotEmpty);
      expect(completions, 1);
      expect(successor.lastMetrics?.generatedTokens, greaterThan(0));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

// Injects a Dart control-adapter failure around a real native context. This is
// not a fault in llama.cpp or the native atomic cancellation bridge.
final class _FailOnceOnCancel extends LlamaCppChatRepository {
  _FailOnceOnCancel(String path)
    : super.withModelPath(path, contextSize: 2048, batchSize: 128, threads: 2);
  var _fail = true;

  @override
  Future<void> cancelActiveInference() async {
    if (_fail) {
      _fail = false;
      throw StateError('Controlled verification cancellation failure');
    }
    await super.cancelActiveInference();
  }
}
