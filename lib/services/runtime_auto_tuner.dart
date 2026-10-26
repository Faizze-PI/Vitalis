import 'dart:async';
import 'dart:convert';

import '../models/runtime_capabilities.dart';
import '../models/runtime_profile.dart';
import 'runtime_benchmark_workload.dart';

class TuningCancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
  void throwIfCancelled() {
    if (_cancelled) throw const TuningCancelled();
  }
}

class TuningCancelled implements Exception {
  const TuningCancelled();
}

class RuntimeTuningBaselineUnavailable implements Exception {
  const RuntimeTuningBaselineUnavailable();

  @override
  String toString() => 'Conservative runtime baseline was not verified';
}

class RuntimeBenchmarkConfigurationUnavailable implements Exception {
  const RuntimeBenchmarkConfigurationUnavailable();

  @override
  String toString() =>
      'Applied native benchmark configuration was not verified';
}

class RuntimeBenchmarkResult {
  const RuntimeBenchmarkResult({
    required this.profile,
    required this.promptTokensPerSecond,
    required this.generationTokensPerSecond,
    required this.generatedTokens,
    required this.safe,
    this.failureReason,
  });

  final RuntimeProfile profile;
  final double promptTokensPerSecond;
  final double generationTokensPerSecond;
  final int generatedTokens;
  final bool safe;
  final String? failureReason;

  bool isValidFor(RuntimeProfile requestedProfile) =>
      safe &&
      failureReason == null &&
      generatedTokens == RuntimeBenchmarkPolicy.outputTokens &&
      promptTokensPerSecond.isFinite &&
      promptTokensPerSecond > 0 &&
      generationTokensPerSecond.isFinite &&
      generationTokensPerSecond > 0 &&
      jsonEncode(profile.toJson()) == jsonEncode(requestedProfile.toJson());
}

typedef RuntimeBenchmarkRunner =
    Future<RuntimeBenchmarkResult> Function(
      RuntimeProfile profile,
      TuningCancellationToken cancellation,
    );

class RuntimeAutoTuner {
  const RuntimeAutoTuner();

  List<RuntimeProfile> candidates(
    RuntimeProfile conservative,
    RuntimeCapabilities capabilities,
  ) {
    if (!capabilities.hasKnownSafeTelemetry || capabilities.isSevere) {
      return [conservative];
    }
    final cores = capabilities.performanceProcessors!.clamp(
      1,
      capabilities.logicalProcessors,
    );
    final threads = <int>{(cores - 1).clamp(1, 8), cores.clamp(1, 8)}.toList()
      ..sort();
    final result = <RuntimeProfile>[conservative];
    for (var threadIndex = 0; threadIndex < threads.length; threadIndex++) {
      final threadCount = threads[threadIndex];
      final batches = threadIndex == threads.length - 1
          ? const [128, 256, 512]
          : const [128, 512];
      for (final batch in batches) {
        final candidate = conservative.copyWith(
          generationThreads: threadCount,
          promptThreads: threadCount,
          batchSize: batch,
        );
        if (!result.any(
          (existing) =>
              existing.generationThreads == candidate.generationThreads &&
              existing.batchSize == candidate.batchSize,
        )) {
          result.add(candidate);
        }
      }
    }
    return result.take(6).toList(growable: false);
  }

  Future<RuntimeBenchmarkResult> tune({
    required RuntimeProfile conservative,
    required RuntimeCapabilities capabilities,
    required RuntimeBenchmarkRunner benchmark,
    required TuningCancellationToken cancellation,
  }) async {
    cancellation.throwIfCancelled();
    final baseline = await benchmark(conservative, cancellation);
    cancellation.throwIfCancelled();
    if (!baseline.isValidFor(conservative)) {
      // A later successful candidate is not evidence for the conservative
      // baseline. Without it, no throughput-regression comparison is valid.
      throw const RuntimeTuningBaselineUnavailable();
    }
    final results = <RuntimeBenchmarkResult>[baseline];
    for (final candidate in candidates(conservative, capabilities).skip(1)) {
      cancellation.throwIfCancelled();
      final result = await benchmark(candidate, cancellation);
      cancellation.throwIfCancelled();
      if (!result.isValidFor(candidate)) continue;
      if (result.generationTokensPerSecond <
          baseline.generationTokensPerSecond) {
        continue;
      }
      results.add(result);
    }
    final maxPrompt = results
        .map((result) => result.promptTokensPerSecond)
        .reduce((a, b) => a > b ? a : b);
    final maxGeneration = results
        .map((result) => result.generationTokensPerSecond)
        .reduce((a, b) => a > b ? a : b);
    results.sort((left, right) {
      final leftScore =
          0.35 * (left.promptTokensPerSecond / maxPrompt) +
          0.65 * (left.generationTokensPerSecond / maxGeneration);
      final rightScore =
          0.35 * (right.promptTokensPerSecond / maxPrompt) +
          0.65 * (right.generationTokensPerSecond / maxGeneration);
      return rightScore.compareTo(leftScore);
    });
    return results.first;
  }
}
