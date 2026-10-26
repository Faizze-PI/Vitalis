import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/models/generation_watchdog_policy.dart';

void main() {
  test('preparation derives the existing generation deadline values', () {
    const policy = RuntimeWatchdogPolicy.modelPreparation;
    policy.validate();
    expect(
      policy.noProgressTimeout,
      GenerationWatchdogPolicy.conservative.noProgressTimeout,
    );
    expect(
      policy.maximumDuration,
      GenerationWatchdogPolicy.conservative.maximumRequestDuration,
    );
    expect(
      GenerationWatchdogPolicy.conservative.cancellationAcknowledgementTimeout,
      policy.noProgressTimeout,
    );
    expect(
      RuntimeWatchdogDefaults.backendInitializationTimeout,
      const Duration(seconds: 30),
    );
  });
  test('negative override values are rejected', () {
    for (final policy in [
      const RuntimeWatchdogPolicy(
        noProgressTimeout: Duration(seconds: -1),
        maximumDuration: Duration.zero,
      ),
      const RuntimeWatchdogPolicy(
        noProgressTimeout: Duration.zero,
        maximumDuration: Duration(seconds: -1),
      ),
    ]) {
      expect(policy.validate, throwsArgumentError);
    }
  });
  test('zero deadlines are explicit valid fault-test overrides', () {
    const RuntimeWatchdogPolicy(
      noProgressTimeout: Duration.zero,
      maximumDuration: Duration.zero,
    ).validate();
  });
}
