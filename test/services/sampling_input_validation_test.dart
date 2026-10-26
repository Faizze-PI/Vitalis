import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/src/generation_options.dart';
import 'package:llm_llamacpp/src/persistent_inference_isolate.dart';

void main() {
  final cases = <String, GenerationOptions>{
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
      1e300,
      -1e300,
    ])
      'temperature $value': GenerationOptions(temperature: value),
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
      -0.01,
      1.01,
    ])
      'topP $value': GenerationOptions(topP: value),
    'topK int32 overflow': const GenerationOptions(topK: 2147483648),
    'topK int32 underflow': const GenerationOptions(topK: -2147483649),
    'seed negative': const GenerationOptions(seed: -1),
    'seed uint32 overflow': const GenerationOptions(seed: 4294967296),
    'zero output': const GenerationOptions(maxTokens: 0),
    'negative output': const GenerationOptions(maxTokens: -1),
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
      1e300,
    ])
      'frequency $value': GenerationOptions(frequencyPenalty: value),
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
      1e300,
    ])
      'presence $value': GenerationOptions(presencePenalty: value),
    for (final value in [
      double.nan,
      double.infinity,
      double.negativeInfinity,
      0.0,
      -1.0,
      1e300,
    ])
      'repeat $value': GenerationOptions(repeatPenalty: value),
  };
  for (final entry in cases.entries) {
    test(
      'invalid ${entry.key} rejected before touching another owner',
      () async {
        final runtime = PersistentInferenceIsolate.instance;
        await runtime.withExclusiveSession(Object(), () async {
          final before = runtime.operationSnapshot;
          await expectLater(
            runtime
                .runInference(
                  owner: Object(),
                  modelPath: 'must-not-open.gguf',
                  prompt: '',
                  stopTokens: [],
                  contextSize: 1,
                  batchSize: 1,
                  nGpuLayers: 0,
                  options: entry.value,
                )
                .drain<void>(),
            throwsArgumentError,
          );
          expect(
            runtime.operationSnapshot.contextOwnerId,
            before.contextOwnerId,
          );
          expect(runtime.operationSnapshot.hasNativeWork, before.hasNativeWork);
        });
      },
    );
  }
  test('native representable signed penalties and defaults remain valid', () {
    for (final options in [
      const GenerationOptions(),
      const GenerationOptions(frequencyPenalty: 0, presencePenalty: 0),
      const GenerationOptions(frequencyPenalty: -2, presencePenalty: -0.5),
      const GenerationOptions(
        repeatPenalty: 1,
        frequencyPenalty: 2,
        presencePenalty: 2,
      ),
    ]) {
      expect(options.validatePenalties, returnsNormally);
    }
    expect(
      const GenerationOptions(repeatPenalty: 1e-300).validatePenalties,
      throwsArgumentError,
      reason: 'Positive double underflows to native zero',
    );
  });

  test('native sampler boundary modes remain usable without narrowing ABI', () {
    for (final options in [
      const GenerationOptions(),
      const GenerationOptions(
        temperature: -1,
        topK: -2147483648,
        topP: 0,
        seed: 0,
        maxTokens: 1,
      ),
      const GenerationOptions(
        temperature: 0,
        topK: 2147483647,
        topP: 1,
        seed: 4294967295,
      ),
      const GenerationOptions(topK: 0),
    ]) {
      expect(options.validate, returnsNormally);
    }
  });
}
