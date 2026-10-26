abstract final class RuntimeBenchmarkPolicy {
  static const promptTokens = 256; // hardcode: HC-048
  static const outputTokens = 32; // hardcode: HC-048
  static const maximumPaddingUnits = promptTokens; // hardcode: HC-048
  static const instruction =
      'List common household objects in a numbered list. '
      'Continue until the response limit. Reference words:'; // hardcode: HC-048
  static const paddingUnit = ' item'; // hardcode: HC-048
}

class RuntimeBenchmarkWorkloadUnavailable implements Exception {
  const RuntimeBenchmarkWorkloadUnavailable();
  @override
  String toString() => 'Exact native benchmark workload was not verified';
}

/// The complete rendered chat, including model/template markers, is counted
/// by the supplied native tokenizer. Character counts are never token counts.
class RuntimeBenchmarkWorkload {
  const RuntimeBenchmarkWorkload._(this.prompt);
  final String prompt;

  static Future<RuntimeBenchmarkWorkload> create({
    required Future<int> Function(String) countPromptTokens,
    required void Function() checkCurrent,
    required int contextSize,
  }) async {
    checkCurrent();
    if (contextSize <
        RuntimeBenchmarkPolicy.promptTokens +
            RuntimeBenchmarkPolicy.outputTokens) {
      throw const RuntimeBenchmarkWorkloadUnavailable();
    }
    final tried = <int>{};
    Future<({String text, int count})> inspect(int units) async {
      checkCurrent();
      tried.add(units);
      final text =
          RuntimeBenchmarkPolicy.instruction +
          List.filled(units, RuntimeBenchmarkPolicy.paddingUnit).join();
      final count = await countPromptTokens(text);
      checkCurrent();
      if (count < 0) throw const RuntimeBenchmarkWorkloadUnavailable();
      return (text: text, count: count);
    }

    Future<RuntimeBenchmarkWorkload> verified(String text) async {
      // Also reject changing tokenizer/template state during construction.
      if (await countPromptTokens(text) != RuntimeBenchmarkPolicy.promptTokens)
        throw const RuntimeBenchmarkWorkloadUnavailable();
      checkCurrent();
      return RuntimeBenchmarkWorkload._(text);
    }

    // A bounded binary search handles ordinary tokenizers cheaply. Token
    // counts are not assumed monotonic: enumerate untried candidates if needed.
    var low = 0;
    var high = RuntimeBenchmarkPolicy.maximumPaddingUnits;
    while (low <= high) {
      final units = (low + high) ~/ 2;
      final candidate = await inspect(units);
      if (candidate.count == RuntimeBenchmarkPolicy.promptTokens) {
        return verified(candidate.text);
      }
      if (candidate.count < RuntimeBenchmarkPolicy.promptTokens)
        low = units + 1;
      else
        high = units - 1;
    }
    for (
      var units = 0;
      units <= RuntimeBenchmarkPolicy.maximumPaddingUnits;
      units++
    ) {
      if (tried.contains(units)) continue;
      final result = await inspect(units);
      if (result.count == RuntimeBenchmarkPolicy.promptTokens)
        return verified(result.text);
    }
    throw const RuntimeBenchmarkWorkloadUnavailable();
  }
}
