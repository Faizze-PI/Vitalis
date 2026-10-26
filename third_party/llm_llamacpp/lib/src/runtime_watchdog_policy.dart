import 'dart:async';

typedef RuntimeWatchdogTimerFactory = Timer Function(Duration, void Function());

class RuntimeWatchdogPolicy {
  const RuntimeWatchdogPolicy({
    required this.noProgressTimeout,
    required this.maximumDuration,
  });
  static const modelPreparation = RuntimeWatchdogPolicy(
    noProgressTimeout: RuntimeWatchdogDefaults.noProgressTimeout,
    maximumDuration: RuntimeWatchdogDefaults.maximumRequestDuration,
  );
  final Duration noProgressTimeout;
  final Duration maximumDuration;
  void validate() {
    if (noProgressTimeout < Duration.zero || maximumDuration < Duration.zero) {
      throw ArgumentError('Invalid runtime watchdog policy');
    }
  }
}

class RuntimeWatchdogDefaults {
  // hardcode: HC-007. Preserve backend's prior cap and generation's prior values.
  static const backendInitializationTimeout = Duration(seconds: 30);
  static const noProgressTimeout = Duration(seconds: 90);
  static const maximumRequestDuration = Duration(minutes: 30);
}
