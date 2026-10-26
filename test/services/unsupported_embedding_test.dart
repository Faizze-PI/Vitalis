import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';

void main() {
  for (final batch in [false, true]) {
    test(
      'unsupported embedding operation is explicit (batch: $batch)',
      () async {
        final repository = LlamaCppChatRepository.withModelPath(
          'fixture-must-never-be-opened.gguf',
        );
        final before = repository.operationSnapshot;
        try {
          final operation = batch
              ? repository.batchEmbed(model: 'fixture', messages: ['fixture'])
              : repository.embed(model: 'fixture', messages: ['fixture']);
          await expectLater(
            operation,
            throwsA(
              isA<InferenceCapabilityUnsupported>().having(
                (error) => error.capability,
                'capability diagnostic',
                'embeddings',
              ),
            ),
          );
          final after = repository.operationSnapshot;
          expect(after.nativeRequestId, before.nativeRequestId);
          expect(after.contextOwnerId, before.contextOwnerId);
          expect(after.sessionGeneration, before.sessionGeneration);
          expect(after.initializationPending, isFalse);
        } finally {
          await repository.close();
        }
      },
    );
  }

  test('disposed embedding caller remains rejected as disposed', () async {
    final repository = LlamaCppChatRepository();
    await repository.close();
    await expectLater(
      repository.embed(model: 'fixture', messages: ['fixture']),
      throwsA(isA<InferenceRepositoryDisposed>()),
    );
  });

  test('unsupported embedding path has no independent native worker', () {
    final source = File(
      'third_party/llm_llamacpp/lib/src/llamacpp_chat_repository.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('embedding_isolate.dart')));
    expect(source, isNot(contains('llamacpp_chat_repository_embedding.dart')));
    expect(
      File(
        'third_party/llm_llamacpp/lib/src/embedding_isolate.dart',
      ).existsSync(),
      isFalse,
    );
  });

  test('obsolete standalone worker cannot bypass persistent runtime', () {
    expect(
      File(
        'third_party/llm_llamacpp/lib/src/inference_isolate.dart',
      ).existsSync(),
      isFalse,
    );
    final source = File(
      'third_party/llm_llamacpp/lib/src/isolate_messages.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('class InferenceRequest')));
  });
}
