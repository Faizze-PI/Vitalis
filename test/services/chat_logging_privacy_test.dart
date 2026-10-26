import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:logging/logging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'verbose rejected generation never logs private message content',
    () async {
      final previousLevel = Logger.root.level;
      Logger.root.level = Level.ALL;
      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      final repository = LlamaCppChatRepository.withModelPath('unused.gguf');
      addTearDown(() async {
        await repository.close();
        await subscription.cancel();
        Logger.root.level = previousLevel;
      });

      await LlamaCppChatRepository.withUnloadedRuntime(() async {
        await expectLater(
          repository
              .streamChat(
                'fixture',
                messages: [
                  LLMMessage(
                    role: LLMRole.system,
                    content: 'PRIVATE_SYSTEM_7829',
                  ),
                  LLMMessage(role: LLMRole.user, content: 'PRIVATE_USER_3681'),
                ],
              )
              .drain<void>(),
          throwsA(isA<InferenceRuntimeBusy>()),
        );
      });

      final messages = records.map((record) => record.message).join('\n');
      expect(messages, contains('Messages count: 2'));
      expect(messages, isNot(contains('PRIVATE_SYSTEM_7829')));
      expect(messages, isNot(contains('PRIVATE_USER_3681')));
    },
  );
}
