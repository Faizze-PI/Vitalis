import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/runtime_capabilities_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android snapshot parser preserves explicit capabilities', () {
    final result = parseAndroidRuntimeCapabilities({
      'logicalProcessors': 8,
      'performanceProcessors': 4,
      'deviceFingerprint': 'device/build',
      'supportedAbis': ['arm64-v8a'],
      'packagedBackends': ['cpu', 'vulkan'],
      'availableMemoryBytes': 1024,
      'totalMemoryBytes': 2048,
      'processRssBytes': 256,
      'thermalStatus': 2,
      'lowMemory': false,
    }, fallbackLogicalProcessors: 2);

    expect(result.logicalProcessors, 8);
    expect(result.performanceProcessors, 4);
    expect(result.deviceFingerprint, 'device/build');
    expect(result.abis, ['arm64-v8a']);
    expect(result.packagedBackends, {'cpu', 'vulkan'});
    expect(result.availableMemoryBytes, 1024);
    expect(result.totalMemoryBytes, 2048);
    expect(result.processRssBytes, 256);
    expect(result.thermalStatus, 2);
    expect(result.lowMemory, isFalse);
  });

  test('Android parser uses conservative missing-value defaults', () {
    final result = parseAndroidRuntimeCapabilities(
      const {},
      fallbackLogicalProcessors: 6,
    );

    expect(result.logicalProcessors, 6);
    expect(result.performanceProcessors, isNull);
    expect(result.deviceFingerprint, 'android-unknown');
    expect(result.abis, isEmpty);
    expect(result.packagedBackends, {'cpu'});
    expect(result.availableMemoryBytes, isNull);
  });

  test('desktop provider returns conservative capabilities', () async {
    const provider = AndroidRuntimeCapabilitiesProvider(
      channel: MethodChannel('unused-test-channel'),
    );

    final result = await provider.snapshot();

    expect(result.logicalProcessors, greaterThanOrEqualTo(1));
    expect(result.logicalProcessors, lessThanOrEqualTo(32));
    expect(result.packagedBackends, {'cpu'});
    expect(result.deviceFingerprint, contains('-unknown'));
  });

  test('Android provider maps a platform snapshot', () async {
    const channel = MethodChannel('runtime-capabilities-success');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'snapshot');
          return <String, dynamic>{
            'deviceFingerprint': 'fixture',
            'logicalProcessors': 7,
            'packagedBackends': <String>['cpu'],
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    const provider = AndroidRuntimeCapabilitiesProvider(
      channel: channel,
      isAndroid: true,
      logicalProcessors: 3,
    );
    final result = await provider.snapshot();

    expect(result.deviceFingerprint, 'fixture');
    expect(result.logicalProcessors, 7);
  });

  test('Android provider falls back on null and platform failures', () async {
    const nullChannel = MethodChannel('runtime-capabilities-null');
    const errorChannel = MethodChannel('runtime-capabilities-error');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(nullChannel, (_) async => null);
    messenger.setMockMethodCallHandler(
      errorChannel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    addTearDown(() {
      messenger.setMockMethodCallHandler(nullChannel, null);
      messenger.setMockMethodCallHandler(errorChannel, null);
    });

    final nullResult = await const AndroidRuntimeCapabilitiesProvider(
      channel: nullChannel,
      isAndroid: true,
      logicalProcessors: 9,
    ).snapshot();
    final errorResult = await const AndroidRuntimeCapabilitiesProvider(
      channel: errorChannel,
      isAndroid: true,
      logicalProcessors: 9,
    ).snapshot();

    expect(nullResult.logicalProcessors, 9);
    expect(errorResult.logicalProcessors, 9);
    expect(errorResult.deviceFingerprint, contains('-unknown'));
  });
}
