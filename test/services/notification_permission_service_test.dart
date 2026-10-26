import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/notification_permission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('vitalis/device_safety');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('maps native granted status', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => {'status': 'granted'},
        );

    final status = await NotificationPermissionService(
      channel: channel,
      isAndroid: _android,
    ).ensureForDownload();

    expect(status, NotificationPermissionStatus.granted);
  });
}

bool _android() => true;
