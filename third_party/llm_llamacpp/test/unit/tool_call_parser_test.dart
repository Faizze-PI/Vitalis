library;

import 'package:llm_core/llm_core.dart';
import 'package:llm_llamacpp/src/tool_call_parser.dart';
import 'package:test/test.dart';

void main() {
  group('ToolCallParser', () {
    test('parseToolCalls assigns non-empty ids for JSON format', () {
      const content = '{"name": "calculator", "arguments": {"a": 2, "b": 2}}';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls, isNotEmpty);
      expect(calls.first.id, isNotNull);
      expect(calls.first.id, isNotEmpty);
      expect(calls.first.name, 'calculator');
      expect(calls.first.arguments, anyOf('{"a":2,"b":2}', '{"a": 2, "b": 2}'));
    });

    test('parseToolCalls assigns non-empty ids for function-style format', () {
      const content = 'calculator({"a": 2, "b": 2})';

      final calls = ToolCallParser.parseToolCalls(content);

      expect(calls, isNotEmpty);
      expect(calls.first.id, isNotNull);
      expect(calls.first.id, isNotEmpty);
      expect(calls.first.name, 'calculator');
    });
  });
}
