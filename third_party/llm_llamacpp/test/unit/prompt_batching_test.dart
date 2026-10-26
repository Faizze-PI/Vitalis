import 'package:test/test.dart';
import 'package:llm_llamacpp/src/prompt_batching.dart';

void main() {
  group('promptDecodeChunks', () {
    test('does not create a decode request for an empty prompt', () {
      expect(promptDecodeChunks(tokenCount: 0, batchSize: 128), isEmpty);
    });

    test('keeps an exact native batch intact', () {
      expect(promptDecodeChunks(tokenCount: 128, batchSize: 128), [
        (offset: 0, length: 128),
      ]);
    });

    test('splits the 256-token tuning workload at the 128-token boundary', () {
      final chunks = promptDecodeChunks(tokenCount: 256, batchSize: 128);

      expect(chunks, [(offset: 0, length: 128), (offset: 128, length: 128)]);
      expect(chunks.every((chunk) => chunk.length <= 128), isTrue);
    });

    test('rejects invalid native batch sizes', () {
      expect(
        () => promptDecodeChunks(tokenCount: 1, batchSize: 0),
        throwsArgumentError,
      );
    });
  });
}
