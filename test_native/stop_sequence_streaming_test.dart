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
    'unrelated stop marker preserves native output without batching it all',
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
        await runtime.cancel(null, owner);
        await runtime.drainOwner(owner);
        await runtime.releaseOwnedContext(owner);
      });
      Future<List<dynamic>> generate(List<String> stops) => runtime
          .runInference(
            owner: owner,
            modelPath: path,
            contextSize: 2048,
            batchSize: 128,
            nGpuLayers: 0,
            threads: 2,
            prompt: '',
            messages: const [
              IsolateMessage(
                role: 'user',
                content: 'List the numbers 1 to 20.',
              ),
            ],
            thinking: false,
            stopTokens: stops,
            options: const GenerationOptions(
              maxTokens: 16,
              temperature: 0,
              seed: 42,
            ),
          )
          .toList();

      final reference = await generate([]);
      final marker = 'UNUSED_STOP_MARKER_' * 64;
      final actual = await generate([marker]);
      final referenceText = reference
          .whereType<InferenceToken>()
          .map((event) => event.token)
          .join();
      final chunks = actual
          .whereType<InferenceToken>()
          .where((event) => event.token.isNotEmpty)
          .toList();
      final actualText = chunks.map((event) => event.token).join();
      expect(referenceText, isNotEmpty);
      expect(
        referenceText.length,
        lessThan(marker.length - 1),
        reason: 'Fixture must expose whole-response buffering in the old code',
      );
      expect(actualText, referenceText);
      expect(
        chunks.length,
        greaterThan(1),
        reason: 'Unrelated stop markers must not hold all output until flush',
      );
      expect(actual.whereType<InferenceComplete>(), hasLength(1));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
