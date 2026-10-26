import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'model_downloader.dart';

enum DownloadState { idle, downloading, completed, error }

class ModelDownloadService extends ChangeNotifier {
  final ModelDownloader _downloader;
  DownloadState _state = DownloadState.idle;
  double _progress = 0.0;
  String _statusMessage = '';
  double _downloadSpeed = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  CancelToken? _cancelToken;
  Timer? _speedTimer;
  int _lastBytes = 0;
  Timer? _throttleTimer;
  bool _hasPendingProgress = false;
  bool _disposed = false;
  Future<void>? _resetFuture;
  Future<void> _resetSettlement = Future<void>.value();
  int _resetFailures = 0;
  Future<void>? _downloadFuture;
  Future<void> _downloadSettlement = Future<void>.value();
  Future<void>? _closeFuture;
  bool _stopRequested = false;
  int _downloadFailures = 0;
  int _notificationDepth = 0;
  bool _notifierDisposed = false;

  DownloadState get state => _state;
  double get progress => _progress;
  String get statusMessage => _statusMessage;
  double get downloadSpeed => _downloadSpeed;
  int get downloadedBytes => _downloadedBytes;
  int get totalBytes => _totalBytes;
  bool get isCompleted => _state == DownloadState.completed;
  bool get isDownloading => _downloadFuture != null;
  bool get isCancelling => isDownloading && _stopRequested;
  int get resetFailures => _resetFailures;
  int get downloadFailures => _downloadFailures;

  @override
  void notifyListeners() {
    if (_disposed) return;
    _notificationDepth++;
    try {
      super.notifyListeners();
    } finally {
      _notificationDepth--;
      if (_disposed && _notificationDepth == 0 && !_notifierDisposed) dispose();
    }
  }

  ModelDownloadService({required ModelDownloader downloader})
    : _downloader = downloader;

  Future<bool> isModelDownloaded() => _downloader.isModelDownloaded();

  Future<void> downloadModel() {
    if (_disposed)
      return Future.error(StateError('Download service is disposed'));
    final existing = _downloadFuture;
    if (existing != null) return existing;
    if (_resetFuture != null)
      return Future.error(StateError('Model reset is active'));
    final completion = Completer<void>();
    final operation = completion.future;
    _downloadFuture = operation;
    _stopRequested = false;
    _cancelToken = CancelToken();
    _downloadSettlement = operation.then<void>(
      (_) {},
      onError: (Object error) {
        _downloadFailures++;
      },
    );
    unawaited(() async {
      try {
        await _runDownload();
        completion.complete();
      } catch (_) {
        _state = DownloadState.error;
        _statusMessage = 'Download failed. Please retry.';
        completion.completeError(StateError('Download could not be completed'));
      } finally {
        _speedTimer?.cancel();
        _throttleTimer?.cancel();
        _downloadFuture = null;
        notifyListeners();
      }
    }());
    return operation;
  }

  Future<void> _runDownload() async {
    final token = _cancelToken!;
    _state = DownloadState.downloading;
    _progress = 0.0;
    _downloadedBytes = 0;
    _totalBytes = 0;
    _downloadSpeed = 0.0;
    _lastBytes = 0;
    notifyListeners();
    if (_disposed || _stopRequested) {
      _state = DownloadState.idle;
      return;
    }

    _speedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final bytesThisSecond = _downloadedBytes - _lastBytes;
      _downloadSpeed = bytesThisSecond / (1024 * 1024);
      _lastBytes = _downloadedBytes;
      notifyListeners();
    });

    _throttleTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_hasPendingProgress) {
        notifyListeners();
        _hasPendingProgress = false;
      }
    });

    final result = await _downloader.download(
      cancelToken: token,
      onProgress: (progress, downloaded, total) {
        if (_disposed ||
            _stopRequested ||
            _downloadFuture == null ||
            !identical(token, _cancelToken))
          return;
        _downloadedBytes = downloaded;
        _totalBytes = total;
        _progress = progress;
        _hasPendingProgress = true;
      },
    );

    _speedTimer?.cancel();
    _throttleTimer?.cancel();

    if (_stopRequested || result.isCancelled) {
      _state = DownloadState.idle;
      _progress = 0.0;
    } else if (result.isSuccess) {
      _state = DownloadState.completed;
      _progress = 1.0;
    } else {
      _state = DownloadState.error;
      _statusMessage = result.error ?? 'Download failed';
    }
    notifyListeners();
  }

  Future<void> cancelDownload() {
    if (_downloadFuture == null) return Future<void>.value();
    _stopRequested = true;
    _cancelToken?.cancel();
    _speedTimer?.cancel();
    _throttleTimer?.cancel();
    _statusMessage = 'Waiting for download cancellation';
    notifyListeners();
    return _downloadSettlement;
  }

  Future<void> resetDownloadState() {
    if (_disposed)
      return Future.error(StateError('Download service is disposed'));
    final existing = _resetFuture;
    if (existing != null) return existing;
    if (isDownloading)
      return Future.error(StateError('A download is still active'));
    final completion = Completer<void>();
    final operation = completion.future;
    _resetFuture = operation;
    _resetSettlement = operation.then<void>(
      (_) {},
      onError: (Object error) {
        _resetFailures++;
      },
    );
    unawaited(() async {
      try {
        await _downloader.resetState();
        if (!_disposed) {
          _state = DownloadState.idle;
          _progress = 0.0;
          _downloadedBytes = 0;
          _totalBytes = 0;
          _downloadSpeed = 0.0;
          _statusMessage = '';
          notifyListeners();
        }
        completion.complete();
      } catch (error, stack) {
        completion.completeError(error, stack);
      } finally {
        _resetFuture = null;
      }
    }());
    return operation;
  }

  /// Waits for reset termination, not a claim about ordinary download recovery.
  Future<void> drainPendingReset() => _resetSettlement;

  /// Retains admitted operations until their transport/storage work settles.
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    dispose();
    return _closeFuture = Future.wait([_downloadSettlement, _resetSettlement]);
  }

  @override
  void dispose() {
    if (_notifierDisposed) return;
    _disposed = true;
    _stopRequested = true;
    _speedTimer?.cancel();
    _throttleTimer?.cancel();
    _cancelToken?.cancel();
    if (_notificationDepth == 0) {
      _notifierDisposed = true;
      super.dispose();
    }
  }
}
