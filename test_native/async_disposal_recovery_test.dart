import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'asynchronous disposal retains a failed control operation until owner recovery',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final owner = _FailOnceOnCancel(path);
      final successor = LlamaCppChatRepository.withModelPath(
        path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      addTearDown(() async {
        if (owner.cleanupFailed) await owner.recoverAfterClose();
        await owner.close();
        await successor.close();
      });
      await owner.prepare();
      final held = owner.operationSnapshot.contextOwnerId;
      owner.dispose();
      expect(owner.isDisposed, isTrue);
      await expectLater(owner.close(), throwsStateError);
      expect(owner.cleanupFailed, isTrue);
      expect(owner.operationSnapshot.requiresRecovery, isTrue);
      expect(owner.operationSnapshot.contextOwnerId, held);
      await expectLater(
        successor.prepare(),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      await expectLater(
        owner.prepare(),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );

      expect(await owner.recoverAfterClose(), RuntimeRecoveryOutcome.recovered);
      expect(owner.cleanupFailed, isFalse);
      expect(owner.operationSnapshot.hasRetainedContext, isFalse);
      await owner.close();
      await successor.prepare();
      final output = StringBuffer();
      var completed = 0;
      await for (final chunk in successor.streamChatWithGenerationOptions(
        'dispose-recovery-fixture',
        messages: [
          LLMMessage(role: LLMRole.user, content: 'Reply briefly: ready'),
        ],
        generationOptions: const GenerationOptions(maxTokens: 16),
      )) {
        output.write(chunk.message?.content ?? '');
        if (chunk.done == true) completed++;
      }
      expect(output, isNotEmpty);
      expect(completed, 1);
      expect(owner.isDisposed, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
  test(
    'owned legacy handle is retained after failed disposal and freed on recovery',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final owner = _FailOnceOwnedCancel();
      final successor = LlamaCppChatRepository.withModelPath(
        path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      addTearDown(() async {
        if (owner.cleanupFailed) await owner.recoverAfterClose();
        await owner.close();
        await successor.close();
      });
      final before = owner.operationSnapshot;
      await expectLater(owner.prepare(), throwsStateError);
      expect(owner.operationSnapshot.contextOwnerId, before.contextOwnerId);
      expect(owner.operationSnapshot.hasNativeWork, isFalse);
      await owner.loadModel(
        path,
        options: const ModelLoadOptions(vocabOnly: true),
      );
      final handle = owner.model!;
      final vocabulary = handle.vocabSize;
      await owner.prepare();
      owner.dispose();
      await expectLater(owner.close(), throwsStateError);
      expect(owner.cleanupFailed, isTrue);
      expect(owner.model, same(handle));
      expect(
        handle.vocabSize,
        vocabulary,
        reason: 'Failed shutdown must not free the local owned handle',
      );
      await expectLater(
        successor.prepare(),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      expect(await owner.recoverAfterClose(), RuntimeRecoveryOutcome.recovered);
      expect(owner.model, isNull);
      expect(owner.cleanupFailed, isFalse);
      expect(
        () => handle.vocabSize,
        throwsStateError,
        reason: 'Confirmed recovery must dispose the directly owned handle',
      );
      await successor.prepare();
      expect(
        await successor.countChatTokens([
          LLMMessage(role: LLMRole.user, content: 'Ready after owned recovery'),
        ]),
        greaterThan(0),
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

// Simulated control-adapter failure around a real loaded native context. This
// does not claim a fault was injected into the native cancellation bridge.
class _FailOnceOnCancel extends LlamaCppChatRepository {
  _FailOnceOnCancel(String path)
    : super.withModelPath(path, contextSize: 2048, batchSize: 128, threads: 2);
  var _fail = true;
  @override
  Future<void> cancelActiveInference() async {
    if (_fail) {
      _fail = false;
      throw StateError('Simulated cancellation transport failure');
    }
    await super.cancelActiveInference();
  }
}

class _FailOnceOwnedCancel extends LlamaCppChatRepository {
  _FailOnceOwnedCancel() : super(contextSize: 2048, batchSize: 128, threads: 2);
  var _fail = true;
  @override
  Future<void> cancelActiveInference() async {
    if (_fail) {
      _fail = false;
      throw StateError('Simulated owned cancellation transport failure');
    }
    await super.cancelActiveInference();
  }
}
