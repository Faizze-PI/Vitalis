/// Splits a tokenized prompt into requests accepted by llama.cpp.
///
/// `llama_decode` aborts the process when a submitted batch exceeds the
/// context's configured `n_batch`; this helper makes that invariant explicit
/// at the Dart/native boundary. Positions remain native-managed through
/// `llama_batch_get_one`, so each returned range is decoded in order.
List<({int offset, int length})> promptDecodeChunks({
  required int tokenCount,
  required int batchSize,
}) {
  if (tokenCount < 0) {
    throw ArgumentError.value(tokenCount, 'tokenCount', 'must not be negative');
  }
  if (batchSize <= 0) {
    throw ArgumentError.value(batchSize, 'batchSize', 'must be positive');
  }

  final chunks = <({int offset, int length})>[];
  for (var offset = 0; offset < tokenCount; offset += batchSize) {
    final remaining = tokenCount - offset;
    chunks.add((
      offset: offset,
      length: remaining < batchSize ? remaining : batchSize,
    ));
  }
  return chunks;
}
