// SECURITY: ModelDownloader handles model file integrity via SHA-256 verification.
// The bundled model is pinned to an immutable revision and publisher checksum.
// Downloads use the immutable HTTPS URL in BundledModelManifest.
// 3-second cooldown prevents rapid retry abuse.
// Retry behavior is defined by ModelLibraryPolicy and applies only to transient errors.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';

import '../constants/app_constants.dart';
import '../database/database_helper.dart';
import '../models/model_descriptor.dart';
import '../models/bundled_model_manifest.dart';
import '../models/model_library_policy.dart';
import '../utils/app_logger.dart';
import 'hardware_sentinel_service.dart';
import 'model_registry_service.dart';
import 'model_storage_preflight.dart';

class ModelDownloadSpec {
  const ModelDownloadSpec({
    required this.url,
    required this.fileName,
    required this.byteSize,
    required this.sha256,
  });

  final String url;
  final String fileName;
  final int byteSize;
  final String sha256;

  static const bundled = ModelDownloadSpec(
    url: BundledModelManifest.downloadUrl,
    fileName: BundledModelManifest.fileName,
    byteSize: BundledModelManifest.byteSize,
    sha256: BundledModelManifest.sha256,
  );
}

abstract interface class ModelDownloadEnvironment {
  DateTime now();

  Future<void> delay(Duration duration);

  Future<Directory> documentsDirectory();

  Future<int?> usableStorageBytes();

  Future<void> persistVerifiedModel(String filePath, ModelDownloadSpec spec);
}

abstract interface class BundledModelRegistry {
  Future<Map<String, Object?>?> read();

  Future<void> clearInstallation(String localPath);
}

final class DatabaseBundledModelRegistry implements BundledModelRegistry {
  const DatabaseBundledModelRegistry();

  @override
  Future<Map<String, Object?>?> read() =>
      DatabaseHelper.instance.getModel(BundledModelManifest.id);

  @override
  Future<void> clearInstallation(String localPath) =>
      DatabaseHelper.instance.clearModelInstallationByPath(localPath);
}

final class AndroidModelDownloadEnvironment
    implements ModelDownloadEnvironment {
  AndroidModelDownloadEnvironment({ModelRegistryService? registry})
    : _registry = registry;
  final ModelRegistryService? _registry;
  @override
  DateTime now() => DateTime.now();

  @override
  Future<void> delay(Duration duration) => Future<void>.delayed(duration);

  @override
  Future<Directory> documentsDirectory() => getApplicationDocumentsDirectory();

  @override
  Future<int?> usableStorageBytes() => queryAllocatableModelStorage();

  @override
  Future<void> persistVerifiedModel(
    String filePath,
    ModelDownloadSpec spec,
  ) async {
    if (spec.sha256 != BundledModelManifest.sha256 ||
        spec.byteSize != BundledModelManifest.byteSize ||
        spec.fileName != BundledModelManifest.fileName ||
        spec.url != BundledModelManifest.downloadUrl) {
      throw StateError('Bundled model authority does not match the manifest');
    }
    final registry = _registry;
    if (registry == null)
      throw StateError('Model installation authority is unavailable');
    await registry.installBundledModel(filePath);
  }
}

class ModelDownloader {
  final HardwareSentinelService _sentinel;
  final ModelDownloadEnvironment _environment;
  final ModelDownloadSpec _spec;
  final Dio Function() _dioFactory;
  final BundledModelRegistry _registry;
  ModelRegistryService? _resetRegistry;
  DateTime? _lastAttemptTime;

  ModelDownloader({
    required HardwareSentinelService sentinel,
    ModelDownloadEnvironment? environment,
    ModelDownloadSpec spec = ModelDownloadSpec.bundled,
    Dio Function()? dioFactory,
    BundledModelRegistry registry = const DatabaseBundledModelRegistry(),
    ModelRegistryService? resetRegistry,
  }) : _sentinel = sentinel,
       _environment = environment ?? AndroidModelDownloadEnvironment(),
       _spec = spec,
       _dioFactory = dioFactory ?? Dio.new,
       _registry = registry,
       _resetRegistry = resetRegistry;

  Future<bool> isModelDownloaded() async {
    final row = await _registry.read();
    if (row == null) return false;
    final model = ModelDescriptor.fromMap(row);
    return model.isInstalled && await File(model.localPath!).exists();
  }

  Future<String?> getModelPath() async {
    final row = await _registry.read();
    if (row == null) return null;
    final model = ModelDescriptor.fromMap(row);
    return model.isInstalled ? model.localPath : null;
  }

  Future<DownloadResult> download({
    required void Function(double progress, int downloaded, int total)
    onProgress,
    CancelToken? cancelToken,
  }) async {
    if (_lastAttemptTime != null) {
      final elapsed = _environment.now().difference(_lastAttemptTime!);
      if (elapsed.inSeconds < 3) {
        return DownloadResult.error('Please wait before retrying download.');
      }
    }
    _lastAttemptTime = _environment.now();

    final reason = _sentinel.unsafeReasonDownload();
    if (reason != null) {
      return DownloadResult.error(reason);
    }

    final dir = await _environment.documentsDirectory();
    final filePath = '${dir.path}/${_spec.fileName}';
    final partialPath = '$filePath.part';
    try {
      return await LlamaCppChatRepository.withModelFilesMutation([
        partialPath,
      ], () => _downloadOwned(filePath, partialPath, onProgress, cancelToken));
    } on InferenceRuntimeBusy {
      return DownloadResult.error('This model download is already in use.');
    }
  }

  Future<DownloadResult> _downloadOwned(
    String filePath,
    String partialPath,
    void Function(double, int, int) onProgress,
    CancelToken? cancelToken,
  ) async {
    final destination = File(filePath);
    if (await destination.exists()) {
      if (!await _matchesPinnedModel(destination)) {
        return DownloadResult.error(
          'An existing model needs explicit repair; it was preserved.',
        );
      }
      try {
        await _environment.persistVerifiedModel(filePath, _spec);
        return DownloadResult.success(filePath);
      } catch (_) {
        return DownloadResult.error(
          'Model activation failed; the existing file was preserved.',
        );
      }
    }
    final usable = await _environment.usableStorageBytes();
    final requiredBytes = (_spec.byteSize * 1.15).ceil();
    if (usable != null && usable < requiredBytes) {
      return DownloadResult.error(
        'Not enough free storage for the model and verification copy.',
      );
    }

    for (
      int attempt = 0;
      attempt <= ModelLibraryPolicy.maximumTransferAttempts;
      attempt++
    ) {
      try {
        final dio = _dioFactory()
          ..options.connectTimeout = AppConstants.requestTimeout
          ..options.receiveTimeout = const Duration(minutes: 20);
        final partial = File(partialPath);
        final existingBytes = partial.existsSync() ? partial.lengthSync() : 0;

        final response = await dio.download(
          _spec.url,
          partialPath,
          cancelToken: cancelToken,
          options: Options(
            headers: existingBytes > 0
                ? {'Range': 'bytes=$existingBytes-'}
                : null,
          ),
          deleteOnError: false,
          fileAccessMode: existingBytes > 0
              ? FileAccessMode.append
              : FileAccessMode.write,
          onReceiveProgress: (received, total) {
            final downloaded = existingBytes + received;
            final expectedTotal = total > 0
                ? existingBytes + total
                : _spec.byteSize;
            final progress = expectedTotal > 0
                ? downloaded / expectedTotal
                : 0.0;
            onProgress(progress.clamp(0.0, 1.0), downloaded, expectedTotal);
          },
        );

        if (existingBytes > 0 && response.statusCode != 206) {
          await partial.delete();
          if (attempt == ModelLibraryPolicy.maximumTransferAttempts) {
            return DownloadResult.error('Server did not accept resume request');
          }
          continue;
        }

        final file = File(partialPath);
        if (!file.existsSync() || file.lengthSync() == 0) {
          return DownloadResult.error('Downloaded file is missing or empty');
        }

        final verified = await _verifyModelIntegrity(partialPath);
        if (!verified) {
          return DownloadResult.error('Model file integrity check failed');
        }

        // A destination appearing during transfer belongs to another operation.
        // Never overwrite it, even if this download's bytes have validated.
        final moved = await LlamaCppChatRepository.withModelFilesMutation(
          [filePath],
          () async {
            if (await destination.exists()) return false;
            await file.rename(filePath);
            return true;
          },
        );
        if (!moved) {
          return DownloadResult.error(
            'Model destination changed; retry after verification.',
          );
        }
        try {
          await _environment.persistVerifiedModel(filePath, _spec);
        } catch (error) {
          // Do not leave an activated file whose registry/preferences were not
          // transactionally finalized.
          try {
            await LlamaCppChatRepository.withModelFilesMutation(
              [filePath],
              () async {
                if (await File(partialPath).exists()) {
                  throw StateError(
                    'Partial destination changed during activation',
                  );
                }
                await destination.rename(partialPath);
              },
            );
          } catch (rollbackError) {
            AppLogger.instance.warning(
              'Model activation rollback was deferred (${rollbackError.runtimeType})',
            );
          }
          return DownloadResult.error('Model activation failed');
        }

        return DownloadResult.success(filePath);
      } on InferenceRuntimeBusy {
        return DownloadResult.error(
          'Model files are in use; retry after the current operation.',
        );
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          return DownloadResult.cancelled();
        }

        final statusCode = e.response?.statusCode;
        final isTransient =
            statusCode == 429 ||
            (statusCode != null && statusCode >= 500 && statusCode <= 599) ||
            e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout;

        if (!isTransient ||
            attempt == ModelLibraryPolicy.maximumTransferAttempts) {
          final isPermanentClientError =
              statusCode != null &&
              statusCode >= 400 &&
              statusCode < 500 &&
              statusCode != 429;
          if (isPermanentClientError) {
            try {
              await File(partialPath).delete();
            } catch (cleanupError) {
              AppLogger.instance.warningFailure(
                'Rejected download cleanup was deferred',
                cleanupError,
              );
            }
          }
          final safeMessage =
              'Download failed: ${e.type.name}'
              '${e.response != null ? ' (HTTP $statusCode)' : ''}';
          return DownloadResult.error(safeMessage);
        }

        await _environment.delay(_retryDelay(e, attempt));
      } catch (e) {
        // Preserve a partially received file for a later Range retry. Integrity
        // failures are deleted explicitly by `_verifyModelIntegrity`.
        return DownloadResult.error('Download failed');
      }
    }

    return DownloadResult.error(
      'Download failed after ${ModelLibraryPolicy.maximumTransferAttempts} retries',
    );
  }

  Future<void> resetState() async {
    try {
      final row = await _registry.read();
      if (row == null) return;
      // Registry identity, controlled roots, aliases and native writer leases
      // are governed by the same authority as Model Library uninstall.
      await (_resetRegistry ??= ModelRegistryService()).uninstall(
        BundledModelManifest.id,
      );
    } on InferenceRuntimeBusy {
      rethrow;
    } on ModelStorageBusy {
      rethrow;
    } catch (error) {
      AppLogger.instance.warning('Bundled reset failed (${error.runtimeType})');
      throw StateError(
        'Bundled model reset did not complete. Verify it in Model Library.',
      );
    }
  }

  Future<bool> _matchesPinnedModel(File file) async {
    try {
      if (await file.length() != _spec.byteSize) return false;
      return (await sha256.bind(file.openRead()).first).toString() ==
          _spec.sha256;
    } catch (error) {
      AppLogger.instance.warning(
        'Existing model verification unavailable (${error.runtimeType})',
      );
      return false;
    }
  }

  Future<bool> _verifyModelIntegrity(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.length() != _spec.byteSize) {
        AppLogger.instance.errorSync(
          'Model size did not match pinned metadata',
        );
        await file.delete();
        return false;
      }
      final hash = (await sha256.bind(file.openRead()).first).toString();
      if (hash != _spec.sha256) {
        AppLogger.instance.errorSync(
          'Model integrity check failed: expected the pinned checksum',
        );
        try {
          await file.delete();
        } catch (cleanupError) {
          AppLogger.instance.warningFailure(
            'Invalid model cleanup was deferred',
            cleanupError,
          );
        }
        return false;
      }

      AppLogger.instance.infoSync('Model integrity verified');
      return true;
    } catch (e) {
      AppLogger.instance.errorFailureSync('Model verification error', e);
      return false;
    }
  }

  Duration _retryDelay(DioException error, int attempt) {
    final retryAfter = error.response?.headers.value('retry-after');
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter);
      if (seconds != null) {
        return Duration(seconds: seconds.clamp(1, 60));
      }
      try {
        final date = HttpDate.parse(retryAfter);
        final delay = date.difference(_environment.now().toUtc());
        if (!delay.isNegative) {
          return delay > const Duration(seconds: 60)
              ? const Duration(seconds: 60)
              : delay;
        }
      } on FormatException {
        // Ignore malformed Retry-After and use bounded exponential backoff.
      }
    }
    return Duration(
      seconds:
          ModelLibraryPolicy.bundledRetryBackoffSeconds[attempt.clamp(
            0,
            ModelLibraryPolicy.bundledRetryBackoffSeconds.length - 1,
          )],
    );
  }
}

class DownloadResult {
  final bool isSuccess;
  final bool isCancelled;
  final String? error;
  final String? filePath;

  DownloadResult._({
    required this.isSuccess,
    required this.isCancelled,
    this.error,
    this.filePath,
  });

  factory DownloadResult.success(String path) =>
      DownloadResult._(isSuccess: true, isCancelled: false, filePath: path);

  factory DownloadResult.error(String message) =>
      DownloadResult._(isSuccess: false, isCancelled: false, error: message);

  factory DownloadResult.cancelled() =>
      DownloadResult._(isSuccess: false, isCancelled: true);
}
