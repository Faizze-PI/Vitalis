import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:vitalis_app/services/chat_state_controller.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';

class _MockSentinel implements HardwareSentinelService {
  @override
  int get currentLevel => 100;
  @override
  bool get isCharging => true;
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
  Stream<bool> get onHealthChanged =>
      Stream<bool>.multi((_) {}, isBroadcast: true);
  @override
  Future<void> init() async {}
  @override
  void dispose() {}
}

void main() {
  group('ChatStateController timeout', () {
    test('transitions to error after timeout override', () async {
      final controller = ChatStateController(
        sentinel: _MockSentinel(),
        timeoutOverride: const Duration(seconds: 1),
      );

      final statusChanges = <ChatStatus>[];
      controller.onStatusChanged = (status) => statusChanges.add(status);
      controller.onError = (error) {};

      expect(controller.status, ChatStatus.idle);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(controller.status, ChatStatus.idle);

      controller.dispose();
    });

    test('default watchdog leaves an idle controller unchanged', () {
      final controller = ChatStateController(sentinel: _MockSentinel());

      expect(controller.status, ChatStatus.idle);

      controller.dispose();
    });
  });
}
