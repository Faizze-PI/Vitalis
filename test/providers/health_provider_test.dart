import 'package:flutter_test/flutter_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:vitalis_app/providers/health_provider.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';

class _MockSentinel implements HardwareSentinelService {
  @override
  int get currentLevel => 85;
  @override
  bool get isCharging => false;
  @override
  bool get isInSaveMode => false;
  @override
  bool get isDisposed => false;
  @override
  ConnectivityResult get connectivityType => ConnectivityResult.wifi;
  @override
  int get memoryPressureLevel => 0;
  @override
  bool isSafeForHeavyOperation() => true;
  @override
  bool isSafeForDownload() => true;
  @override
  String? unsafeReasonHeavy() => null;
  @override
  String? unsafeReasonDownload() => null;
  @override
  void checkHeavyOperation() {}
  @override
  void checkDownload() {}
  @override
  Stream<bool> get onHealthChanged => const Stream.empty();
  @override
  Future<void> init() async {}
  @override
  void dispose() {}
}

class _UnsafeSentinel implements HardwareSentinelService {
  @override
  int get currentLevel => 15;
  @override
  bool get isCharging => false;
  @override
  bool get isInSaveMode => true;
  @override
  bool get isDisposed => false;
  @override
  ConnectivityResult get connectivityType => ConnectivityResult.none;
  @override
  int get memoryPressureLevel => 0;
  @override
  bool isSafeForHeavyOperation() => false;
  @override
  bool isSafeForDownload() => false;
  @override
  String? unsafeReasonHeavy() => 'Battery too low';
  @override
  String? unsafeReasonDownload() => 'No connectivity';
  @override
  void checkHeavyOperation() {}
  @override
  void checkDownload() {}
  @override
  Stream<bool> get onHealthChanged => const Stream.empty();
  @override
  Future<void> init() async {}
  @override
  void dispose() {}
}

void main() {
  group('HealthProvider', () {
    test('initial state reflects sentinel values', () {
      final provider = HealthProvider(sentinel: _MockSentinel());
      expect(provider.batteryLevel, 85);
      expect(provider.isCharging, false);
      expect(provider.batterySaver, false);
      expect(provider.isSafeForHeavy, true);
      expect(provider.isSafeForDownload, true);
    });

    test('unsafe sentinel reflects low battery and no connectivity', () {
      final provider = HealthProvider(sentinel: _UnsafeSentinel());
      expect(provider.batteryLevel, 15);
      expect(provider.isSafeForHeavy, false);
      expect(provider.isSafeForDownload, false);
      expect(provider.batterySaver, true);
    });

    test('dispose stops timer', () async {
      final provider = HealthProvider(sentinel: _MockSentinel());
      await Future.delayed(const Duration(milliseconds: 100));
      provider.dispose();
      expect(provider.rssMb, greaterThanOrEqualTo(0));
    });

    test('rssMb is non-negative after construction', () {
      final provider = HealthProvider(sentinel: _MockSentinel());
      expect(provider.rssMb, greaterThanOrEqualTo(0));
    });
  });
}
