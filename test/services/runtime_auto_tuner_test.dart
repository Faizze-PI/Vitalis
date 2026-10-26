import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/runtime_capabilities.dart';
import 'package:vitalis_app/models/runtime_profile.dart';
import 'package:vitalis_app/services/backend_self_test.dart';
import 'package:vitalis_app/services/runtime_auto_tuner.dart';

void main() {
  const conservative = RuntimeProfile(
    contextSize: 4096,
    reservedOutputTokens: 512,
    generationThreads: 2,
    promptThreads: 2,
    batchSize: 128,
    gpuLayers: 0,
    thinkingMode: ThinkingMode.off,
  );
  const capabilities = RuntimeCapabilities(
    logicalProcessors: 8,
    performanceProcessors: 4,
    deviceFingerprint: 'device',
    abis: ['arm64-v8a'],
    packagedBackends: {'cpu', 'vulkan'},
    availableMemoryBytes: 4 * 1024 * 1024 * 1024,
    totalMemoryBytes: 8 * 1024 * 1024 * 1024,
    processRssBytes: 100,
    thermalStatus: 0,
    lowMemory: false,
  );

  test('automatic tuner evaluates no more than six bounded candidates', () {
    final candidates = const RuntimeAutoTuner().candidates(
      conservative,
      capabilities,
    );
    expect(candidates.length, lessThanOrEqualTo(6));
    expect(candidates.first, same(conservative));
    expect(candidates.every((profile) => profile.gpuLayers == 0), isTrue);
    expect(
      candidates.every(
        (profile) => const [128, 256, 512].contains(profile.batchSize),
      ),
      isTrue,
    );
  });

  test('automatic tuner selects the fastest safe weighted candidate', () async {
    final winner = await const RuntimeAutoTuner().tune(
      conservative: conservative,
      capabilities: capabilities,
      cancellation: TuningCancellationToken(),
      benchmark: (profile, _) async => RuntimeBenchmarkResult(
        profile: profile,
        promptTokensPerSecond: profile.batchSize.toDouble(),
        generationTokensPerSecond:
            profile.generationThreads == 4 && profile.batchSize == 512
            ? 20
            : 10,
        generatedTokens: 32,
        safe: true,
      ),
    );
    expect(winner.profile.generationThreads, 4);
    expect(winner.profile.batchSize, 512);
  });

  test('unknown telemetry keeps only the conservative profile', () {
    const unknown = RuntimeCapabilities(
      logicalProcessors: 8,
      performanceProcessors: 4,
      deviceFingerprint: 'unknown',
      abis: [],
      packagedBackends: {'cpu'},
    );
    expect(const RuntimeAutoTuner().candidates(conservative, unknown), [
      conservative,
    ]);
  });
  test('benchmark result cannot exceed the fixed generation workload', () {
    const result = RuntimeBenchmarkResult(
      profile: conservative,
      promptTokensPerSecond: 10,
      generationTokensPerSecond: 10,
      generatedTokens: 33,
      safe: true,
    );
    expect(result.isValidFor(conservative), isFalse);
  });

  test('cancelled tuning stops before benchmarking', () async {
    final cancellation = TuningCancellationToken()..cancel();
    expect(
      () => const RuntimeAutoTuner().tune(
        conservative: conservative,
        capabilities: capabilities,
        cancellation: cancellation,
        benchmark: (_, _) async => throw StateError('must not run'),
      ),
      throwsA(isA<TuningCancelled>()),
    );
  });

  for (final rate in [
    double.nan,
    double.infinity,
    double.negativeInfinity,
    0.0,
    -1.0,
  ]) {
    for (final field in ['prompt', 'generation']) {
      test('rejects invalid conservative $field rate $rate', () async {
        var calls = 0;
        await expectLater(
          const RuntimeAutoTuner().tune(
            conservative: conservative,
            capabilities: capabilities,
            cancellation: TuningCancellationToken(),
            benchmark: (profile, _) async {
              calls++;
              return RuntimeBenchmarkResult(
                profile: profile,
                promptTokensPerSecond: field == 'prompt' ? rate : 10,
                generationTokensPerSecond: field == 'generation' ? rate : 10,
                generatedTokens: 32,
                safe: true,
              );
            },
          ),
          throwsA(isA<RuntimeTuningBaselineUnavailable>()),
        );
        expect(calls, 1, reason: 'Never tune past an unverified baseline');
      });
    }
  }

  for (final failure in [
    'unsafe',
    'short',
    'profile mismatch',
    'reported failure',
  ]) {
    test('stops when conservative baseline is $failure', () async {
      var calls = 0;
      await expectLater(
        const RuntimeAutoTuner().tune(
          conservative: conservative,
          capabilities: capabilities,
          cancellation: TuningCancellationToken(),
          benchmark: (profile, _) async {
            calls++;
            return RuntimeBenchmarkResult(
              profile: failure == 'profile mismatch'
                  ? profile.copyWith(
                      generationThreads: profile.generationThreads + 1,
                    )
                  : profile,
              promptTokensPerSecond: 10,
              generationTokensPerSecond: 10,
              generatedTokens: failure == 'short' ? 31 : 32,
              safe: failure != 'unsafe' || calls > 1,
              failureReason: failure == 'reported failure'
                  ? 'decode_error'
                  : null,
            );
          },
        ),
        throwsA(isA<RuntimeTuningBaselineUnavailable>()),
      );
      expect(calls, 1);
    });
  }

  test(
    'rejects invalid and mismatched candidates after a valid baseline',
    () async {
      var calls = 0;
      final winner = await const RuntimeAutoTuner().tune(
        conservative: conservative,
        capabilities: capabilities,
        cancellation: TuningCancellationToken(),
        benchmark: (profile, _) async {
          calls++;
          return RuntimeBenchmarkResult(
            profile: calls == 3
                ? profile.copyWith(batchSize: profile.batchSize + 1)
                : profile,
            promptTokensPerSecond: calls == 2 ? double.infinity : 10,
            generationTokensPerSecond: calls == 1 ? 10 : (calls <= 3 ? 100 : 9),
            generatedTokens: 32,
            safe: true,
          );
        },
      );
      expect(winner.profile, same(conservative));
      expect(winner.generationTokensPerSecond, 10);
    },
  );

  test('accepts an equivalent copied configuration', () async {
    final winner = await const RuntimeAutoTuner().tune(
      conservative: conservative,
      capabilities: capabilities,
      cancellation: TuningCancellationToken(),
      benchmark: (profile, _) async => RuntimeBenchmarkResult(
        profile: RuntimeProfile.fromJson(profile.toJson()),
        promptTokensPerSecond: 10,
        generationTokensPerSecond: 10,
        generatedTokens: 32,
        safe: true,
      ),
    );
    expect(winner.profile.toJson(), conservative.toJson());
  });

  for (final cancelledCall in [1, 2]) {
    test(
      'cancellation during benchmark $cancelledCall rejects its result',
      () async {
        final cancellation = TuningCancellationToken();
        var calls = 0;
        await expectLater(
          const RuntimeAutoTuner().tune(
            conservative: conservative,
            capabilities: capabilities,
            cancellation: cancellation,
            benchmark: (profile, token) async {
              calls++;
              if (calls == cancelledCall) token.cancel();
              return RuntimeBenchmarkResult(
                profile: profile,
                promptTokensPerSecond: 10,
                generationTokensPerSecond: 10,
                generatedTokens: 32,
                safe: true,
              );
            },
          ),
          throwsA(isA<TuningCancelled>()),
        );
        expect(calls, cancelledCall);
      },
    );
  }

  test(
    'Vulkan self-test probes bounded layer counts and retains best',
    () async {
      final probed = <int>[];
      final result = await const BackendSelfTest().run(
        backend: 'vulkan',
        cpuProfile: conservative,
        modelLayerCount: 28,
        cancellation: TuningCancellationToken(),
        probe: (profile, _) async {
          probed.add(profile.gpuLayers);
          return RuntimeBenchmarkResult(
            profile: profile,
            promptTokensPerSecond: 10,
            generationTokensPerSecond: profile.gpuLayers.toDouble(),
            generatedTokens: 32,
            safe: true,
          );
        },
      );
      expect(probed, [7, 14, 28]);
      expect(result.passed, isTrue);
      expect(result.offloadedLayers, 28);
    },
  );
}
