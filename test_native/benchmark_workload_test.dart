import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/isolate_messages.dart'
    show InferenceCompletionReason;
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/services/runtime_benchmark_workload.dart';

void main() {
  for (final supportsThinkingControl in [false, true]) {
    test(
      'native benchmark counts and evaluates exactly 256 prompt tokens (control: $supportsThinkingControl)',
      () async {
        final path = Platform.environment['VITALIS_TEST_MODEL'];
        expect(path, isNotNull, reason: 'Verified native fixture is mandatory');
        final file = File(path!);
        expect(await file.exists(), isTrue);
        expect(
          (await sha256.bind(file.openRead()).first).toString(),
          BundledModelManifest.sha256,
        );
        final repository = LlamaCppChatRepository.withModelPath(
          path,
          contextSize: 2048,
          batchSize: 128,
          threads: 2,
          promptThreads: 2,
          supportsThinkingControl: supportsThinkingControl,
        );
        addTearDown(repository.close);
        await repository.prepare();
        var queries = 0;
        final workload = await RuntimeBenchmarkWorkload.create(
          contextSize: repository.contextSize,
          checkCurrent: () {},
          countPromptTokens: (prompt) {
            queries++;
            return repository.countChatTokens([
              LLMMessage(role: LLMRole.user, content: prompt),
            ], think: false);
          },
        );
        await for (final _ in repository.streamChatWithGenerationOptions(
          'fixed-benchmark-fixture',
          messages: [LLMMessage(role: LLMRole.user, content: workload.prompt)],
          think: false,
          generationOptions: const GenerationOptions(
            maxTokens: RuntimeBenchmarkPolicy.outputTokens,
          ),
        )) {}
        final metrics = repository.lastMetrics!;
        expect(metrics.promptTokens, RuntimeBenchmarkPolicy.promptTokens);
        expect(metrics.generatedTokens, RuntimeBenchmarkPolicy.outputTokens);
        expect(
          metrics.completionReason,
          InferenceCompletionReason.outputLimit.name,
        );
        expect(metrics.promptEvalMicros, greaterThan(0));
        stdout.writeln(
          'NATIVE_BENCHMARK_WORKLOAD:${jsonEncode({'template_control_path': supportsThinkingControl, 'prompt_tokens': metrics.promptTokens, 'tokenizer_queries': queries, 'generated_tokens': metrics.generatedTokens, 'prompt_eval_micros': metrics.promptEvalMicros})}',
        );
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }
}
