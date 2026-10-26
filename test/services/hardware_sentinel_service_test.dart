import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/device_safety_policy.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';
import 'package:vitalis_app/services/memory_pressure_service.dart';

void main() {
  late StreamController<BatteryState> batteryStates;
  late StreamController<List<ConnectivityResult>> connectivityChanges;
  late StreamController<dynamic> memoryEvents;

  setUp(() {
    batteryStates = StreamController<BatteryState>.broadcast();
    connectivityChanges =
        StreamController<List<ConnectivityResult>>.broadcast();
    memoryEvents = StreamController<dynamic>.broadcast();
  });

  tearDown(() async {
    await batteryStates.close();
    await connectivityChanges.close();
    await memoryEvents.close();
  });

  HardwareSentinelService createSentinel({
    int level = 80,
    bool saver = false,
    List<ConnectivityResult> connectivity = const [ConnectivityResult.wifi],
    Map<String, dynamic>? snapshot = const {
      'thermalStatus': 0,
      'lowMemory': false,
      'powerSaveMode': false,
    },
    DeviceSafetyPolicy policy = const DeviceSafetyPolicy(
      pollInterval: Duration(days: 1),
    ),
    DateTime? now,
  }) {
    return HardwareSentinelService.forTesting(
      policy: policy,
      clock: () => now ?? DateTime.utc(2026),
      battery: _BatteryFixture(
        levelValue: level,
        saverValue: saver,
        stateValues: batteryStates.stream,
      ),
      connectivity: _ConnectivityFixture(
        currentValue: connectivity,
        changeValues: connectivityChanges.stream,
      ),
      device: _DeviceFixture(snapshot),
      memoryPressure: MemoryPressureService(
        policy: policy,
        eventStream: () => memoryEvents.stream,
      ),
    );
  }

  test('initial telemetry permits safe inference and download', () async {
    final service = createSentinel();
    addTearDown(service.dispose);

    await service.init();

    expect(service.currentLevel, 80);
    expect(service.connectivityType, ConnectivityResult.wifi);
    expect(service.isSafeForHeavyOperation(), isTrue);
    expect(service.isSafeForDownload(), isTrue);
    expect(service.checkHeavyOperation, returnsNormally);
    expect(service.checkDownload, returnsNormally);
  });

  test('charging does not clear Battery Saver protection', () async {
    final service = createSentinel(saver: true);
    addTearDown(service.dispose);
    await service.init();

    batteryStates.add(BatteryState.charging);
    await Future<void>.delayed(Duration.zero);

    expect(service.isCharging, isTrue);
    expect(service.isInSaveMode, isTrue);
    expect(service.isSafeForHeavyOperation(), isFalse);
    expect(
      service.checkHeavyOperation,
      throwsA(isA<LowPowerThrottlingException>()),
    );
  });

  test('critical memory starts cooldown and blocks heavy work', () async {
    final service = createSentinel();
    addTearDown(service.dispose);
    await service.init();

    memoryEvents.add({'trimMemoryLevel': 90});
    await Future<void>.delayed(Duration.zero);

    expect(service.memoryPressureLevel, 90);
    expect(service.unsafeReasonHeavy(), contains('memory'));
  });

  test('offline connectivity blocks only downloads', () async {
    final service = createSentinel(
      connectivity: const [ConnectivityResult.none],
    );
    addTearDown(service.dispose);
    await service.init();

    expect(service.isSafeForHeavyOperation(), isTrue);
    expect(service.isSafeForDownload(), isFalse);
    expect(service.unsafeReasonDownload(), contains('No internet'));
    expect(service.checkDownload, throwsA(isA<LowPowerThrottlingException>()));

    connectivityChanges.add(const [ConnectivityResult.mobile]);
    await Future<void>.delayed(Duration.zero);
    expect(service.isSafeForDownload(), isTrue);
  });

  test(
    'missing device plugin remains an unknown non-fabricated state',
    () async {
      final service = HardwareSentinelService.forTesting(
        clock: () => DateTime.utc(2026),
        battery: _BatteryFixture(
          levelValue: 70,
          saverValue: false,
          stateValues: batteryStates.stream,
        ),
        connectivity: _ConnectivityFixture(
          currentValue: const [ConnectivityResult.wifi],
          changeValues: connectivityChanges.stream,
        ),
        device: const _ThrowingDeviceFixture(),
        memoryPressure: MemoryPressureService(
          eventStream: () => memoryEvents.stream,
        ),
      );
      addTearDown(service.dispose);

      await service.init();

      expect(service.currentLevel, 70);
      expect(service.isSafeForHeavyOperation(), isTrue);
    },
  );

  test('dispose is idempotent', () async {
    final service = createSentinel();
    await service.init();
    service.dispose();

    expect(service.isDisposed, isTrue);
    expect(service.dispose, returnsNormally);
  });

  test('telemetry failures remain conservative and observable', () async {
    final service = HardwareSentinelService.forTesting(
      clock: () => DateTime.utc(2026),
      battery: _ThrowingBatteryFixture(batteryStates.stream),
      connectivity: _ThrowingConnectivityFixture(connectivityChanges.stream),
      device: const _GenericThrowingDeviceFixture(),
      memoryPressure: MemoryPressureService(
        eventStream: () => memoryEvents.stream,
      ),
    );
    addTearDown(service.dispose);

    await service.init();

    expect(service.currentLevel, isNull);
    expect(service.isInSaveMode, isNull);
    expect(service.connectivityType, isNull);
    expect(service.isSafeForHeavyOperation(), isTrue);
  });

  test('charging refresh failure clears stale battery telemetry', () async {
    Object? refreshFailure;
    final battery = _MutableBatteryFixture(
      states: batteryStates.stream,
      levelValue: () {
        if (refreshFailure != null) throw refreshFailure;
        return 75;
      },
      saverValue: () {
        if (refreshFailure != null) throw refreshFailure;
        return false;
      },
    );
    final service = HardwareSentinelService.forTesting(
      clock: () => DateTime.utc(2026),
      battery: battery,
      connectivity: _ConnectivityFixture(
        currentValue: const [ConnectivityResult.wifi],
        changeValues: connectivityChanges.stream,
      ),
      device: const _DeviceFixture(null),
      memoryPressure: MemoryPressureService(
        eventStream: () => memoryEvents.stream,
      ),
    );
    addTearDown(service.dispose);
    await service.init();

    refreshFailure = StateError('battery unavailable');
    batteryStates.add(BatteryState.full);
    await Future<void>.delayed(Duration.zero);

    expect(service.isCharging, isTrue);
    expect(service.currentLevel, isNull);
    expect(service.isInSaveMode, isNull);
  });

  test('periodic refresh publishes updated safety', () async {
    final service = createSentinel(
      snapshot: const {'thermalStatus': 3, 'lowMemory': false},
      policy: const DeviceSafetyPolicy(
        pollInterval: Duration(milliseconds: 5),
        cooldown: Duration(milliseconds: 20),
      ),
    );
    addTearDown(service.dispose);
    final event = Completer<bool>();
    final subscription = service.onHealthChanged.listen((safe) {
      if (!event.isCompleted) event.complete(safe);
    });
    addTearDown(subscription.cancel);

    await service.init();
    // Observe completion, not an assumed scheduler deadline under host load.
    // The test runner's timeout still fails a missing periodic publication.
    expect(await event.future, isFalse);
  });
}

final class _BatteryFixture implements BatteryTelemetry {
  const _BatteryFixture({
    required this.levelValue,
    required this.saverValue,
    required this.stateValues,
  });

  final int levelValue;
  final bool saverValue;
  final Stream<BatteryState> stateValues;

  @override
  Future<int> level() async => levelValue;
  @override
  Future<bool> saverEnabled() async => saverValue;
  @override
  Stream<BatteryState> get states => stateValues;
}

final class _ConnectivityFixture implements ConnectivityTelemetry {
  const _ConnectivityFixture({
    required this.currentValue,
    required this.changeValues,
  });

  final List<ConnectivityResult> currentValue;
  final Stream<List<ConnectivityResult>> changeValues;

  @override
  Stream<List<ConnectivityResult>> get changes => changeValues;
  @override
  Future<List<ConnectivityResult>> current() async => currentValue;
}

final class _DeviceFixture implements DeviceSnapshotTelemetry {
  const _DeviceFixture(this.value);
  final Map<String, dynamic>? value;

  @override
  Future<Map<String, dynamic>?> snapshot() async => value;
}

final class _ThrowingDeviceFixture implements DeviceSnapshotTelemetry {
  const _ThrowingDeviceFixture();

  @override
  Future<Map<String, dynamic>?> snapshot() =>
      throw MissingPluginException('fixture');
}

final class _GenericThrowingDeviceFixture implements DeviceSnapshotTelemetry {
  const _GenericThrowingDeviceFixture();

  @override
  Future<Map<String, dynamic>?> snapshot() =>
      throw StateError('device unavailable');
}

final class _ThrowingBatteryFixture implements BatteryTelemetry {
  const _ThrowingBatteryFixture(this.states);

  @override
  final Stream<BatteryState> states;

  @override
  Future<int> level() => throw StateError('battery unavailable');

  @override
  Future<bool> saverEnabled() => throw StateError('battery unavailable');
}

final class _ThrowingConnectivityFixture implements ConnectivityTelemetry {
  const _ThrowingConnectivityFixture(this.changes);

  @override
  final Stream<List<ConnectivityResult>> changes;

  @override
  Future<List<ConnectivityResult>> current() =>
      throw StateError('network unavailable');
}

final class _MutableBatteryFixture implements BatteryTelemetry {
  const _MutableBatteryFixture({
    required this.states,
    required this.levelValue,
    required this.saverValue,
  });

  @override
  final Stream<BatteryState> states;
  final int Function() levelValue;
  final bool Function() saverValue;

  @override
  Future<int> level() async => levelValue();

  @override
  Future<bool> saverEnabled() async => saverValue();
}
