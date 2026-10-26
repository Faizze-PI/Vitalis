import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/runtime_auto_tuner.dart';
import 'package:vitalis_app/services/runtime_benchmark_workload.dart';

void main() {
  int units(String text) =>
      text.substring(RuntimeBenchmarkPolicy.instruction.length).length ~/
      RuntimeBenchmarkPolicy.paddingUnit.length;
  Future<RuntimeBenchmarkWorkload> build(
    Future<int> Function(String) count, {
    void Function()? check,
    int contextSize = 1024,
  }) => RuntimeBenchmarkWorkload.create(
    countPromptTokens: count,
    checkCurrent: check ?? () {},
    contextSize: contextSize,
  );
  test(
    'complete template token count reaches exactly the fixed workload',
    () async {
      var queries = 0;
      final workload = await build((text) async {
        queries++;
        return 17 + units(text);
      });
      expect(17 + units(workload.prompt), 256);
      expect(queries, lessThan(12));
    },
  );
  test('non-monotonic tokenizer uses bounded exhaustive fallback', () async {
    var queries = 0;
    final workload = await build((text) async {
      queries++;
      return units(text) == 3 ? 256 : 100;
    });
    expect(units(workload.prompt), 3);
    expect(queries, lessThanOrEqualTo(258));
  });
  test(
    'unreachable exact count fails instead of rounding or estimating',
    () async {
      var queries = 0;
      await expectLater(
        build((_) async {
          queries++;
          return 255;
        }),
        throwsA(isA<RuntimeBenchmarkWorkloadUnavailable>()),
      );
      expect(queries, 257);
    },
  );
  test(
    'template changes between construction and verification are rejected',
    () async {
      var queries = 0;
      await expectLater(
        build((_) async => ++queries == 1 ? 256 : 255),
        throwsA(isA<RuntimeBenchmarkWorkloadUnavailable>()),
      );
    },
  );
  test('invalid native token count is rejected', () async {
    await expectLater(
      build((_) async => -1),
      throwsA(isA<RuntimeBenchmarkWorkloadUnavailable>()),
    );
  });
  test(
    'context includes the fixed reserved output before tokenizing',
    () async {
      var queries = 0;
      await expectLater(
        build((_) async {
          queries++;
          return 256;
        }, contextSize: 287),
        throwsA(isA<RuntimeBenchmarkWorkloadUnavailable>()),
      );
      expect(queries, 0);
      expect(
        await build((_) async => 256, contextSize: 288),
        isA<RuntimeBenchmarkWorkload>(),
      );
    },
  );
  test(
    'cancellation after asynchronous tokenization stops further requests',
    () async {
      final cancellation = TuningCancellationToken();
      var queries = 0;
      await expectLater(
        build((_) async {
          queries++;
          cancellation.cancel();
          return 100;
        }, check: cancellation.throwIfCancelled),
        throwsA(isA<TuningCancelled>()),
      );
      expect(queries, 1);
    },
  );
  test(
    'cancellation after final token verification rejects the workload',
    () async {
      final cancellation = TuningCancellationToken();
      var queries = 0;
      await expectLater(
        build((_) async {
          if (++queries == 2) cancellation.cancel();
          return 256;
        }, check: cancellation.throwIfCancelled),
        throwsA(isA<TuningCancelled>()),
      );
      expect(queries, 2);
    },
  );
}
