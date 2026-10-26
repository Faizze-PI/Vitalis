typedef DeviceSafetyClock = DateTime Function();

class DeviceSafetySnapshot {
  const DeviceSafetySnapshot({
    this.batteryLevel,
    this.isCharging,
    this.batterySaver,
    this.thermalStatus,
    this.trimMemoryLevel,
    this.systemLowMemory,
    this.cooldownUntil,
  });

  final int? batteryLevel;
  final bool? isCharging;
  final bool? batterySaver;
  final int? thermalStatus;
  final int? trimMemoryLevel;
  final bool? systemLowMemory;
  final DateTime? cooldownUntil;
}

/// Single authority for runtime safety thresholds and timing.
class DeviceSafetyPolicy {
  const DeviceSafetyPolicy({
    this.minimumUnpluggedBatteryPercent = 15,
    this.moderateThermalStatus = 2,
    this.severeThermalStatus = 3,
    this.criticalTrimMemoryLevel = 80,
    this.cooldown = const Duration(seconds: 30),
    this.pollInterval = const Duration(seconds: 5),
  });

  final int minimumUnpluggedBatteryPercent;
  final int moderateThermalStatus;
  final int severeThermalStatus;
  final int criticalTrimMemoryLevel;
  final Duration cooldown;
  final Duration pollInterval;

  bool isCriticalMemory(DeviceSafetySnapshot snapshot) =>
      snapshot.systemLowMemory == true ||
      (snapshot.trimMemoryLevel != null &&
          snapshot.trimMemoryLevel! >= criticalTrimMemoryLevel);

  bool shouldStartCooldown(DeviceSafetySnapshot snapshot) =>
      (snapshot.thermalStatus != null &&
          snapshot.thermalStatus! >= severeThermalStatus) ||
      isCriticalMemory(snapshot);

  String? unsafeReason(DeviceSafetySnapshot snapshot, DateTime now) {
    if (snapshot.isCharging == false &&
        snapshot.batteryLevel != null &&
        snapshot.batteryLevel! < minimumUnpluggedBatteryPercent) {
      return 'Battery is critically low (${snapshot.batteryLevel}%). Plug in your device to continue.';
    }
    if (snapshot.batterySaver == true) {
      return 'Battery Saver is active. Heavy inference is paused to protect battery life.';
    }
    if (snapshot.thermalStatus != null &&
        snapshot.thermalStatus! >= severeThermalStatus) {
      return 'Device temperature is too high for safe local inference. Let it cool before continuing.';
    }
    if (isCriticalMemory(snapshot)) {
      return 'Device memory is critically low. Close some apps and try again.';
    }
    if (snapshot.cooldownUntil != null &&
        now.isBefore(snapshot.cooldownUntil!)) {
      return 'Device safety cooldown is active. Wait briefly before resuming local inference.';
    }
    return null;
  }
}
