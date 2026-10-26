import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';

abstract interface class BatteryTelemetry {
  Future<int> level();
  Future<bool> saverEnabled();
  Stream<BatteryState> get states;
}

final class BatteryPlusTelemetry implements BatteryTelemetry {
  BatteryPlusTelemetry([Battery? battery]) : _battery = battery ?? Battery();
  final Battery _battery;

  @override
  Future<int> level() => _battery.batteryLevel;
  @override
  Future<bool> saverEnabled() => _battery.isInBatterySaveMode;
  @override
  Stream<BatteryState> get states => _battery.onBatteryStateChanged;
}

abstract interface class ConnectivityTelemetry {
  Future<List<ConnectivityResult>> current();
  Stream<List<ConnectivityResult>> get changes;
}

final class ConnectivityPlusTelemetry implements ConnectivityTelemetry {
  ConnectivityPlusTelemetry([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();
  final Connectivity _connectivity;

  @override
  Future<List<ConnectivityResult>> current() =>
      _connectivity.checkConnectivity();
  @override
  Stream<List<ConnectivityResult>> get changes =>
      _connectivity.onConnectivityChanged;
}

abstract interface class DeviceSnapshotTelemetry {
  Future<Map<String, dynamic>?> snapshot();
}

final class MethodChannelDeviceSnapshotTelemetry
    implements DeviceSnapshotTelemetry {
  const MethodChannelDeviceSnapshotTelemetry({
    MethodChannel channel = const MethodChannel('vitalis/device_safety'),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<Map<String, dynamic>?> snapshot() =>
      _channel.invokeMapMethod<String, dynamic>('snapshot');
}
