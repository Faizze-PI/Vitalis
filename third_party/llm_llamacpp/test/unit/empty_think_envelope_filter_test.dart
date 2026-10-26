import 'package:test/test.dart';
import 'package:llm_llamacpp/src/empty_think_envelope_filter.dart';

void main() {
  group('EmptyThinkEnvelopeFilter', () {
    test('removes an empty envelope split over streamed chunks', () {
      final filter = EmptyThinkEnvelopeFilter();

      expect(filter.add('<'), isEmpty);
      expect(filter.add('think>\n'), isEmpty);
      expect(filter.add('\n</think>\nAnswer'), 'Answer');
      expect(filter.finish(), isEmpty);
    });

    test('preserves a non-empty think block instead of hiding it', () {
      final filter = EmptyThinkEnvelopeFilter();

      expect(filter.add('<think>reasoning'), '<think>reasoning');
      expect(filter.add('</think>Answer'), '</think>Answer');
    });

    test('does not delay a normal response', () {
      final filter = EmptyThinkEnvelopeFilter();

      expect(filter.add('Plain answer'), 'Plain answer');
    });
  });
}
