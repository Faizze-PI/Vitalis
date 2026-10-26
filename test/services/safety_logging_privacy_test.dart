import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/device_safety_policy.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';
import 'package:vitalis_app/services/memory_pressure_service.dart';
import 'package:vitalis_app/utils/app_logger.dart';

const _privateMarker = 'PRIVATE_TELEMETRY_EXCEPTION_FIXTURE';

void main() {
  for (final privacy in [true, false]) {
    for (final failure in [
      'battery',
      'network',
      'device',
      'charging',
      'periodic',
      'memoryStart',
      'memoryStream',
    ]) {
      test('$failure logs exclude payload privacy=$privacy', () async {
        final parent = await Directory.systemTemp.resolveSymbolicLinks();
        final root = await Directory(parent).createTemp('vitalis_safety_logs_');
        final owned = await root.resolveSymbolicLinks();
        if (!owned.startsWith('$parent${Platform.pathSeparator}')) {
          throw StateError('Log fixture escaped its temporary parent');
        }
        final logger = AppLogger.forTesting(
          directoryResolver: () async => root,
          privacyLoader: () async => privacy,
          privacySaver: (_) async {},
          clock: () => DateTime.utc(2026, 10, 25),
        );
        final battery = _Battery(failure);
        final events = StreamController<dynamic>.broadcast(sync: true);
        final memory = MemoryPressureService(
          logger: logger,
          eventStream: () {
            if (failure == 'memoryStart') throw const _TelemetryFailure();
            return events.stream;
          },
        );
        final sentinel = HardwareSentinelService.forTesting(
          logger: logger,
          clock: () => DateTime.utc(2026),
          policy: DeviceSafetyPolicy(
            pollInterval: failure == 'periodic'
                ? const Duration(milliseconds: 10)
                : const Duration(days: 1),
          ),
          battery: battery,
          connectivity: _Connectivity(failure),
          device: _Device(failure),
          memoryPressure: memory,
        );
        addTearDown(() async {
          sentinel.dispose();
          await battery.statesController.close();
          await events.close();
          await logger.flush();
          if (await root.resolveSymbolicLinks() != owned) {
            throw StateError('Log fixture ownership changed');
          }
          await root.delete(recursive: true);
        });
        await logger.loadPersistedState();
        await sentinel.init();
        if (failure == 'charging') {
          battery.statesController.add(BatteryState.charging);
          await battery.failed.future;
        } else if (failure == 'periodic') {
          await battery.failed.future;
        } else if (failure == 'memoryStream') {
          events.addError(const _TelemetryFailure());
        }
        // Observe asynchronous error handling, not an assumed wall-clock delay.
        await Future<void>.delayed(Duration.zero);
        sentinel.dispose();
        await logger.flush();
        final logs = await logger.getLogs();
        expect(logs, contains('_TelemetryFailure'));
        expect(
          logs,
          contains(failure.startsWith('memory') ? '[ERROR]' : '[WARN]'),
        );
        final files = await root
            .list(recursive: true)
            .where((entry) => entry is File)
            .cast<File>()
            .toList();
        expect(files, isNotEmpty);
        for (final file in files) {
          expect(await file.readAsString(), isNot(contains(_privateMarker)));
        }
        expect(logs, isNot(contains(_privateMarker)));
      });
    }
  }
}

final class _TelemetryFailure implements Exception {
  const _TelemetryFailure();
  @override
  String toString() => '_TelemetryFailure: $_privateMarker';
}

final class _Battery implements BatteryTelemetry {
  _Battery(this.failure);
  final String failure;
  int reads = 0;
  final failed = Completer<void>();
  final statesController = StreamController<BatteryState>.broadcast(sync: true);
  @override
  Future<int> level() async {
    reads++;
    if (failure == 'battery' ||
        (reads > 1 && (failure == 'charging' || failure == 'periodic'))) {
      if (!failed.isCompleted) failed.complete();
      throw const _TelemetryFailure();
    }
    return 80;
  }

  @override
  Future<bool> saverEnabled() async => false;
  @override
  Stream<BatteryState> get states => statesController.stream;
}

final class _Connectivity implements ConnectivityTelemetry {
  _Connectivity(this.failure);
  final String failure;
  @override
  Future<List<ConnectivityResult>> current() async {
    if (failure == 'network') throw const _TelemetryFailure();
    return [ConnectivityResult.wifi];
  }

  @override
  Stream<List<ConnectivityResult>> get changes => const Stream.empty();
}

final class _Device implements DeviceSnapshotTelemetry {
  _Device(this.failure);
  final String failure;
  @override
  Future<Map<String, dynamic>?> snapshot() async {
    if (failure == 'device') throw const _TelemetryFailure();
    return {'thermalStatus': 0, 'lowMemory': false, 'powerSaveMode': false};
  }
}
