import 'dart:async';
import 'dart:io';

import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:test/test.dart';

import 'verified_model_fixture.dart';

void main() {
  late final String modelPath;
  late final LlamaCppChatRepository runtime;
  LlamaCppChatRepository? cleanupOwner;

  setUpAll(() async {
    NativeLog.sink = (level, message) => stderr.writeln('$level: $message');
    modelPath = await verifiedModelFixture();
    runtime = LlamaCppChatRepository.withModelPath(
      modelPath,
      contextSize: 2048,
      batchSize: 128,
      threads: 2,
      supportsThinkingControl: true,
    );
    cleanupOwner = runtime;
    await runtime.prepare();
  });

  tearDownAll(() async {
    try {
      await cleanupOwner?.close();
    } finally {
      NativeLog.sink = null;
    }
  });

  test('tokenizes through the prepared native text context', () async {
    final count = await runtime.countChatTokens([
      LLMMessage(role: LLMRole.user, content: 'VITALIS tokenizer gate'),
    ]);
    expect(count, greaterThan(0));
  });

  test(
    'reuses process backend across 25 model load and unload cycles',
    () async {
      final loader = LlamaCppModelLoader();
      try {
        for (var cycle = 0; cycle < 25; cycle++) {
          final model = await loader.loadModel(
            modelPath,
            options: const ModelLoadOptions(vocabOnly: true),
          );
          expect(model.vocabSize, greaterThan(0), reason: 'cycle $cycle');
          loader.unloadModel(modelPath, force: true);
        }
      } finally {
        loader.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'generates visible text and authoritative completion metrics',
    () async {
      final output = StringBuffer();
      var completed = false;
      await for (final chunk in runtime.streamChatWithGenerationOptions(
        'bundled-qwen',
        messages: [
          LLMMessage(
            role: LLMRole.user,
            content: 'Reply with exactly: VITALIS NATIVE PASS',
          ),
        ],
        generationOptions: const GenerationOptions(maxTokens: 32),
      )) {
        output.write(chunk.message?.content ?? '');
        completed |= chunk.done == true;
      }
      expect(output, isNotEmpty);
      expect(completed, isTrue);
      expect(runtime.lastMetrics, isNotNull);
      expect(runtime.lastMetrics!.promptTokens, greaterThan(0));
      expect(runtime.lastMetrics!.generatedTokens, greaterThan(0));
      expect(runtime.lastMetrics!.completionReason, isNot('error'));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'acknowledged cancellation returns ready for the next request',
    () async {
      final firstVisible = Completer<void>();
      final streamDone = Completer<void>();
      runtime
          .streamChatWithGenerationOptions(
            'bundled-qwen',
            messages: [
              LLMMessage(
                role: LLMRole.user,
                content:
                    'Write a detailed numbered list with at least 100 items.',
              ),
            ],
            generationOptions: const GenerationOptions(maxTokens: 512),
          )
          .listen(
            (chunk) {
              if (!firstVisible.isCompleted &&
                  (chunk.message?.content?.isNotEmpty ?? false)) {
                firstVisible.complete();
              }
            },
            onError: streamDone.completeError,
            onDone: streamDone.complete,
          );

      await firstVisible.future.timeout(const Duration(minutes: 2));
      await runtime.cancelActiveInference().timeout(const Duration(seconds: 2));
      await streamDone.future.timeout(const Duration(seconds: 2));
      expect(runtime.lastMetrics?.completionReason, 'cancelled');
      expect(
        runtime.lastMetrics?.cancellationAcknowledgementMicros,
        inInclusiveRange(1, const Duration(seconds: 2).inMicroseconds),
      );

      final recovery = StringBuffer();
      await for (final chunk in runtime.streamChatWithGenerationOptions(
        'bundled-qwen',
        messages: [
          LLMMessage(role: LLMRole.user, content: 'Reply with: READY'),
        ],
        generationOptions: const GenerationOptions(maxTokens: 16),
      )) {
        recovery.write(chunk.message?.content ?? '');
      }
      expect(recovery, isNotEmpty);
      expect(runtime.lastMetrics?.completionReason, isNot('cancelled'));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
