import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';
import 'package:vitalis_app/services/model_download_service.dart';
import 'package:vitalis_app/services/model_downloader.dart';

void main() {
  test(
    'download close shares shutdown and waits for writer termination',
    () async {
      final transport = _PendingDownload();
      final service = ModelDownloadService(downloader: transport);
      final running = service.downloadModel();
      await transport.entered.future;
      var closed = false;
      final closing = service.close();
      expect(identical(closing, service.close()), isTrue);
      final observed = closing.then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      await expectLater(service.downloadModel(), throwsStateError);
      transport.finished.complete(DownloadResult.cancelled());
      await Future.wait([running, observed]);
      expect(closed, isTrue);
      expect(transport.calls, 1);
    },
  );

  test(
    'unexpected transport failure remains observed and cleanup settles',
    () async {
      final transport = _PendingDownload();
      final service = ModelDownloadService(downloader: transport);
      final running = service.downloadModel();
      final failure = expectLater(
        running,
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'redaction',
            isNot(contains('token=secret')),
          ),
        ),
      );
      await transport.entered.future;
      transport.finished.completeError(StateError('/private/token=secret'));
      await failure;
      expect(service.state, DownloadState.error);
      expect(service.isDownloading, isFalse);
      await service.close();
      expect(service.downloadFailures, 1);
    },
  );

  test(
    'reentrant disposal at download admission prevents transport start',
    () async {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);
      final transport = _PendingDownload();
      final service = ModelDownloadService(downloader: transport);
      service.addListener(service.dispose);
      await service.downloadModel();
      await service.close();
      expect(transport.calls, 0);
      expect(errors, isEmpty);
    },
  );

  test(
    'late previous download progress cannot overwrite a new request',
    () async {
      final transport = _PendingDownload();
      final service = ModelDownloadService(downloader: transport);
      addTearDown(service.dispose);
      final first = service.downloadModel();
      await transport.entered.future;
      final oldProgress = transport.progress!;
      transport.finished.complete(DownloadResult.success('disposable.gguf'));
      await first;
      transport.finished = Completer<DownloadResult>();
      final second = service.downloadModel();
      transport.progress!(0.1, 10, 100);
      oldProgress(0.9, 90, 100);
      final observed = service.downloadedBytes;
      transport.finished.complete(DownloadResult.cancelled());
      await second;
      expect(observed, 10);
    },
  );
  test(
    'cancel retains active writer admission until transport settles',
    () async {
      final transport = _PendingDownload();
      final service = ModelDownloadService(downloader: transport);
      addTearDown(service.dispose);
      final running = service.downloadModel();
      await transport.entered.future;
      service.cancelDownload();
      final stillOwned = service.isDownloading;
      final second = service.downloadModel();
      final callsBeforeSettlement = transport.calls;
      transport.finished.complete(DownloadResult.cancelled());
      await Future.wait([running, second]);
      expect(stillOwned, isTrue);
      expect(callsBeforeSettlement, 1);
    },
  );

  test('disposed download service cannot start transport work', () async {
    final transport = _PendingDownload();
    final service = ModelDownloadService(downloader: transport)..dispose();
    final attempt = service.downloadModel();
    final observed = attempt.then<Object?>(
      (_) => null,
      onError: (Object error) => error,
    );
    await Future<void>.delayed(Duration.zero);
    final calls = transport.calls;
    if (!transport.finished.isCompleted)
      transport.finished.complete(DownloadResult.cancelled());
    expect(await observed, isA<StateError>());
    expect(calls, 0);
  });
  test('reset drain remains pending until the owned acknowledgement', () async {
    final downloader = _Downloader();
    final service = ModelDownloadService(downloader: downloader);
    final resetting = service.resetDownloadState();
    await downloader.entered.future;
    service.dispose();
    var drained = false;
    final draining = service.drainPendingReset().then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    final drainedBeforeAcknowledgement = drained;
    downloader.acknowledged.complete();
    await Future.wait([resetting, draining]);
    expect(drainedBeforeAcknowledgement, isFalse);
    expect(drained, isTrue);
  });

  test(
    'failed reset stays observable while disposal drains settlement',
    () async {
      final downloader = _Downloader();
      final service = ModelDownloadService(downloader: downloader);
      final resetting = service.resetDownloadState();
      final observed = expectLater(resetting, throwsStateError);
      await downloader.entered.future;
      service.dispose();
      final draining = service.drainPendingReset();
      downloader.acknowledged.completeError(
        StateError('Disposable reset failure'),
      );
      await Future.wait([observed, draining]);
      expect(service.resetFailures, 1);
    },
  );

  test('duplicate reset callers share the owned operation', () async {
    final downloader = _Downloader();
    final service = ModelDownloadService(downloader: downloader);
    addTearDown(service.dispose);
    final first = service.resetDownloadState();
    final second = service.resetDownloadState();
    final callsBeforeAcknowledgement = downloader.calls;
    downloader.acknowledged.complete();
    await Future.wait([first, second]);
    expect(callsBeforeAcknowledgement, 1);
    expect(identical(first, second), isTrue);
  });

  test(
    'an admitted reset settles without notification after disposal',
    () async {
      final downloader = _Downloader();
      final service = ModelDownloadService(downloader: downloader);
      final resetting = service.resetDownloadState();
      await downloader.entered.future;
      service.dispose();
      downloader.acknowledged.complete();
      await resetting;
    },
  );

  test('disposed download service rejects reset before transport', () async {
    final downloader = _Downloader()..acknowledged.complete();
    final service = ModelDownloadService(downloader: downloader)..dispose();
    await expectLater(service.resetDownloadState(), throwsStateError);
    expect(downloader.calls, 0);
  });
}

final class _PendingDownload extends ModelDownloader {
  _PendingDownload() : super(sentinel: _UnusedSafety());
  final entered = Completer<void>();
  var finished = Completer<DownloadResult>();
  void Function(double, int, int)? progress;
  int calls = 0;
  @override
  Future<DownloadResult> download({
    CancelToken? cancelToken,
    void Function(double, int, int)? onProgress,
  }) {
    calls++;
    progress = onProgress;
    if (!entered.isCompleted) entered.complete();
    return finished.future;
  }
}

final class _Downloader extends ModelDownloader {
  _Downloader() : super(sentinel: _UnusedSafety());
  final entered = Completer<void>();
  final acknowledged = Completer<void>();
  int calls = 0;

  @override
  Future<void> resetState() async {
    calls++;
    if (!entered.isCompleted) entered.complete();
    await acknowledged.future;
  }
}

final class _UnusedSafety implements HardwareSentinelService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected safety access in service lifecycle fixture');
}
