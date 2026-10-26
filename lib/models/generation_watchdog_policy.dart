import 'dart:async';
import 'package:llm_llamacpp/src/runtime_watchdog_policy.dart';

typedef WatchdogTimerFactory = Timer Function(Duration, void Function());

class GenerationWatchdogPolicy {
  const GenerationWatchdogPolicy({
    required this.noProgressTimeout,
    required this.maximumRequestDuration,
  });

  /// Conservative defaults: a stalled decoder is cancelled quickly while a
  /// healthy long response can continue well beyond the old fixed limit.
  static const conservative = GenerationWatchdogPolicy(
    noProgressTimeout: RuntimeWatchdogDefaults.noProgressTimeout,
    maximumRequestDuration: RuntimeWatchdogDefaults.maximumRequestDuration,
  );

  final Duration noProgressTimeout;
  final Duration maximumRequestDuration;

  /// Waiting for shutdown uses the existing inactivity allowance, not an
  /// assumption that expiry has stopped native work (hardcode: HC-007).
  Duration get cancellationAcknowledgementTimeout => noProgressTimeout;
}
