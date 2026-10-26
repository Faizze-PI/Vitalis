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
    'native context applies independent generation and prompt threads',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final runtime = PersistentInferenceIsolate.instance;
      final owner = Object();
      addTearDown(() async {
        await runtime.releaseOwnedContext(owner);
        runtime.dispose();
      });
      for (final promptThreads in <int?>[3, 1, null]) {
        await runtime.prepare(
          owner: owner,
          modelPath: path,
          contextSize: 2048,
          batchSize: 128,
          nGpuLayers: 0,
          threads: 2,
          promptThreads: promptThreads,
        );
        final events = await runtime
            .runInference(
              owner: owner,
              modelPath: path,
              contextSize: 2048,
              batchSize: 128,
              nGpuLayers: 0,
              threads: 2,
              promptThreads: promptThreads,
              prompt: 'Say hello.',
              stopTokens: const [],
              options: const GenerationOptions(maxTokens: 1),
            )
            .toList();
        final completion = events.whereType<InferenceComplete>().single;
        final applied = completion.configuration!;
        stdout.writeln(
          'NATIVE_CONFIGURATION generation=${applied.generationThreads} '
          'prompt=${applied.promptThreads} context=${applied.contextSize} '
          'batch=${applied.batchSize}',
        );
        expect(applied.generationThreads, 2);
        expect(applied.promptThreads, promptThreads ?? 2);
        expect(applied.contextSize, 2048);
        expect(applied.batchSize, 128);
        expect(completion.generatedTokens, greaterThan(0));
        expect(completion.modelLoadMicros, 0);
        expect(completion.contextInitMicros, 0);
        expect(
          events.whereType<RuntimeProgress>().where(
            (progress) =>
                progress.phase == RuntimeProgressPhase.contextCreating &&
                progress.completedUnits == 0,
          ),
          isEmpty,
          reason: 'Generation must reuse the correctly prepared context',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
