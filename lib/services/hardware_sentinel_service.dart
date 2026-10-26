import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import '../models/device_safety_policy.dart';
import '../utils/app_logger.dart';
import 'lifecycle_manager.dart';
import 'memory_pressure_service.dart';
import 'hardware_telemetry.dart';

export 'hardware_telemetry.dart';

class HardwareSentinelException implements Exception {
  final String message;
  HardwareSentinelException(this.message);
  @override
  String toString() => message;
}

class LowPowerThrottlingException extends HardwareSentinelException {
  LowPowerThrottlingException(super.message);
}

class HardwareSentinelService implements LifecycleManager {
  static final HardwareSentinelService instance = HardwareSentinelService._();
  HardwareSentinelService._({
    DeviceSafetyPolicy policy = const DeviceSafetyPolicy(),
    DeviceSafetyClock clock = DateTime.now,
    BatteryTelemetry? battery,
    ConnectivityTelemetry? connectivity,
    DeviceSnapshotTelemetry? device,
    MemoryPressureService? memoryPressure,
    AppLogger? logger,
  }) : _policy = policy,
       _logger = logger ?? AppLogger.instance,
       _clock = clock,
       _battery = battery ?? BatteryPlusTelemetry(),
       _connectivity = connectivity ?? ConnectivityPlusTelemetry(),
       _device = device ?? const MethodChannelDeviceSnapshotTelemetry(),
       _memoryPressure = memoryPressure ?? MemoryPressureService();

  factory HardwareSentinelService.forTesting({
    DeviceSafetyPolicy policy = const DeviceSafetyPolicy(),
    required DeviceSafetyClock clock,
    required BatteryTelemetry battery,
    required ConnectivityTelemetry connectivity,
    required DeviceSnapshotTelemetry device,
    required MemoryPressureService memoryPressure,
    AppLogger? logger,
  }) => HardwareSentinelService._(
    policy: policy,
    clock: clock,
    battery: battery,
    connectivity: connectivity,
    device: device,
    memoryPressure: memoryPressure,
    logger: logger,
  );

  final BatteryTelemetry _battery;
  final AppLogger _logger;
  final ConnectivityTelemetry _connectivity;
  final DeviceSnapshotTelemetry _device;
  final MemoryPressureService _memoryPressure;
  final DeviceSafetyPolicy _policy;
  final DeviceSafetyClock _clock;

  int? _lastLevel;
  bool? _isInSaveMode;
  bool? _isCharging;
  ConnectivityResult? _connectivityType;
  int? _thermalStatus;
  bool? _systemLowMemory;
  DateTime? _safetyCooldownUntil;

  final StreamController<bool> _healthController =
      StreamController<bool>.broadcast();
  StreamSubscription? _batterySub;
  StreamSubscription? _connectivitySub;
  StreamSubscription? _memorySub;
  Timer? _healthTimer;

  int? get currentLevel => _lastLevel;
  bool? get isInSaveMode => _isInSaveMode;
  bool? get isCharging => _isCharging;
  ConnectivityResult? get connectivityType => _connectivityType;
  int get memoryPressureLevel => _memoryPressure.currentLevel;

  Stream<bool> get onHealthChanged => _healthController.stream;

  Future<void> init() async {
    try {
      _lastLevel = await _battery.level();
      _isInSaveMode = await _battery.saverEnabled();
    } catch (error) {
      _lastLevel = null;
      _isInSaveMode = null;
      _logger.warning('Battery telemetry unavailable (${error.runtimeType})');
    }

    try {
      final results = await _connectivity.current();
      _connectivityType = results.isNotEmpty
          ? results.first
          : ConnectivityResult.none;
    } catch (error) {
      _connectivityType = null;
      _logger.warning('Network telemetry unavailable (${error.runtimeType})');
    }

    await _refreshDeviceSnapshot();

    _memoryPressure.startListening();
    _memorySub = _memoryPressure.onMemoryPressure.listen((level) {
      if (!_isDisposed) {
        if (_policy.shouldStartCooldown(_snapshot())) {
          _safetyCooldownUntil = _clock().add(_policy.cooldown);
        }
        _healthController.add(_computeCurrentSafety());
      }
    });

    _batterySub = _battery.states.listen((state) async {
      _isCharging =
          state == BatteryState.charging || state == BatteryState.full;
      if (_isCharging == true) {
        try {
          _lastLevel = await _battery.level();
          _isInSaveMode = await _battery.saverEnabled();
        } catch (error) {
          _lastLevel = null;
          _isInSaveMode = null;
          _logger.warning(
            'Charging telemetry refresh failed (${error.runtimeType})',
          );
        }
      }
    });

    _connectivitySub = _connectivity.changes.listen((results) {
      _connectivityType = results.isNotEmpty
          ? results.first
          : ConnectivityResult.none;
    });

    _healthTimer = Timer.periodic(_policy.pollInterval, (_) async {
      if (_isDisposed) return;
      try {
        _lastLevel = await _battery.level();
        _isInSaveMode = await _battery.saverEnabled();
      } catch (error) {
        _lastLevel = null;
        _isInSaveMode = null;
        _logger.warning(
          'Battery telemetry refresh failed (${error.runtimeType})',
        );
      }
      await _refreshDeviceSnapshot();
      if (!_isDisposed) {
        _healthController.add(_computeCurrentSafety());
      }
    });
  }

  bool _computeCurrentSafety() {
    return unsafeReasonHeavy() == null;
  }

  bool isSafeForHeavyOperation() {
    return unsafeReasonHeavy() == null;
  }

  bool isSafeForDownload() {
    if (!isSafeForHeavyOperation()) return false;
    if (_connectivityType == ConnectivityResult.none) return false;
    return true;
  }

  String? unsafeReasonHeavy() {
    return _policy.unsafeReason(_snapshot(), _clock());
  }

  DeviceSafetySnapshot _snapshot() => DeviceSafetySnapshot(
    batteryLevel: _lastLevel,
    isCharging: _isCharging,
    batterySaver: _isInSaveMode,
    thermalStatus: _thermalStatus,
    trimMemoryLevel: _memoryPressure.currentLevel,
    systemLowMemory: _systemLowMemory,
    cooldownUntil: _safetyCooldownUntil,
  );

  Future<void> _refreshDeviceSnapshot() async {
    try {
      final snapshot = await _device.snapshot();
      if (snapshot == null) return;
      _thermalStatus = snapshot['thermalStatus'] as int?;
      _systemLowMemory = snapshot['lowMemory'] as bool?;
      if (_policy.shouldStartCooldown(_snapshot())) {
        _safetyCooldownUntil = _clock().add(_policy.cooldown);
      }
      _isInSaveMode = snapshot['powerSaveMode'] as bool? ?? _isInSaveMode;
    } on MissingPluginException {
      _thermalStatus = null;
    } catch (error) {
      _thermalStatus = null;
      _systemLowMemory = null;
      _logger.warning(
        'Device safety telemetry unavailable (${error.runtimeType})',
      );
    }
  }

  String? unsafeReasonDownload() {
    if (!isSafeForHeavyOperation()) return unsafeReasonHeavy();
    if (_connectivityType == ConnectivityResult.none) {
      return 'No internet connection. Connect to continue.';
    }
    return null;
  }

  void checkHeavyOperation() {
    if (!isSafeForHeavyOperation()) {
      throw LowPowerThrottlingException(unsafeReasonHeavy()!);
    }
  }

  void checkDownload() {
    if (!isSafeForDownload()) {
      final reason = unsafeReasonDownload();
      if (reason != null) {
        throw LowPowerThrottlingException(reason);
      }
    }
  }

  bool _isDisposed = false;

  @override
  bool get isDisposed => _isDisposed;

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _batterySub?.cancel();
    _connectivitySub?.cancel();
    _memorySub?.cancel();
    _healthTimer?.cancel();
    _memoryPressure.dispose();
    _healthController.close();
  }
}
