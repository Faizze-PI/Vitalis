import 'package:llm_llamacpp/llm_llamacpp.dart';

import '../models/message.dart';
import '../models/note.dart';
import '../models/runtime_profile.dart';
import '../models/context_plan_result.dart';

/// Planner-owned, content-free validation text safe to show to the user.
/// Tokenizer/native exceptions must not be promoted to this type.
class ContextPlanningError extends StateError {
  ContextPlanningError(super.message);
}

class ContextPlanner {
  const ContextPlanner(this.tokenCounter);

  final ContextTokenCounter tokenCounter;

  Future<ContextPlanResult> plan({
    required String systemPrompt,
    required List<Note> attachedNotes,
    required List<Message> messages,
    required RuntimeProfile profile,
  }) async {
    final currentUser =
        messages.isNotEmpty &&
            messages.last.role == MessageRole.user &&
            !messages.last.isError
        ? messages.last.content
        : null;
    if (currentUser == null) {
      throw ContextPlanningError('The current user message is missing');
    }

    if (profile.reservedOutputTokens <= 0 || profile.contextSize <= 0) {
      throw ContextPlanningError('Context and output budgets must be positive');
    }
    var inputLimit = profile.contextSize - profile.reservedOutputTokens;

    var includedNotes = List<Note>.from(attachedNotes);
    late List<Map<String, String>> selected;
    late int selectedTokens;
    while (true) {
      selected = [
        {
          'role': 'system',
          'content': _systemWithNotes(systemPrompt, includedNotes),
        },
        {'role': 'user', 'content': currentUser},
      ];
      selectedTokens = await _count(selected, profile);
      if (selectedTokens <= inputLimit || includedNotes.isEmpty) break;
      includedNotes.removeLast();
    }
    if (selectedTokens >= profile.contextSize) {
      throw ContextPlanningError(
        'System instructions and the current message require '
        '$selectedTokens tokens; the context holds ${profile.contextSize} '
        'tokens and must leave room for output.',
      );
    }

    final availableOutput = profile.contextSize - selectedTokens;
    final outputTokens = profile.reservedOutputTokens < availableOutput
        ? profile.reservedOutputTokens
        : availableOutput;
    inputLimit = profile.contextSize - outputTokens;
    final history = messages.sublist(0, messages.length - 1);
    final pairs = _newestCompletePairs(history);
    var includedPairs = 0;
    for (final pair in pairs) {
      final candidate = <Map<String, String>>[
        selected.first,
        ...pair,
        ...selected.skip(1),
      ];
      final candidateTokens = await _count(candidate, profile);
      if (candidateTokens > inputLimit) break;
      selected = candidate;
      selectedTokens = candidateTokens;
      includedPairs++;
    }

    return ContextPlanResult(
      context: selected,
      promptTokens: selectedTokens,
      contextSize: profile.contextSize,
      reservedOutputTokens: outputTokens,
      droppedMessageCount: history.length - includedPairs * 2,
      droppedNoteCount: attachedNotes.length - includedNotes.length,
    );
  }

  String _systemWithNotes(String systemPrompt, List<Note> notes) {
    final buffer = StringBuffer(systemPrompt);
    for (final note in notes) {
      buffer
        ..write('\n\nContext from attached note "')
        ..write(note.title)
        ..write('":\n')
        ..write(note.content);
    }
    return buffer.toString();
  }

  List<List<Map<String, String>>> _newestCompletePairs(List<Message> messages) {
    final result = <List<Map<String, String>>>[];
    var index = messages.length - 1;
    while (index >= 1) {
      final assistant = messages[index];
      final user = messages[index - 1];
      // Never join a turn across a failed, orphaned or non-chat record.
      if (assistant.role != MessageRole.assistant ||
          assistant.isError ||
          user.role != MessageRole.user ||
          user.isError)
        break;
      index -= 2;
      result.add([
        {'role': 'user', 'content': user.content},
        {'role': 'assistant', 'content': assistant.content},
      ]);
    }
    return result;
  }

  Future<int> _count(
    List<Map<String, String>> context,
    RuntimeProfile profile,
  ) {
    return tokenCounter.count(
      context,
      thinkingEnabled: profile.thinkingMode.name == 'on',
    );
  }
}

abstract interface class ContextTokenCounter {
  Future<int> count(
    List<Map<String, String>> messages, {
    required bool thinkingEnabled,
  });
}

final class LlamaContextTokenCounter implements ContextTokenCounter {
  const LlamaContextTokenCounter(this.repository);

  final LlamaCppChatRepository repository;

  @override
  Future<int> count(
    List<Map<String, String>> messages, {
    required bool thinkingEnabled,
  }) => repository.countChatTokens(
    messages.map((message) {
      final role = switch (message['role']) {
        'system' => LLMRole.system,
        'assistant' => LLMRole.assistant,
        _ => LLMRole.user,
      };
      return LLMMessage(role: role, content: message['content'] ?? '');
    }).toList(),
    think: thinkingEnabled,
  );
}
