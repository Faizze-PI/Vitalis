import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'uninstall unrelated model preserves an externally loaded model',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final sandbox = await Directory.systemTemp.createTemp(
        'vitalis-disjoint-removal-',
      );
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.setDatabasesPath(sandbox.path);
      final loader = LlamaCppModelLoader();
      final registry = ModelRegistryService(
        allowedRoots: () async => [sandbox],
      );
      try {
        final owned = await loader.loadModel(
          path,
          options: const ModelLoadOptions(vocabOnly: true),
        );
        final vocabulary = owned.vocabSize;
        final unrelated = File('${sandbox.path}/unrelated.gguf');
        await unrelated.writeAsString('GGUF disposable registry fixture');
        await DatabaseHelper.instance.upsertModel({
          'id': 'unrelated',
          'display_name': 'Disposable',
          'source': 'fixture',
          'local_path': unrelated.path,
          'compatibility_status': 'compatible',
          'installation_state': 'installed',
        });
        await registry.uninstall('unrelated');
        expect(await unrelated.exists(), isFalse);
        expect((await registry.findById('unrelated'))?.isInstalled, isFalse);
        expect(owned.vocabSize, vocabulary);
        expect(await File(path).exists(), isTrue);
      } finally {
        try {
          await registry.close();
        } finally {
          loader.dispose();
          await DatabaseHelper.instance.close();
          await sandbox.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'borrowed model survives repository close and acknowledged handoff',
    () async {
      final path = Platform.environment['VITALIS_TEST_MODEL'];
      expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
      expect(
        (await sha256.bind(File(path!).openRead()).first).toString(),
        BundledModelManifest.sha256,
      );
      final loader = LlamaCppModelLoader();
      // The externally owned handle only needs vocabulary for this adapter test;
      // each repository still prepares a real full inference model/context.
      final model = await loader.loadModel(
        path,
        options: const ModelLoadOptions(vocabOnly: true),
      );
      addTearDown(loader.dispose);
      var mutationEntered = false;
      await expectLater(
        LlamaCppChatRepository.withUnloadedRuntime(() async {
          mutationEntered = true;
        }),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      expect(mutationEntered, isFalse);
      final originalVocabulary = model.vocabSize;
      final owner = LlamaCppChatRepository.withModel(
        model,
        loader.bindings,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      final successor = LlamaCppChatRepository.withModel(
        model,
        loader.bindings,
        contextSize: 2048,
        batchSize: 128,
        threads: 2,
      );
      addTearDown(() async {
        try {
          await owner.close();
          await successor.close();
        } finally {
          loader.dispose();
        }
      });

      await owner.withExclusiveSession(() async {
        await owner.prepare();
        expect(owner.reservationState, RuntimeReservationState.reserved);
        expect(owner.operationSnapshot.state, RuntimeReservationState.reserved);
        expect(owner.model, same(model));
        expect(owner.isModelLoaded, isTrue);
        await expectLater(
          successor.prepare(),
          throwsA(isA<InferenceRuntimeBusy>()),
        );
      });
      // Ending the operation leaves a reusable, still-owned context. An idle
      // reservation is not permission for a different repository to take it.
      expect(owner.reservationState, RuntimeReservationState.idle);
      final originalContextOwner = owner.operationSnapshot.contextOwnerId;
      expect(owner.operationSnapshot.hasRetainedContext, isTrue);
      await expectLater(
        successor.prepare(),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      expect(owner.operationSnapshot.contextOwnerId, originalContextOwner);

      Future<void> generate(LlamaCppChatRepository repository) async {
        final text = StringBuffer();
        var completions = 0;
        await for (final chunk in repository.streamChatWithGenerationOptions(
          'borrowed-model-fixture',
          messages: [
            LLMMessage(role: LLMRole.user, content: 'Reply briefly: hello'),
          ],
          generationOptions: const GenerationOptions(maxTokens: 16),
        )) {
          text.write(chunk.message?.content ?? '');
          if (chunk.done == true) completions++;
        }
        expect(text, isNotEmpty);
        expect(completions, 1);
        expect(repository.lastMetrics?.generatedTokens, greaterThan(0));
        final metrics = repository.lastMetrics!;
        expect(metrics.promptEvalMicros, greaterThan(0));
        expect(metrics.promptTokensPerSecond, greaterThan(0));
        expect(metrics.promptTokensPerSecond.isFinite, isTrue);
      }

      await generate(owner);
      await owner.close();
      expect(owner.isDisposed, isTrue);
      expect(owner.isModelLoaded, isFalse);
      expect(
        model.vocabSize,
        originalVocabulary,
        reason: 'Repository must not free its externally owned native model',
      );
      await expectLater(
        owner.prepare(),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
      await successor.prepare();
      expect(
        successor.operationSnapshot.contextOwnerId,
        isNot(originalContextOwner),
      );
      await generate(successor);
      await successor.close();
      expect(model.vocabSize, originalVocabulary);
      loader.dispose();
      model.dispose(); // Repeated disposal cannot release another lease.
      var admittedAfterFree = false;
      await LlamaCppChatRepository.withUnloadedRuntime(() async {
        admittedAfterFree = true;
        expect(await _crossIsolateLoadIsBusy(path), isTrue);
      });
      expect(admittedAfterFree, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<bool> _crossIsolateLoadIsBusy(String path) => Isolate.run(() async {
  final loader = LlamaCppModelLoader();
  try {
    await loader.loadModel(
      path,
      options: const ModelLoadOptions(vocabOnly: true),
    );
    return false;
  } on InferenceRuntimeBusy {
    return true;
  } finally {
    loader.dispose();
  }
});
