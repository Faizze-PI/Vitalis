import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';

// Registered by the mandatory owner/close native suite; never a skipped fixture.
void registerPreparationCancellationCases() {
  test(
    'Stop during backend initialization prevents model preparation',
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
      try {
        final preparing = owner.prepare();
        final observedPreparation = expectLater(
          preparing,
          throwsA(isA<InferencePreparationCancelled>()),
        );
        expect(owner.operationSnapshot.initializationPending, isTrue);
        expect(owner.operationSnapshot.nativeRequestId, isNotNull);

        final stopping = owner.cancelActiveInference();
        expect(owner.operationSnapshot.cancellationRequested, isTrue);
        await stopping;
        await observedPreparation;
        expect(owner.operationSnapshot.initializationPending, isFalse);
        expect(owner.operationSnapshot.cancellationHandleAvailable, isFalse);

        // Backend startup remains reusable, while the cancelled model load was
        // never started. The same owner can now prepare and generate normally.
        await owner.prepare();
        await for (final _ in owner.streamChatWithGenerationOptions(
          'after-backend-startup-stop',
          messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
          generationOptions: const GenerationOptions(maxTokens: 16),
        )) {}
        expect(owner.lastMetrics?.generatedTokens, greaterThan(0));
      } finally {
        await owner.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'explicit Stop after preparation handle publication terminates loading',
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
      final preparing = owner.prepare();
      final observedPreparation = expectLater(
        preparing,
        throwsA(isA<InferencePreparationCancelled>()),
      );
      try {
        final clock = Stopwatch()..start();
        while ((owner.operationSnapshot.nativeRequestId == null ||
                !owner.operationSnapshot.cancellationHandleAvailable) &&
            clock.elapsed < const Duration(seconds: 30)) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(owner.operationSnapshot.initializationPending, isTrue);
        expect(owner.operationSnapshot.nativeRequestId, isNotNull);
        expect(owner.operationSnapshot.cancellationHandleAvailable, isTrue);
        final stopping = owner.cancelActiveInference();
        final observedStop = stopping.then<void>(
          (_) {},
          onError: (Object _, StackTrace __) {},
        );
        try {
          expect(owner.operationSnapshot.cancellationRequested, isTrue);
        } finally {
          await observedStop;
          await stopping;
        }
        await observedPreparation;
        expect(owner.operationSnapshot.initializationPending, isFalse);
        // The receipt proves termination, but retained context quarantine must
        // remain visible until the owning unload acknowledges cleanup.
        expect(owner.operationSnapshot.hasNativeWork, isTrue);
        expect(owner.operationSnapshot.requiresRecovery, isTrue);
      } finally {
        await owner.close();
        await observedPreparation;
        expect(owner.operationSnapshot.hasNativeWork, isFalse);
      }
      final next = LlamaCppChatRepository.withModelPath(
        path,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      try {
        await next.prepare();
        await for (final _ in next.streamChatWithGenerationOptions(
          'after-preparation-stop',
          messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
          generationOptions: const GenerationOptions(maxTokens: 16),
        )) {}
        expect(next.lastMetrics?.generatedTokens, greaterThan(0));
      } finally {
        await next.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  test(
    'Stop addresses retained native preparation',
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
        preparationWatchdogPolicy: const RuntimeWatchdogPolicy(
          noProgressTimeout: Duration.zero,
          maximumDuration: Duration.zero,
        ),
      );
      try {
        await expectLater(
          owner.prepare(),
          throwsA(isA<InferenceRecoveryRequired>()),
        );
        expect(owner.operationSnapshot.initializationPending, isTrue);
        expect(owner.operationSnapshot.nativeRequestId, isNotNull);
        final stopping = owner.cancelActiveInference();
        // Observe Stop independently from later preparation completion/unload.
        final observed = stopping.then<void>(
          (_) {},
          onError: (Object _, StackTrace __) {},
        );
        try {
          expect(
            owner.operationSnapshot.cancellationRequested,
            isTrue,
            reason: 'Stop must address preparation, not return as a no-op',
          );
        } finally {
          await observed;
        }
      } finally {
        await owner.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
