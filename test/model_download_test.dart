import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/model_download_service.dart';
import 'package:vitalis_app/services/model_downloader.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';

class _EmptyRegistry implements BundledModelRegistry {
  @override
  Future<void> clearInstallation(String localPath) async {}

  @override
  Future<Map<String, Object?>?> read() async => null;
}

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
  Stream<bool> get onHealthChanged => const Stream.empty();
  @override
  Future<void> init() async {}
  @override
  void dispose() {}
}

ModelDownloadService _createService() {
  return ModelDownloadService(
    downloader: ModelDownloader(
      sentinel: _MockSentinel(),
      registry: _EmptyRegistry(),
    ),
  );
}

void main() {
  group('ModelDownloadService', () {
    test('initial state is idle', () {
      final service = _createService();
      expect(service.state, DownloadState.idle);
      expect(service.progress, 0.0);
      expect(service.isDownloading, false);
      expect(service.isCompleted, false);
    });

    test('cancel resets state', () {
      final service = _createService();
      service.cancelDownload();
      expect(service.state, DownloadState.idle);
      expect(service.progress, 0.0);
    });

    test('reset clears completed state', () async {
      final service = _createService();
      await service.resetDownloadState();
      expect(service.state, DownloadState.idle);
      expect(service.progress, 0.0);
    });

    test('isModelDownloaded returns false by default', () async {
      final service = _createService();
      final downloaded = await service.isModelDownloaded();
      expect(downloaded, false);
    });
  });
}
