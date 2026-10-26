import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database_helper.dart';
import '../models/hub_model.dart';
import '../models/model_descriptor.dart';
import '../models/model_download_job.dart';
import '../models/model_library_policy.dart';
import '../utils/app_logger.dart';
import 'model_registry_service.dart';
import 'model_download_staging.dart';
import 'native_transfer_stop.dart';
import 'model_storage_preflight.dart';

abstract interface class ModelFileStore {
  Future<Directory> modelDirectory(String modelId);
  Future<int?> usableBytes();
}

final class ApplicationModelFileStore implements ModelFileStore {
  const ApplicationModelFileStore();

  @override
  Future<Directory> modelDirectory(String modelId) async {
    final root = await getApplicationSupportDirectory();
    final safeId = modelId.replaceAll(RegExp('[^A-Za-z0-9_.-]'), '_');
    final directory = Directory(p.join(root.path, 'models', safeId));
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<int?> usableBytes() => queryAllocatableModelStorage();
}

abstract interface class PlatformTransferAdapter {
  Future<TransferResult> transfer({
    required String transferId,
    required String jobId,
    required String modelId,
    required String repository,
    required String revision,
    required Uri source,
    required File partial,
    required int existingBytes,
    required int expectedBytes,
    required String? expectedSha256,
    int artifactIndex = 0,
    int shardCount = 1,
    required void Function(int received, int? total) onProgress,
    required CancelToken cancellation,
  });

  Future<TransferReconciliation?> reconcile(String jobId);
}

/// Control of durable writers that may outlive the originating Dart manager.
abstract interface class DurableTransferControl {
  Future<void> cancelJob(String jobId);
}

class DioTransferAdapter implements PlatformTransferAdapter {
  DioTransferAdapter({
    Dio? dio,
    Future<void> Function(Duration)? delay,
    DateTime Function()? clock,
  }) : _dio = dio ?? Dio(),
       _delay = delay ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now;

  final Dio _dio;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _clock;

  @override
  Future<TransferResult> transfer({
    required String transferId,
    required String jobId,
    required String modelId,
    required String repository,
    required String revision,
    required Uri source,
    required File partial,
    required int existingBytes,
    required int expectedBytes,
    required String? expectedSha256,
    int artifactIndex = 0,
    int shardCount = 1,
    required void Function(int received, int? total) onProgress,
    required CancelToken cancellation,
  }) async {
    if (source.scheme != 'https' || source.host != 'huggingface.co') {
      throw const FormatException(
        'Only HTTPS Hugging Face downloads are allowed',
      );
    }
    var offset = existingBytes;
    for (
      var attempt = 0;
      attempt < ModelLibraryPolicy.maximumTransferAttempts;
      attempt++
    ) {
      try {
        final response = await _dio.downloadUri(
          source,
          partial.path,
          cancelToken: cancellation,
          options: Options(
            headers: offset == 0 ? null : {'Range': 'bytes=$offset-'},
          ),
          deleteOnError: false,
          fileAccessMode: offset == 0
              ? FileAccessMode.write
              : FileAccessMode.append,
          onReceiveProgress: (received, total) =>
              onProgress(offset + received, total < 0 ? null : offset + total),
        );
        return TransferResult(statusCode: response.statusCode ?? 0);
      } on DioException catch (error) {
        if (error.type == DioExceptionType.cancel ||
            !_isTransient(error) ||
            attempt == ModelLibraryPolicy.maximumTransferAttempts - 1) {
          rethrow;
        }
        offset = await partial.exists() ? await partial.length() : 0;
        await _delay(_retryDelay(error, attempt));
      }
    }
    throw StateError('Transfer retry loop exited unexpectedly');
  }

  @override
  Future<TransferReconciliation?> reconcile(String jobId) async => null;

  bool _isTransient(DioException error) {
    final status = error.response?.statusCode;
    return status == 429 ||
        (status != null && status >= 500 && status <= 599) ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout;
  }

  Duration _retryDelay(DioException error, int attempt) {
    final value = error.response?.headers.value('retry-after');
    final seconds = value == null ? null : int.tryParse(value);
    if (seconds != null) {
      return Duration(
        seconds: seconds.clamp(1, ModelLibraryPolicy.maximumRetryAfterSeconds),
      );
    }
    if (value != null) {
      try {
        final duration = HttpDate.parse(value).difference(_clock().toUtc());
        if (!duration.isNegative) {
          return duration >
                  const Duration(
                    seconds: ModelLibraryPolicy.maximumRetryAfterSeconds,
                  )
              ? const Duration(
                  seconds: ModelLibraryPolicy.maximumRetryAfterSeconds,
                )
              : duration;
        }
      } on FormatException {
        // Use the bounded policy below.
      }
    }
    return Duration(seconds: 1 << attempt);
  }
}

class TransferResult {
  const TransferResult({required this.statusCode});
  final int statusCode;
}

class TransferReconciliation {
  const TransferReconciliation({
    required this.state,
    required this.downloadedBytes,
    this.stopReason,
    this.failureCode,
    this.stopDisposition,
  });

  final ModelDownloadJobState state;
  final int downloadedBytes;
  final String? stopReason;
  final String? failureCode;
  final String? stopDisposition;
}

/// Android-owned durable transfer adapter. Native workers retain the transfer
/// manifest and `.part` file when the Flutter process exits.
class AndroidDurableTransferAdapter
    implements PlatformTransferAdapter, DurableTransferControl {
  const AndroidDurableTransferAdapter({
    MethodChannel channel = const MethodChannel('vitalis/model_transfers'),
    Duration pollInterval = NativeTransferStopPolicy.pollInterval,
    Duration stopAcknowledgementTimeout =
        NativeTransferStopPolicy.acknowledgementTimeout,
    NativeStopTimerFactory stopTimerFactory = Timer.new,
    Duration Function()? monotonicNow,
  }) : _channel = channel,
       _pollInterval = pollInterval,
       _stopTimeout = stopAcknowledgementTimeout,
       _stopTimerFactory = stopTimerFactory,
       _monotonicNow = monotonicNow;

  final MethodChannel _channel;
  final Duration _pollInterval;
  final Duration _stopTimeout;
  final NativeStopTimerFactory _stopTimerFactory;
  final Duration Function()? _monotonicNow;

  @override
  Future<void> cancelJob(String jobId) => _stopController.cancelJob(jobId);

  NativeTransferStopController get _stopController =>
      NativeTransferStopController(
        channel: _channel,
        timeout: _stopTimeout,
        pollInterval: _pollInterval,
        timerFactory: _stopTimerFactory,
        monotonicNow: _monotonicNow,
      );

  Future<T> _untilStopped<T>(Future<T> work, CancelToken cancellation) async {
    final value = await Future.any<T>([
      work,
      cancellation.whenCancel.then<T>(
        (_) => throw const _NativeTransferStopRequested(),
      ),
    ]);
    if (cancellation.isCancelled) throw const _NativeTransferStopRequested();
    return value;
  }

  Future<void> _pollUntilStopped(CancelToken cancellation) async {
    final ready = Completer<void>();
    final timer = Timer(_pollInterval, () => ready.complete());
    try {
      await _untilStopped(ready.future, cancellation);
    } finally {
      timer.cancel();
    }
  }

  @override
  Future<TransferResult> transfer({
    required String transferId,
    required String jobId,
    required String modelId,
    required String repository,
    required String revision,
    required Uri source,
    required File partial,
    required int existingBytes,
    required int expectedBytes,
    required String? expectedSha256,
    int artifactIndex = 0,
    int shardCount = 1,
    required void Function(int received, int? total) onProgress,
    required CancelToken cancellation,
  }) async {
    try {
      await _untilStopped(
        _channel.invokeMapMethod<String, dynamic>('enqueue', {
          'transferId': transferId,
          'jobId': jobId,
          'modelId': modelId,
          'repository': repository,
          'revision': revision,
          'sourceUrl': source.toString(),
          'partialPath': partial.path,
          'finalPath': partial.path.substring(0, partial.path.length - 5),
          'artifactIndex': artifactIndex,
          'shardCount': shardCount,
          'expectedBytes': expectedBytes,
          'expectedSha256': expectedSha256,
        }),
        cancellation,
      );
      while (true) {
        final snapshot = await _untilStopped(
          _channel.invokeMapMethod<String, dynamic>('status', {
            'transferId': transferId,
          }),
          cancellation,
        );
        if (snapshot == null) {
          throw StateError('Android transfer manifest is unavailable');
        }
        final received = (snapshot['downloadedBytes'] as num?)?.toInt() ?? 0;
        onProgress(received, expectedBytes);
        switch (snapshot['state'] as String?) {
          case 'downloaded':
            return TransferResult(
              statusCode: existingBytes > 0
                  ? HttpStatus.partialContent
                  : HttpStatus.ok,
            );
          case 'paused':
            if (snapshot['stopAcknowledged'] != true) break;
            throw DioException.requestCancelled(
              requestOptions: RequestOptions(path: source.toString()),
              reason: 'paused',
            );
          case 'cancelled':
            if (snapshot['stopAcknowledged'] != true) break;
            throw DioException.requestCancelled(
              requestOptions: RequestOptions(path: source.toString()),
              reason: 'cancelled',
            );
          case 'failed':
            throw StateError(
              'Android transfer failed: ${snapshot['failureCode'] ?? snapshot['stopReason'] ?? 'unknown'}',
            );
        }
        await _pollUntilStopped(cancellation);
      }
    } on PlatformException catch (error) {
      if (error.code == 'transfer_stop_pending') {
        throw NativeTransferStopUnconfirmed(NativeStopFailure.pending);
      }
      rethrow;
    } on _NativeTransferStopRequested {
      final cancelled = cancellation.cancelError?.error == 'cancelled';
      await _stopController.stopTransfer(jobId, transferId, cancel: cancelled);
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(path: source.toString()),
        reason: cancelled ? 'cancelled' : 'paused',
      );
    }
  }

  @override
  Future<TransferReconciliation?> reconcile(String jobId) async {
    final values = await _channel.invokeListMethod<Object?>('list') ?? const [];
    final matches = values
        .whereType<Map<Object?, Object?>>()
        .where((item) => item['jobId'] == jobId)
        .toList(growable: false);
    if (matches.isEmpty) return null;
    final bytes = matches.fold<int>(
      0,
      (sum, item) => sum + ((item['downloadedBytes'] as num?)?.toInt() ?? 0),
    );
    final states = matches.map((item) => item['state'] as String?).toSet();
    final state = states.contains('cancelled')
        ? ModelDownloadJobState.cancelled
        : states.contains('failed')
        ? ModelDownloadJobState.failed
        : states.every((state) => state == 'downloaded')
        ? ModelDownloadJobState.validating
        : states.contains('running') || states.contains('queued')
        ? ModelDownloadJobState.downloading
        : ModelDownloadJobState.paused;
    return TransferReconciliation(
      state: state,
      downloadedBytes: bytes,
      stopReason: matches
          .map((item) => item['stopReason'] as String?)
          .whereType<String>()
          .firstOrNull,
      failureCode:
          matches.any(
            (item) =>
                (item['state'] == 'paused' || item['state'] == 'cancelled') &&
                item['stopAcknowledged'] != true,
          )
          ? ModelDownloadJob.nativeCancellationPending
          : matches
                .map((item) => item['failureCode'] as String?)
                .whereType<String>()
                .firstOrNull,
      stopDisposition: matches
          .map((item) => item['stopDisposition'] as String?)
          .whereType<String>()
          .firstOrNull,
    );
  }
}

final class _NativeTransferStopRequested implements Exception {
  const _NativeTransferStopRequested();
}

abstract interface class DownloadJobStore {
  Future<void> write(ModelDownloadJob job);
  Future<List<ModelDownloadJob>> list();
}

final class DatabaseDownloadJobStore implements DownloadJobStore {
  DatabaseDownloadJobStore({DatabaseHelper? database})
    : _database = database ?? DatabaseHelper.instance;

  final DatabaseHelper _database;

  @override
  Future<List<ModelDownloadJob>> list() async =>
      (await _database.getDownloadJobs())
          .map((row) => ModelDownloadJob.fromMap(row))
          .toList(growable: false);

  @override
  Future<void> write(ModelDownloadJob job) =>
      _database.upsertDownloadJob(job.toMap());
}

/// Installs public GGUF artifacts at one immutable Hub revision.
///
/// A job owns all shards. Files remain `.part` until size and publisher hash
/// checks pass, then each shard is renamed in the model's private directory.
abstract interface class ModelDownloadOperations {
  Future<ModelDownloadJob> enqueue({
    required HubModelSummary model,
    required GgufVariant variant,
  });

  Future<ModelDownloadJob> run(ModelDownloadJob original);
}

class ModelDownloadManager implements ModelDownloadOperations {
  final Random _identityRandom = Random.secure();
  ModelDownloadManager({
    required DownloadJobStore jobs,
    required ModelFileStore files,
    required PlatformTransferAdapter transfers,
    DatabaseHelper? database,
    ModelRegistryService? registry,
    DateTime Function()? clock,
  }) : _jobs = jobs,
       _files = files,
       _transfers = transfers,
       _database = database ?? DatabaseHelper.instance,
       _registry = registry ?? ModelRegistryService(database: database),
       _clock = clock ?? DateTime.now;

  final DownloadJobStore _jobs;
  final ModelFileStore _files;
  final PlatformTransferAdapter _transfers;
  final DatabaseHelper _database;
  final ModelRegistryService _registry;
  final DateTime Function() _clock;
  final Map<String, CancelToken> _cancellations = {};
  final Map<String, Future<ModelDownloadJob>> _runs = {};
  final Map<String, Future<void>> _cancelRuns = {};
  // Process-local ownership complements (but does not replace) native durable
  // writer ownership. Different manager instances must not write one model.
  static final Set<String> _activeModels = {};
  static final Set<String> _enqueueModels = {};
  final Map<String, ModelDownloadJobState> _stopIntents = {};
  final _jobListeners = <void Function(ModelDownloadJob)>{};

  void addJobListener(void Function(ModelDownloadJob) listener) =>
      _jobListeners.add(listener);
  void removeJobListener(void Function(ModelDownloadJob) listener) =>
      _jobListeners.remove(listener);

  Future<void> _writeJob(ModelDownloadJob job) async {
    await _jobs.write(job);
    for (final listener in _jobListeners.toList()) {
      if (!_jobListeners.contains(listener)) continue;
      try {
        listener(job);
      } catch (error) {
        // An observer cannot turn a successful durable write into a failure.
        AppLogger.instance.warning(
          'Download observer failed (${error.runtimeType})',
        );
      }
    }
  }

  @override
  Future<ModelDownloadJob> enqueue({
    required HubModelSummary model,
    required GgufVariant variant,
  }) async {
    final modelId = _stableModelId(
      model.id,
      model.revision,
      variant.displayName,
    );
    if (!_enqueueModels.add(modelId)) throw StateError('modelEnqueueBusy');
    try {
      return await _enqueueOwned(model: model, variant: variant);
    } finally {
      _enqueueModels.remove(modelId);
    }
  }

  Future<ModelDownloadJob> _enqueueOwned({
    required HubModelSummary model,
    required GgufVariant variant,
  }) async {
    if (model.gated) throw StateError('Gated models are not supported');
    if (model.id != variant.repository || model.revision != variant.revision) {
      throw StateError('Artifact identity does not match the selected model');
    }
    final total = variant.totalBytes;
    if (total == null || variant.files.any((file) => file.sizeBytes == null)) {
      throw StateError('Every model file must have a known size');
    }
    final usable = await _files.usableBytes();
    final requiredBytes = (total * ModelLibraryPolicy.downloadStorageHeadroom)
        .ceil();
    if (usable != null && usable < requiredBytes) {
      throw StateError('Insufficient storage for download and verification');
    }
    final modelId = _stableModelId(
      model.id,
      model.revision,
      variant.displayName,
    );
    final installed = await _database.getModel(modelId);
    if (installed?['installation_state'] == 'installed') {
      throw StateError(
        'Model is already installed; use explicit verify or repair',
      );
    }
    if (_activeModels.contains(modelId)) throw StateError('modelTransferBusy');
    final jobs = await _jobs.list();
    _requireNoNativeRecoveryHold(modelId, jobs);
    final existingJobs = jobs.where(
      (job) =>
          job.modelId == modelId &&
          job.state != ModelDownloadJobState.cancelled &&
          job.state != ModelDownloadJobState.failed &&
          job.state != ModelDownloadJobState.completed,
    );
    if (existingJobs.isNotEmpty) {
      final records = await _database.getModelFiles(modelId);
      final equivalent =
          records.length == variant.files.length &&
          variant.files.every(
            (file) => records.any(
              (row) =>
                  row['file_name'] == file.name &&
                  row['byte_size'] == file.sizeBytes &&
                  row['sha256'] == file.sha256 &&
                  row['etag'] == file.etag &&
                  row['shard_index'] == file.shardIndex &&
                  row['shard_count'] == file.shardCount,
            ),
          );
      if (!equivalent) throw StateError('Artifact identity collision');
      return existingJobs.first;
    }
    final now = _clock();
    final job = ModelDownloadJob(
      id: _newJobId(modelId),
      modelId: modelId,
      repository: model.id,
      revision: model.revision,
      state: ModelDownloadJobState.queued,
      downloadedBytes: 0,
      totalBytes: total,
      createdAt: now,
      updatedAt: now,
    );
    await _database.upsertModel(
      ModelDescriptor(
        id: modelId,
        displayName: variant.displayName,
        source: 'huggingface',
        compatibilityStatus: 'pending_validation',
        repository: model.id,
        revision: model.revision,
        quantization: variant.quantization,
        parameterCount: model.parameterCount,
        license: model.license,
        installationState: 'downloading',
      ).toMap(),
    );
    await _database.replaceModelFiles(
      modelId,
      variant.files
          .map(
            (file) => <String, Object?>{
              'file_name': file.name,
              'byte_size': file.sizeBytes,
              'sha256': file.sha256,
              'etag': file.etag,
              'shard_index': file.shardIndex,
              'shard_count': file.shardCount,
            },
          )
          .toList(),
    );
    await _writeJob(job);
    return job;
  }

  @override
  Future<ModelDownloadJob> run(ModelDownloadJob original) {
    final running = _runs[original.id];
    if (running != null) return running;
    if (original.state == ModelDownloadJobState.completed) {
      return Future.value(original);
    }
    if (!_activeModels.add(original.modelId)) {
      return Future.error(StateError('modelTransferBusy'));
    }
    final completion = Completer<ModelDownloadJob>();
    _runs[original.id] = completion.future;
    void release() {
      _runs.remove(original.id);
      _activeModels.remove(original.modelId);
    }

    unawaited(
      _runOwned(original).then(
        (value) {
          release();
          completion.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          // Initial persistence can fail before _runOwned enters its try/finally.
          _cancellations.remove(original.id);
          _stopIntents.remove(original.id);
          release();
          completion.completeError(error, stack);
        },
      ),
    );
    return completion.future;
  }

  Future<ModelDownloadJob> _runOwned(ModelDownloadJob original) async {
    if (original.state == ModelDownloadJobState.completed) return original;
    _requireNoNativeRecoveryHold(original.modelId, await _jobs.list());
    final cancellation = CancelToken();
    _cancellations[original.id] = cancellation;
    var job = original.copyWith(
      state: ModelDownloadJobState.downloading,
      clearError: true,
      updatedAt: _clock(),
    );
    await _writeJob(job);
    Future<void> progressWrites = Future<void>.value();
    var completedBytes = 0;
    File? activePartial;
    var activeExpectedBytes = 0;
    try {
      final directory = await _files.modelDirectory(job.modelId);
      final records = (await _database.getModelFiles(job.modelId))
          .map((record) => Map<String, dynamic>.from(record))
          .toList(growable: false);
      for (final record in records) {
        final name = record['file_name']! as String;
        _validateFileName(name);
        final expectedSize = record['byte_size']! as int;
        final expectedHash = record['sha256'] as String?;
        final destination = File(p.join(directory.path, p.basename(name)));
        final partial = await ModelDownloadStaging(
          directory,
        ).partial(job.id, name);
        if (await destination.exists() &&
            await _verify(destination, expectedSize, expectedHash)) {
          record['local_path'] = destination.path;
          record['sha256'] = await _hash(destination);
          completedBytes += expectedSize;
          continue;
        }
        activePartial = partial;
        activeExpectedBytes = expectedSize;
        var existing = await partial.exists() ? await partial.length() : 0;
        if (existing > expectedSize) {
          await partial.delete();
          existing = 0;
        }
        final source = _downloadUri(job.repository, job.revision, name);
        final transferId = _transferId(job.id, name);
        final transfer = await _transfers.transfer(
          transferId: transferId,
          jobId: job.id,
          modelId: job.modelId,
          repository: job.repository,
          revision: job.revision,
          source: source,
          partial: partial,
          existingBytes: existing,
          expectedBytes: expectedSize,
          expectedSha256: expectedHash,
          artifactIndex: (record['shard_index'] as int?) ?? 0,
          shardCount: (record['shard_count'] as int?) ?? records.length,
          cancellation: cancellation,
          onProgress: (received, _) {
            progressWrites = progressWrites.then(
              (_) => _writeJob(
                job = job.copyWith(
                  downloadedBytes: completedBytes + received,
                  updatedAt: _clock(),
                ),
              ),
            );
          },
        );
        await progressWrites;
        if (existing > 0 && transfer.statusCode != HttpStatus.partialContent) {
          await partial.delete();
          final restarted = await _transfers.transfer(
            transferId: transferId,
            jobId: job.id,
            modelId: job.modelId,
            repository: job.repository,
            revision: job.revision,
            source: source,
            partial: partial,
            existingBytes: 0,
            expectedBytes: expectedSize,
            expectedSha256: expectedHash,
            artifactIndex: (record['shard_index'] as int?) ?? 0,
            shardCount: (record['shard_count'] as int?) ?? records.length,
            cancellation: cancellation,
            onProgress: (received, _) {
              progressWrites = progressWrites.then(
                (_) => _writeJob(
                  job = job.copyWith(
                    downloadedBytes: completedBytes + received,
                    updatedAt: _clock(),
                  ),
                ),
              );
            },
          );
          await progressWrites;
          if (restarted.statusCode < 200 || restarted.statusCode >= 300) {
            throw StateError('Server rejected the restarted transfer');
          }
        }
        job = job.copyWith(
          state: ModelDownloadJobState.validating,
          downloadedBytes: completedBytes + await partial.length(),
          updatedAt: _clock(),
        );
        await _writeJob(job);
        if (!await _verify(partial, expectedSize, expectedHash)) {
          throw StateError('Downloaded model file failed verification');
        }
        final actualHash = await _hash(partial);
        if (await destination.exists()) await destination.delete();
        await partial.rename(destination.path);
        record['local_path'] = destination.path;
        record['sha256'] = actualHash;
        completedBytes += expectedSize;
        activePartial = null;
      }
      final first = records.first;
      final descriptorRow = await _database.getModel(job.modelId);
      if (descriptorRow == null)
        throw StateError('Model registry entry missing');
      await _database.upsertModel({
        ...descriptorRow,
        'local_path': first['local_path'],
        'sha256': first['sha256'],
        'byte_size': job.totalBytes,
        'compatibility_status': 'validating',
        'installation_state': 'validating',
      });
      await _database.replaceModelFiles(
        job.modelId,
        records.map((row) => Map<String, Object?>.from(row)).toList(),
      );
      await _registry.validateDownloadedModel(
        modelId: job.modelId,
        primaryPath: first['local_path']! as String,
      );
      job = job.copyWith(
        state: ModelDownloadJobState.completed,
        downloadedBytes: job.totalBytes,
        updatedAt: _clock(),
      );
      await _writeJob(job);
      return job;
    } on DioException catch (error) {
      final interrupted = error.type == DioExceptionType.cancel;
      await progressWrites;
      // The adapter has acknowledged writer termination before cancellation
      // reaches here. Polls can miss the final retained network bytes.
      final retainedBytes =
          interrupted && activePartial != null && await activePartial.exists()
          ? min(await activePartial.length(), activeExpectedBytes)
          : 0;
      final stoppedState = _stopIntents[original.id];
      final nativeCancelled = error.error == 'cancelled';
      final cancelled =
          interrupted &&
          (nativeCancelled ||
              (_transfers is! DurableTransferControl &&
                  stoppedState == ModelDownloadJobState.cancelled));
      final paused = interrupted && !cancelled;
      job = job.copyWith(
        downloadedBytes: interrupted
            ? completedBytes + retainedBytes
            : job.downloadedBytes,
        state: cancelled
            ? ModelDownloadJobState.cancelled
            : paused
            ? ModelDownloadJobState.paused
            : ModelDownloadJobState.failed,
        errorCode: interrupted ? null : 'network',
        clearError: interrupted,
        retryCount: interrupted ? job.retryCount : job.retryCount + 1,
        updatedAt: _clock(),
      );
      await _writeJob(job);
      if (cancelled) await _deleteJobPartials(job);
      await _recordInstallationState(
        job,
        cancelled
            ? 'download_cancelled'
            : paused
            ? 'download_paused'
            : 'download_failed',
        interrupted ? 'pending_validation' : 'download_failed',
      );
      return job;
    } catch (error, stack) {
      if (_transfers is DurableTransferControl &&
          (cancellation.isCancelled ||
              error is NativeTransferStopUnconfirmed)) {
        // A failed channel/status call is not a writer-termination acknowledgement.
        // Drain prior progress before persisting the hold so it cannot erase it.
        await progressWrites;
        job = job.copyWith(
          state: ModelDownloadJobState.failed,
          errorCode: ModelDownloadJob.nativeCancellationPending,
          updatedAt: _clock(),
        );
        await _writeJob(job);
        Error.throwWithStackTrace(
          error is NativeTransferStopUnconfirmed
              ? error
              : NativeTransferStopUnconfirmed(NativeStopFailure.transport),
          stack,
        );
      }
      final stoppedState = _stopIntents[original.id];
      final cancelled =
          cancellation.isCancelled &&
          stoppedState == ModelDownloadJobState.cancelled;
      job = job.copyWith(
        state: cancellation.isCancelled
            ? cancelled
                  ? ModelDownloadJobState.cancelled
                  : ModelDownloadJobState.paused
            : ModelDownloadJobState.failed,
        errorCode: cancellation.isCancelled ? null : 'validation_or_transfer',
        clearError: cancellation.isCancelled,
        retryCount: cancellation.isCancelled
            ? job.retryCount
            : job.retryCount + 1,
        updatedAt: _clock(),
      );
      await _writeJob(job);
      if (cancelled) await _deleteJobPartials(job);
      await _recordInstallationState(
        job,
        cancellation.isCancelled
            ? cancelled
                  ? 'download_cancelled'
                  : 'download_paused'
            : 'validation_failed',
        cancellation.isCancelled ? 'pending_validation' : 'failed_validation',
      );
      return job;
    } finally {
      _cancellations.remove(original.id);
      _stopIntents.remove(original.id);
    }
  }

  void pause(String jobId) {
    if (_cancelRuns.containsKey(jobId)) return;
    _stopIntents[jobId] = ModelDownloadJobState.paused;
    _cancellations[jobId]?.cancel('paused');
  }

  void _requireNoNativeRecoveryHold(
    String modelId,
    Iterable<ModelDownloadJob> jobs,
  ) {
    if (jobs.any(
      (job) =>
          job.modelId == modelId &&
          job.errorCode == ModelDownloadJob.nativeCancellationPending,
    )) {
      throw StateError('nativeCancellationPending');
    }
  }

  Future<void> cancel(String jobId) => _cancelRuns.putIfAbsent(
    jobId,
    () => _cancel(jobId).whenComplete(() {
      _cancelRuns.remove(jobId);
    }),
  );

  Future<void> _cancel(String jobId) async {
    final active = _cancellations[jobId];
    if (active != null) {
      _stopIntents[jobId] = ModelDownloadJobState.cancelled;
      active.cancel('cancelled');
      // Returning here previously advertised completion before the adapter had
      // acknowledged termination and the final job state had been persisted.
      final result = await _runs[jobId];
      if (result?.state == ModelDownloadJobState.cancelled ||
          result?.state == ModelDownloadJobState.completed)
        return;
      // A prior pause may have won the token race. Its acknowledgement does
      // not authorize cancellation cleanup; stop the durable job explicitly.
    }
    final matching = (await _jobs.list()).where((job) => job.id == jobId);
    if (matching.isEmpty) return;
    final original = matching.single;
    if (original.state == ModelDownloadJobState.completed) return;
    if (_enqueueModels.contains(original.modelId) ||
        !_activeModels.add(original.modelId)) {
      throw StateError('modelTransferOwnedElsewhere');
    }
    try {
      final control = _transfers;
      if (control is DurableTransferControl) {
        // Persist before asking Android. A failed channel or a restarted Dart
        // manager must not erase uncertainty about the still-owned writer.
        await _writeJob(
          original.copyWith(
            errorCode: ModelDownloadJob.nativeCancellationPending,
            updatedAt: _clock(),
          ),
        );
        await (control as DurableTransferControl).cancelJob(jobId);
      }
      final job = original.copyWith(
        state: ModelDownloadJobState.cancelled,
        clearError: true,
        updatedAt: _clock(),
      );
      await _deleteJobPartials(job);
      await _writeJob(job);
      await _recordInstallationState(
        job,
        'download_cancelled',
        'pending_validation',
      );
      _stopIntents.remove(jobId);
    } finally {
      _activeModels.remove(original.modelId);
    }
  }

  Future<void> _deleteJobPartials(ModelDownloadJob job) async {
    final directory = await _files.modelDirectory(job.modelId);
    final staging = ModelDownloadStaging(directory);
    for (final record in await _database.getModelFiles(job.modelId)) {
      final name = record['file_name']! as String;
      _validateFileName(name);
      final partial = await staging.partial(job.id, name);
      if (await partial.exists()) await partial.delete();
    }
  }

  Future<void> _recordInstallationState(
    ModelDownloadJob job,
    String installationState,
    String compatibilityStatus,
  ) async {
    final otherJobs = await _jobs.list();
    if (otherJobs.any(
      (other) =>
          other.modelId == job.modelId &&
          other.id != job.id &&
          other.state != ModelDownloadJobState.cancelled &&
          other.state != ModelDownloadJobState.failed &&
          other.state != ModelDownloadJobState.completed,
    ))
      return;
    final row = await _database.getModel(job.modelId);
    if (row == null || row['installation_state'] == 'installed') return;
    await _database.upsertModel({
      ...row,
      'installation_state': installationState,
      'compatibility_status': compatibilityStatus,
    });
  }

  Future<List<ModelDownloadJob>> restoreJobs() async {
    final restored = <ModelDownloadJob>[];
    for (final job in await _jobs.list()) {
      if (job.errorCode == ModelDownloadJob.nativeCancellationPending) {
        restored.add(job);
        continue;
      }
      final native = await _transfers.reconcile(job.id);
      final pendingStop =
          native?.failureCode == ModelDownloadJob.nativeCancellationPending;
      final recovered =
          native != null && job.state != ModelDownloadJobState.completed
          ? job.copyWith(
              state: native.state == ModelDownloadJobState.downloading
                  ? ModelDownloadJobState.paused
                  : native.state,
              downloadedBytes: native.downloadedBytes,
              errorCode: pendingStop
                  ? ModelDownloadJob.nativeCancellationPending
                  : native.state == ModelDownloadJobState.failed
                  ? native.failureCode ?? native.stopReason ?? 'native_transfer'
                  : null,
              clearError:
                  !pendingStop && native.state != ModelDownloadJobState.failed,
              updatedAt: _clock(),
            )
          : job.state == ModelDownloadJobState.downloading ||
                job.state == ModelDownloadJobState.validating
          ? job.copyWith(
              state: ModelDownloadJobState.paused,
              updatedAt: _clock(),
            )
          : job;
      if (recovered != job) await _writeJob(recovered);
      restored.add(
        recovered.state == ModelDownloadJobState.validating
            ? await run(recovered)
            : recovered,
      );
    }
    return List.unmodifiable(restored);
  }

  Future<bool> _verify(File file, int size, String? expectedHash) async {
    if (!await file.exists() || await file.length() != size) return false;
    if (expectedHash == null || expectedHash.isEmpty) return true;
    final actual = await _hash(file);
    return actual.toLowerCase() == expectedHash.toLowerCase();
  }

  Future<String> _hash(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Uri _downloadUri(String repository, String revision, String name) =>
      HubArtifactUriPolicy.resolve(
        repository: repository,
        revision: revision,
        artifactName: name,
      );

  void _validateFileName(String name) {
    if (name.startsWith('/') ||
        name.contains('..') ||
        !name.endsWith('.gguf')) {
      throw const FormatException('Unsafe GGUF artifact name');
    }
  }

  String _stableModelId(String repository, String revision, String variant) =>
      'hf-${sha256.convert('$repository\u0000$revision\u0000$variant'.codeUnits).toString().substring(0, 20)}';

  String _newJobId(String modelId) {
    final entropy = List.generate(
      ModelLibraryPolicy.downloadJobEntropyBytes,
      (_) => _identityRandom.nextInt(256),
    );
    return '$modelId-${entropy.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
  }

  String _transferId(String jobId, String artifactName) =>
      'transfer-${sha256.convert('$jobId\u0000$artifactName'.codeUnits).toString().substring(0, 32)}';
}
