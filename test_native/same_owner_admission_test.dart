import 'dart:async';
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
    'same owner cannot admit overlapping native work or replace request identity',
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
      Future<void> prepare() => runtime.prepare(
        modelPath: path,
        contextSize: 2048,
        batchSize: 128,
        nGpuLayers: 0,
        threads: 2,
        owner: owner,
      );
      Stream<dynamic> generate(int maximum) => runtime.runInference(
        modelPath: path,
        prompt: '',
        messages: const [
          IsolateMessage(
            role: 'user',
            content: 'Write a long numbered list of ordinary objects.',
          ),
        ],
        stopTokens: const [],
        contextSize: 2048,
        batchSize: 128,
        nGpuLayers: 0,
        threads: 2,
        options: GenerationOptions(maxTokens: maximum),
        owner: owner,
      );
      await prepare();
      final events = <Object>[];
      final visible = Completer<void>();
      final finished = Completer<void>();
      final subscription = generate(256).listen(
        (event) {
          events.add(event as Object);
          if (event is InferenceToken &&
              event.token.isNotEmpty &&
              !visible.isCompleted) {
            visible.complete();
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!visible.isCompleted) visible.completeError(error, stack);
          if (!finished.isCompleted) finished.completeError(error, stack);
        },
        onDone: () => finished.complete(),
      );
      addTearDown(subscription.cancel);
      await visible.future.timeout(const Duration(minutes: 2));
      final active = runtime.operationSnapshot;
      expect(active.nativeRequestId, isNotNull);
      expect(active.hasNativeWork, isTrue);

      await expectLater(
        runtime.countChatTokens(const [
          IsolateMessage(role: 'user', content: 'Competing tokenization'),
        ], owner: owner),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      await expectLater(prepare(), throwsA(isA<InferenceRuntimeBusy>()));
      await expectLater(
        runtime.withExclusiveSession(
          owner,
          () async => fail('Rejected reservation must not execute its action'),
        ),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      await expectLater(
        generate(8).toList(),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      expect(runtime.operationSnapshot.nativeRequestId, active.nativeRequestId);
      expect(runtime.operationSnapshot.contextOwnerId, active.contextOwnerId);
      expect(events.whereType<InferenceError>(), isEmpty);

      await runtime.cancel(active.nativeRequestId, owner);
      await finished.future.timeout(const Duration(seconds: 3));
      expect(events.whereType<InferenceCancelled>(), hasLength(1));
      expect(events.whereType<InferenceComplete>(), isEmpty);
      expect(runtime.operationSnapshot.hasNativeWork, isFalse);
      final recovered = await generate(8).toList();
      expect(recovered.whereType<InferenceError>(), isEmpty);
      expect(recovered.whereType<InferenceComplete>(), hasLength(1));
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
