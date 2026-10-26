import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/isolate_messages.dart';
import 'package:llm_llamacpp/src/persistent_inference_isolate.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'helper first-output latency includes model context and prompt work',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'] ?? '';
      expect(path, isNotEmpty, reason: 'Verified native fixture is mandatory');
      expect(
        (await sha256.bind(File(path).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final runtime = PersistentInferenceIsolate.instance;
      final owner = Object();
      addTearDown(() async {
        await runtime.cancel(null, owner);
        await runtime.drainOwner(owner);
        await runtime.releaseOwnedContext(owner);
      });
      final events = await runtime
          .runInference(
            owner: owner,
            modelPath: path,
            prompt: 'The numbers are one, two,',
            stopTokens: [],
            contextSize: 512,
            batchSize: 128,
            nGpuLayers: 0,
            threads: 2,
            options: const GenerationOptions(
              maxTokens: 8,
              temperature: 0,
              seed: 42,
            ),
          )
          .toList();
      final complete = events.whereType<InferenceComplete>().single;
      expect(
        events.whereType<InferenceToken>().any((e) => e.token.isNotEmpty),
        isTrue,
      );
      expect(
        complete.modelLoadMicros,
        greaterThan(0),
        reason: 'Cold fixture required',
      );
      expect(complete.timeToFirstTokenMicros, isNotNull);
      expect(
        complete.timeToFirstTokenMicros!,
        greaterThanOrEqualTo(
          complete.modelLoadMicros +
              complete.contextInitMicros +
              complete.promptEvalMicros,
        ),
        reason:
            'Generation-only duration cannot be reported as request first-output latency',
      );
      final timing = complete.outputTiming!;
      expect(timing.requestId, greaterThanOrEqualTo(0));
      expect(timing.firstSampledTokenMicros, isNotNull);
      expect(timing.firstEmittedTextMicros, complete.timeToFirstTokenMicros);
      expect(
        timing.firstSampledTokenMicros!,
        lessThanOrEqualTo(timing.firstEmittedTextMicros!),
      );
      final warm =
          (await runtime
                  .runInference(
                    owner: owner,
                    modelPath: path,
                    prompt: 'The numbers are one, two,',
                    stopTokens: [],
                    contextSize: 512,
                    batchSize: 128,
                    nGpuLayers: 0,
                    threads: 2,
                    options: const GenerationOptions(
                      maxTokens: 8,
                      temperature: 0,
                      seed: 42,
                    ),
                  )
                  .toList())
              .whereType<InferenceComplete>()
              .single;
      expect(warm.modelLoadMicros, 0);
      expect(warm.contextInitMicros, 0);
      expect(warm.outputTiming!.requestId, isNot(timing.requestId));
      expect(
        warm.timeToFirstTokenMicros,
        warm.outputTiming!.firstEmittedTextMicros,
      );
      expect(
        warm.outputTiming!.firstSampledTokenMicros!,
        lessThanOrEqualTo(warm.outputTiming!.firstEmittedTextMicros!),
      );
      final marker = events
          .whereType<InferenceToken>()
          .map((e) => e.token)
          .join();
      final suppressed = await runtime
          .runInference(
            owner: owner,
            modelPath: path,
            prompt: 'The numbers are one, two,',
            stopTokens: [marker],
            contextSize: 512,
            batchSize: 128,
            nGpuLayers: 0,
            threads: 2,
            options: const GenerationOptions(
              maxTokens: 8,
              temperature: 0,
              seed: 42,
            ),
          )
          .toList();
      final stopped = suppressed.whereType<InferenceComplete>().single;
      expect(stopped.reason, InferenceCompletionReason.stopSequence);
      expect(
        suppressed.whereType<InferenceToken>().any((e) => e.token.isNotEmpty),
        isFalse,
      );
      expect(stopped.outputTiming!.firstSampledTokenMicros, isNotNull);
      expect(stopped.outputTiming!.firstEmittedTextMicros, isNull);
      expect(
        stopped.timeToFirstTokenMicros,
        isNull,
        reason: 'Buffered stop text is not an emitted text event',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
