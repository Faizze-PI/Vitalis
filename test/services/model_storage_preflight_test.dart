import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/model_download_manager.dart';
import 'package:vitalis_app/services/model_downloader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('vitalis/model_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final readers = <String, Future<int?> Function()>{
    'library': const ApplicationModelFileStore().usableBytes,
    'bundled': AndroidModelDownloadEnvironment().usableStorageBytes,
  };

  const paths = MethodChannel('plugins.flutter.io/path_provider');
  setUp(
    () => messenger.setMockMethodCallHandler(paths, (call) async {
      expect(call.method, 'getApplicationSupportDirectory');
      return Directory.systemTemp.path;
    }),
  );
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(paths, null);
  });

  for (final reader in readers.entries) {
    test(
      '${reader.key} queries allocatable storage instead of telemetry',
      () async {
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return 123456;
        });
        expect(await reader.value(), 123456);
        expect(calls.map((call) => call.method), ['allocatableBytes']);
        expect(
          calls.single.arguments,
          Platform.isWindows ? isA<String>() : isNull,
        );
      },
    );

    test(
      '${reader.key} rejects malformed or negative storage values',
      () async {
        for (final value in <Object?>[-1, 1.5, '123', null]) {
          messenger.setMockMethodCallHandler(channel, (_) async => value);
          expect(await reader.value(), isNull);
        }
      },
    );

    test(
      '${reader.key} treats platform failure and absence as unknown',
      () async {
        messenger.setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'storage_unavailable');
        });
        expect(await reader.value(), isNull);
        messenger.setMockMethodCallHandler(channel, null);
        expect(await reader.value(), isNull);
      },
    );
  }
}
