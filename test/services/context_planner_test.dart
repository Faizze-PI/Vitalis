import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/note.dart';
import 'package:vitalis_app/models/runtime_profile.dart';
import 'package:vitalis_app/services/context_planner.dart';

class _ExactCounter implements ContextTokenCounter {
  bool? thinkingEnabled;

  @override
  Future<int> count(
    List<Map<String, String>> messages, {
    required bool thinkingEnabled,
  }) async {
    this.thinkingEnabled = thinkingEnabled;
    return messages.fold<int>(
      0,
      (total, message) => total + (message['content']?.runes.length ?? 0),
    );
  }
}

RuntimeProfile _profile({
  int context = 100,
  int output = 10,
  ThinkingMode thinking = ThinkingMode.off,
}) => RuntimeProfile(
  contextSize: context,
  reservedOutputTokens: output,
  generationThreads: 1,
  promptThreads: 1,
  batchSize: 32,
  gpuLayers: 0,
  thinkingMode: thinking,
);

Message _message(MessageRole role, String content) =>
    Message(chatId: 1, role: role, content: content);

void main() {
  test(
    'large requested output remains bounded by exact available context',
    () async {
      final result = await ContextPlanner(_ExactCounter()).plan(
        systemPrompt: 'fixed',
        attachedNotes: [],
        messages: [_message(MessageRole.user, 'current')],
        profile: _profile(context: 100, output: 9223372036854775807),
      );
      expect(result.promptTokens, 12);
      expect(result.reservedOutputTokens, 88);
      expect(
        result.promptTokens + result.reservedOutputTokens,
        result.contextSize,
      );
    },
  );

  test(
    'failed trailing assistant cannot resurrect an earlier user request',
    () async {
      await expectLater(
        ContextPlanner(_ExactCounter()).plan(
          systemPrompt: 's',
          attachedNotes: [],
          messages: [
            _message(MessageRole.user, 'old request'),
            Message(
              chatId: 1,
              role: MessageRole.assistant,
              content: 'failed response',
              isError: true,
            ),
          ],
          profile: _profile(),
        ),
        throwsA(isA<ContextPlanningError>()),
      );
    },
  );

  for (final barrier in [
    _message(MessageRole.user, 'unanswered'),
    _message(MessageRole.assistant, 'orphan'),
    _message(MessageRole.system, 'historical system record'),
    Message(
      chatId: 1,
      role: MessageRole.assistant,
      content: 'error',
      isError: true,
    ),
  ]) {
    test(
      'history ${barrier.role.name}/${barrier.isError} is a turn boundary',
      () async {
        final result = await ContextPlanner(_ExactCounter()).plan(
          systemPrompt: 's',
          attachedNotes: [],
          messages: [
            _message(MessageRole.user, 'old user'),
            _message(MessageRole.assistant, 'old answer'),
            barrier,
            _message(MessageRole.user, 'recent user'),
            _message(MessageRole.assistant, 'recent answer'),
            _message(MessageRole.user, 'current'),
          ],
          profile: _profile(context: 500),
        );
        expect(result.context.map((entry) => entry['content']).toList(), [
          's',
          'recent user',
          'recent answer',
          'current',
        ]);
        expect(result.droppedMessageCount, 3);
        expect(result.wasTruncated, isTrue);
      },
    );
  }

  test('reduces output reservation when required input still fits', () async {
    final result = await ContextPlanner(_ExactCounter()).plan(
      systemPrompt: 's' * 20,
      attachedNotes: [],
      messages: [_message(MessageRole.user, 'u' * 20)],
      profile: _profile(context: 50, output: 30),
    );
    expect(result.promptTokens, 40);
    expect(result.reservedOutputTokens, 10);
    expect(result.context.last['content'], 'u' * 20);
  });

  test(
    'counts the rendered request with the runtime tokenizer adapter',
    () async {
      final counter = _ExactCounter();
      final result = await ContextPlanner(counter).plan(
        systemPrompt: 'system',
        attachedNotes: [Note(title: 'facts', content: 'note')],
        messages: [_message(MessageRole.user, 'current')],
        profile: _profile(thinking: ThinkingMode.on),
      );

      expect(result.context.first['content'], contains('facts'));
      expect(result.context.last['content'], 'current');
      expect(
        result.promptTokens + result.reservedOutputTokens,
        lessThanOrEqualTo(100),
      );
      expect(counter.thinkingEnabled, isTrue);
    },
  );

  test('keeps only a contiguous newest block of complete turns', () async {
    final result = await ContextPlanner(_ExactCounter()).plan(
      systemPrompt: 's',
      attachedNotes: const [],
      messages: [
        _message(MessageRole.user, 'old-user-' * 4),
        _message(MessageRole.assistant, 'old-answer-' * 4),
        _message(MessageRole.user, 'new-user'),
        _message(MessageRole.assistant, 'new-answer'),
        _message(MessageRole.user, 'current'),
      ],
      profile: _profile(context: 45, output: 5),
    );

    expect(
      result.context.map((entry) => entry['content']),
      containsAll(['new-user', 'new-answer', 'current']),
    );
    expect(
      result.context.map((entry) => entry['content']),
      isNot(contains('old-user-' * 4)),
    );
    expect(result.droppedMessageCount, 2);
  });

  test('drops notes from the end before rejecting required content', () async {
    final result = await ContextPlanner(_ExactCounter()).plan(
      systemPrompt: 'system',
      attachedNotes: [
        Note(title: 'keep', content: 'a'),
        Note(title: 'drop', content: 'x' * 80),
      ],
      messages: [_message(MessageRole.user, 'current')],
      profile: _profile(context: 80, output: 10),
    );

    expect(result.droppedNoteCount, 1);
    expect(result.context.first['content'], contains('keep'));
    expect(result.context.first['content'], isNot(contains('drop')));
  });

  test(
    'rejects rather than truncating system instructions or current input',
    () async {
      expect(
        () => ContextPlanner(_ExactCounter()).plan(
          systemPrompt: 's' * 40,
          attachedNotes: const [],
          messages: [_message(MessageRole.user, 'u' * 40)],
          profile: _profile(context: 50, output: 10),
        ),
        throwsA(isA<StateError>()),
      );
    },
  );
}
