import 'dart:async';
import 'dart:io';
import 'application_private_directory.dart';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/database_helper.dart';
import '../database/model_installation_journal.dart';
import '../models/imported_model_file.dart';
export '../models/imported_model_file.dart';
import '../models/model_descriptor.dart';
import '../models/bundled_model_manifest.dart';
import '../models/model_storage_error.dart';
export '../models/model_storage_error.dart';
import '../models/model_verification_phase.dart';
import '../models/model_library_policy.dart';
import '../models/runtime_profile.dart';
import 'runtime_capabilities_provider.dart';
import 'runtime_profile_store.dart';
import 'model_verification_runtime.dart';
import 'model_shard_restorer.dart';
import '../utils/app_logger.dart';

typedef ModelRootResolver = Future<List<Directory>> Function();
typedef ModelDirectoryResolver = Future<Directory> Function();
typedef GgufMetadataReader = Future<GgufMetadata> Function(String path);
typedef CompatibilityProbeFactory =
    LlamaCppChatRepository Function({
      required String modelPath,
      required RuntimeProfile profile,
    });

class ModelRegistryService {
  void _reportVerificationPhase(
    ModelVerificationPhaseSink? sink,
    ModelVerificationPhase phase,
  ) {
    try {
      sink?.call(phase);
    } catch (_) {
      AppLogger.instance.warning('Model verification phase observer failed');
    }
  }

  ModelRegistryService({
    DatabaseHelper? database,
    RuntimeProfileStore? profileStore,
    RuntimeCapabilitiesProvider? capabilitiesProvider,
    ModelRootResolver? allowedRoots,
    ModelImportPicker? importPicker,
    ModelImportSetPicker? restoreSetPicker,
    ModelDirectoryResolver? documentsDirectory,
    GgufMetadataReader? metadataReader,
    CompatibilityProbeFactory? probeFactory,
    DateTime Function()? clock,
    void Function()? checkProbeSafety,
    this.probeSafetyChanges,
    this.probeDeadline = CompatibilityProbePolicy.generationDeadline,
  }) : _database = database ?? DatabaseHelper.instance,
       _profileStore = profileStore ?? SharedPreferencesRuntimeProfileStore(),
       _capabilitiesProvider =
           capabilitiesProvider ?? const AndroidRuntimeCapabilitiesProvider(),
       _allowedRoots = allowedRoots ?? _defaultAllowedRoots,
       _importPicker = importPicker ?? _defaultImportPicker,
       _restoreSetPicker = restoreSetPicker ?? _defaultRestoreSetPicker,
       _documentsDirectory = documentsDirectory ?? applicationPrivateDirectory,
       _metadataReader = metadataReader ?? GgufMetadata.fromFile,
       _probeFactory = probeFactory ?? _defaultProbeFactory,
       checkProbeSafety = checkProbeSafety ?? _unknownProbeSafety,
       _clock = clock ?? DateTime.now;

  final DatabaseHelper _database;
  final RuntimeProfileStore _profileStore;
  final RuntimeCapabilitiesProvider _capabilitiesProvider;
  final ModelRootResolver _allowedRoots;
  final ModelImportPicker _importPicker;
  final ModelImportSetPicker _restoreSetPicker;
  final ModelDirectoryResolver _documentsDirectory;
  final GgufMetadataReader _metadataReader;
  final CompatibilityProbeFactory _probeFactory;
  final DateTime Function() _clock;
  final Duration probeDeadline;
  final void Function() checkProbeSafety;
  final Stream<bool>? probeSafetyChanges;

  static void _unknownProbeSafety() => throw ModelProbeSafetyStop();

  void _checkProbeSafety() {
    try {
      checkProbeSafety();
    } catch (_) {
      throw ModelProbeSafetyStop();
    }
  }

  final _verificationRuntime = ModelVerificationRuntime();
  Directory? _retainedImportStaging;
  Future<RuntimeRecoveryOutcome>? _probeRecovery;
  bool _disposed = false;
  Future<void>? _closeFuture;
  final Set<Future<void>> _storageOperations = {};

  Completer<void> _beginStorageOperation() {
    final finished = Completer<void>();
    _storageOperations.add(finished.future);
    return finished;
  }

  void _finishStorageOperation(Completer<void> finished) {
    _storageOperations.remove(finished.future);
    finished.complete();
  }

  Future<void> close() {
    final pending = _closeFuture;
    if (pending != null) return pending;
    final completion = Completer<void>();
    _closeFuture = completion.future;
    _disposed = true;
    unawaited(
      Future<void>.sync(_finishClose).then<void>(
        (_) => completion.complete(),
        onError: (Object error, StackTrace stack) =>
            completion.completeError(error, stack),
      ),
    );
    return completion.future;
  }

  Future<void> _finishClose() async {
    Object? nativeFailure;
    StackTrace? nativeStack;
    try {
      await _verificationRuntime.close();
    } catch (error, stack) {
      nativeFailure = error;
      nativeStack = stack;
    }
    await Future.wait(_storageOperations.toList(growable: false));
    if (nativeFailure != null)
      Error.throwWithStackTrace(nativeFailure, nativeStack!);
    if (requiresProbeRecovery) throw InferenceRecoveryRequired();
  }

  void dispose() {
    unawaited(
      close().then<void>(
        (_) {},
        onError: (Object error, StackTrace _) {
          AppLogger.instance.warning(
            'Model verification shutdown unconfirmed (${error.runtimeType})',
          );
        },
      ),
    );
  }

  void _checkNotDisposed() {
    if (_disposed) throw InferenceRepositoryDisposed();
  }

  bool get requiresProbeRecovery =>
      _verificationRuntime.requiresRecovery || _retainedImportStaging != null;

  /// Recovery never selects a model or changes a chat assignment. Staging may
  /// be removed only after native owner cleanup has acknowledged.
  Future<RuntimeRecoveryOutcome> recoverProbeCleanup() {
    final pending = _probeRecovery;
    if (pending != null) return pending;
    if (!requiresProbeRecovery) return Future.error(InferenceRuntimeBusy());
    final completion = Completer<RuntimeRecoveryOutcome>();
    _probeRecovery = completion.future;
    unawaited(() async {
      try {
        final outcome = _verificationRuntime.requiresRecovery
            ? await _verificationRuntime.recoverOwnedCleanup()
            : RuntimeRecoveryOutcome.recovered;
        if (outcome == RuntimeRecoveryOutcome.recovered) {
          final staging = _retainedImportStaging;
          if (staging != null && await staging.exists()) {
            await staging.delete(recursive: true);
          }
          _retainedImportStaging = null;
        }
        _probeRecovery = null;
        completion.complete(outcome);
      } catch (error, stack) {
        _probeRecovery = null;
        completion.completeError(error, stack);
      }
    }());
    return completion.future;
  }

  void _checkProbeAvailable() {
    _checkNotDisposed();
    if (_probeRecovery != null) throw InferenceRuntimeBusy();
    if (requiresProbeRecovery) throw InferenceRecoveryRequired();
    _verificationRuntime.checkAvailable();
  }

  static Future<ImportedModelFile?> _defaultImportPicker() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gguf'],
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    return ImportedModelFile(
      name: file.name,
      size: file.size,
      readStream: file.readStream,
    );
  }

  static Future<List<ImportedModelFile>?> _defaultRestoreSetPicker() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gguf'],
      withReadStream: true,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return null;
    return [
      for (final file in result.files)
        ImportedModelFile(
          name: file.name,
          size: file.size,
          readStream: file.readStream,
        ),
    ];
  }

  static LlamaCppChatRepository _defaultProbeFactory({
    required String modelPath,
    required RuntimeProfile profile,
  }) => LlamaCppChatRepository.withModelPath(
    modelPath,
    contextSize: profile.contextSize,
    batchSize: profile.batchSize,
    threads: profile.generationThreads,
    nGpuLayers: 0,
  );

  Future<List<ModelDescriptor>> listModels() async =>
      (await _database.getModels()).map(ModelDescriptor.fromMap).toList();

  // Imports share the native probe and final content-addressed directory even
  // when initiated through different registry instances in the UI isolate.
  static bool _importInProgress = false;
  static bool _uninstallInProgress = false;
  static int _validationOperations = 0;
  static int _verificationOperations = 0;

  Future<ModelDescriptor?> importGguf() async {
    _checkProbeAvailable();
    if (_uninstallInProgress ||
        _validationOperations != 0 ||
        _verificationOperations != 0)
      throw ModelStorageBusy();
    if (_importInProgress) throw StateError('modelImportBusy');
    _importInProgress = true;
    final finished = _beginStorageOperation();
    try {
      return await _importGguf();
    } finally {
      _importInProgress = false;
      _finishStorageOperation(finished);
    }
  }

  Future<ModelDescriptor?> _importGguf() async {
    final picked = await _importPicker();
    _checkNotDisposed();
    if (picked == null) return null;
    if (picked.size < 1024 * 1024) {
      throw const FormatException('The selected GGUF file is too small');
    }

    final documents = await _documentsDirectory();
    final modelsDirectory = Directory('${documents.path}/models');
    await modelsDirectory.create(recursive: true);
    final staging = await modelsDirectory.createTemp('import-');
    final temporary = File(p.join(staging.path, 'model.part'));
    try {
      final digestSink = _DigestSink();
      final hashSink = sha256.startChunkedConversion(digestSink);
      final output = temporary.openWrite();
      try {
        final input = picked.readStream;
        if (input == null)
          throw StateError('The selected file is not readable');
        await for (final chunk in input) {
          hashSink.add(chunk);
          output.add(chunk);
        }
        hashSink.close();
        await output.close();
      } catch (_) {
        await output.close();
        if (await temporary.exists()) await temporary.delete();
        rethrow;
      }
      final hash = digestSink.value.toString();
      final header = await temporary
          .openRead(0, 4)
          .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
      if (header.length != 4 || String.fromCharCodes(header) != 'GGUF') {
        await temporary.delete();
        throw const FormatException('The selected file is not a GGUF model');
      }

      final metadata = await _metadataReader(temporary.path);
      final architecture = metadata.architecture?.trim();
      final tokenizer = metadata.get<String>('tokenizer.ggml.model')?.trim();
      final chatTemplate = metadata
          .get<String>('tokenizer.chat_template')
          ?.trim();
      final blockCount = metadata.get<int>('$architecture.block_count');
      final supportsThinking = _supportsThinkingTemplate(chatTemplate);
      if (architecture == null || architecture.isEmpty) {
        await temporary.delete();
        throw const FormatException('GGUF architecture metadata is missing');
      }
      if (tokenizer == null || tokenizer.isEmpty) {
        await temporary.delete();
        throw const FormatException('GGUF tokenizer metadata is missing');
      }
      if (chatTemplate == null || chatTemplate.isEmpty) {
        await temporary.delete();
        throw const FormatException('GGUF chat template is missing');
      }

      final id = 'local-${hash.substring(0, 16)}';
      final destination = File('${modelsDirectory.path}/$id.gguf');
      final existing = await findById(id);
      if (existing != null && existing.sha256 != hash) {
        throw StateError('Model identity collision');
      }
      if (await destination.exists()) {
        final storedHash = (await sha256.bind(destination.openRead()).first)
            .toString();
        if (storedHash != hash) {
          throw StateError('Existing model file requires explicit repair');
        }
        if (existing != null &&
            existing.isInstalled &&
            existing.compatibilityStatus == 'compatible' &&
            existing.localPath == destination.path) {
          return existing;
        }
      }

      final probeDescriptor = ModelDescriptor(
        id: id,
        displayName: metadata.name ?? picked.name,
        source: 'local_import',
        compatibilityStatus: 'probing',
        localPath: temporary.path,
        sha256: hash,
        byteSize: await temporary.length(),
        architecture: architecture,
        tokenizer: tokenizer,
        contextTrain: metadata.contextLength,
        chatTemplate: chatTemplate,
        blockCount: blockCount,
        supportsThinking: supportsThinking,
      );
      final capabilities = await _capabilitiesProvider.snapshot();
      _checkNotDisposed();
      if (capabilities.isSevere) throw ModelProbeSafetyStop();
      _checkProbeSafety();
      final probeProfile = RuntimeProfile.forCompatibilityProbe(
        probeDescriptor,
        capabilities,
      );
      final repository = _probeFactory(
        modelPath: temporary.path,
        profile: probeProfile,
      );
      await _runCompatibilityProbe(repository, probeProfile);
      _checkNotDisposed();
      // Only promote validated staging bytes. Existing files are never replaced
      // by import, including when a probe fails or the registry write fails.
      if (!await destination.exists()) await temporary.rename(destination.path);

      final descriptor = ModelDescriptor(
        id: id,
        displayName:
            metadata.name ??
            picked.name.replaceFirst(
              RegExp(r'\.gguf$', caseSensitive: false),
              '',
            ),
        localPath: destination.path,
        source: 'local_import',
        sha256: hash,
        byteSize: await destination.length(),
        architecture: architecture,
        tokenizer: tokenizer,
        contextTrain: metadata.contextLength,
        chatTemplate: chatTemplate,
        blockCount: blockCount,
        supportsThinking: supportsThinking,
        compatibilityStatus: 'compatible',
        installedAt: _clock(),
        installationState: 'installed',
      );
      await _database.upsertModel(descriptor.toMap());
      return descriptor;
    } finally {
      // This unique directory was created by this invocation, not supplied by
      // the document picker. No installed model is under this cleanup target.
      if (_verificationRuntime.requiresRecovery) {
        // These bytes may still back a native mapping. Retain this invocation's
        // unique staging directory until acknowledged owner recovery.
        _retainedImportStaging = staging;
      } else if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }

  Future<void> activate(ModelDescriptor model) async {
    if (!model.isInstalled) {
      throw StateError('The selected model is not installed');
    }
  }

  Future<ModelDescriptor> requireInstalled(String id) async {
    final model = await findById(id);
    if (model == null || !model.isInstalled) {
      throw StateError('The selected model is not installed');
    }
    if (!await File(model.localPath!).exists()) {
      throw StateError('The selected model file is unavailable');
    }
    return model;
  }

  Future<ModelDescriptor?> findById(String id) async {
    final row = await _database.getModel(id);
    return row == null ? null : ModelDescriptor.fromMap(row);
  }

  Future<ModelDescriptor?> findByPath(String path) async {
    final row = await _database.getModelByPath(path);
    return row == null ? null : ModelDescriptor.fromMap(row);
  }

  /// Restores a single-file record only after its replacement is proved to be
  /// the same bytes and passes a real compatibility probe. Chat assignments
  /// and the old registry row remain untouched on every failed attempt.
  Future<ModelDescriptor?> restoreMissingFile(
    String modelId, {
    ModelVerificationPhaseSink? onPhase,
  }) async {
    _checkProbeAvailable();
    if (_importInProgress ||
        _uninstallInProgress ||
        _validationOperations != 0 ||
        _verificationOperations != 0) {
      throw ModelStorageBusy();
    }
    _importInProgress = true;
    final finished = _beginStorageOperation();
    try {
      final current = await findById(modelId);
      _checkNotDisposed();
      if (current == null ||
          current.sha256 == null ||
          current.localPath == null) {
        throw StateError('Recorded model identity is unavailable');
      }
      final artifacts = await _database.getModelFiles(modelId);
      if (artifacts.length > 1) {
        return await ModelShardRestorer(
          journal: ModelInstallationJournal(
            database: () => _database.database,
            clock: _clock,
          ),
          modelsDirectory: () async =>
              Directory(p.join((await _documentsDirectory()).path, 'models')),
          picker: _restoreSetPicker,
          checkActive: _checkNotDisposed,
          validate: (expected, primary) => _validateDownloadedModel(
            modelId: modelId,
            primaryPath: primary,
            expectedDescriptor: expected,
            onPhase: onPhase,
            persist: false,
          ),
        ).restore(
          current,
          artifacts,
          onPhase: (phase) => _reportVerificationPhase(onPhase, phase),
        );
      }
      if (await File(current.localPath!).exists()) {
        throw StateError('The recorded model file is still present');
      }
      if (artifacts.isNotEmpty &&
          (artifacts.length != 1 ||
              artifacts.single['shard_count'] != 1 ||
              (artifacts.single['shard_index'] ?? 0) != 0 ||
              artifacts.single['sha256'] != current.sha256 ||
              artifacts.single['byte_size'] != current.byteSize)) {
        throw StateError('Split models require complete shard recovery');
      }
      final picked = await _importPicker();
      _checkNotDisposed();
      if (picked == null) return null;
      final input = picked.readStream;
      if (input == null) throw StateError('The selected file is not readable');
      final documents = await _documentsDirectory();
      final modelsDirectory = Directory(p.join(documents.path, 'models'));
      await modelsDirectory.create(recursive: true);
      final staging = await modelsDirectory.createTemp('restore-');
      final temporary = File(p.join(staging.path, 'model.part'));
      try {
        _reportVerificationPhase(onPhase, ModelVerificationPhase.hashing);
        final output = temporary.openWrite();
        try {
          var received = 0;
          await for (final chunk in input) {
            _checkNotDisposed();
            received += chunk.length;
            if (received > picked.size ||
                (current.byteSize != null && received > current.byteSize!)) {
              throw ModelIdentityMismatch();
            }
            output.add(chunk);
          }
          await output.flush();
        } finally {
          await output.close();
        }
        _checkNotDisposed();
        final actualSize = await temporary.length();
        if (actualSize != picked.size ||
            (current.byteSize != null && actualSize != current.byteSize)) {
          throw ModelIdentityMismatch();
        }
        final hash = (await sha256.bind(temporary.openRead()).first).toString();
        if (hash.toLowerCase() != current.sha256!.toLowerCase()) {
          throw ModelIdentityMismatch();
        }
        final validated = await _validateDownloadedModel(
          modelId: modelId,
          primaryPath: temporary.path,
          onPhase: onPhase,
          persist: false,
        );
        _checkNotDisposed();
        final destination = File(
          p.join(modelsDirectory.path, 'restored-$hash.gguf'),
        );
        if (await destination.exists()) {
          await _verifyFile(
            destination,
            expectedSize: actualSize,
            expectedHash: hash,
          );
        } else {
          await temporary.rename(destination.path);
        }
        final restored = ModelDescriptor.fromMap({
          ...validated.toMap(),
          'local_path': destination.path,
        });
        await _database.restoreModelInstallation(
          restored.toMap(),
          expectedPath: current.localPath!,
          expectedHash: current.sha256!,
          artifactId: artifacts.isEmpty ? null : artifacts.single['id'] as int,
        );
        return restored;
      } finally {
        if (_verificationRuntime.requiresRecovery) {
          _retainedImportStaging = staging;
        } else if (await staging.exists()) {
          await staging.delete(recursive: true);
        }
      }
    } finally {
      _importInProgress = false;
      _finishStorageOperation(finished);
    }
  }

  Future<ModelDescriptor> verifyInstallation(
    String modelId, {
    ModelVerificationPhaseSink? onPhase,
  }) async {
    _checkProbeAvailable();
    if (_uninstallInProgress || _importInProgress) throw ModelStorageBusy();
    _verificationOperations++;
    final finished = _beginStorageOperation();
    try {
      return await _verifyInstallation(modelId, onPhase: onPhase);
    } finally {
      _verificationOperations--;
      _finishStorageOperation(finished);
    }
  }

  Future<ModelDescriptor> _verifyInstallation(
    String modelId, {
    ModelVerificationPhaseSink? onPhase,
  }) async {
    final model = await findById(modelId);
    _checkNotDisposed();
    if (model == null || model.localPath == null) {
      throw StateError('The selected model is not installed');
    }
    try {
      _reportVerificationPhase(onPhase, ModelVerificationPhase.hashing);
      final records = await _database.getModelFiles(modelId);
      if (records.isEmpty) {
        await _verifyFile(
          File(model.localPath!),
          expectedSize: model.byteSize,
          expectedHash: model.sha256,
        );
      } else {
        for (final record in records) {
          final localPath = record['local_path'] as String?;
          if (localPath == null) {
            throw StateError('An installed model shard is unavailable');
          }
          await _verifyFile(
            File(localPath),
            expectedSize: record['byte_size'] as int?,
            expectedHash: record['sha256'] as String?,
          );
        }
      }
      return await validateDownloadedModel(
        modelId: modelId,
        primaryPath: model.localPath!,
        onPhase: onPhase,
      );
    } on ModelProbeSafetyStop {
      // Device pressure is not evidence of invalid model bytes.
      rethrow;
    } on ModelStorageBusy {
      rethrow;
    } on InferenceRuntimeBusy {
      // A busy runtime says nothing about the validity of installed bytes.
      rethrow;
    } on InferenceRecoveryRequired {
      // Runtime quarantine says nothing about this model's file integrity.
      rethrow;
    } on InferenceRepositoryDisposed {
      // Closing verification is not evidence that the installed model is invalid.
      rethrow;
    } catch (_) {
      _checkNotDisposed();
      await _database.upsertModel({
        ...model.toMap(),
        'compatibility_status': 'verification_failed',
        'installation_state': 'verification_failed',
      });
      rethrow;
    }
  }

  Future<void> uninstall(String modelId) async {
    _checkProbeAvailable();
    if (_importInProgress ||
        _uninstallInProgress ||
        _validationOperations != 0 ||
        _verificationOperations != 0)
      throw ModelStorageBusy();
    _uninstallInProgress = true;
    final finished = _beginStorageOperation();
    try {
      await _uninstall(modelId);
    } finally {
      _uninstallInProgress = false;
      _finishStorageOperation(finished);
    }
  }

  Future<void> _uninstall(String modelId) async {
    final model = await findById(modelId);
    if (model == null) throw StateError('Model registry entry is missing');
    final records = await _database.getModelFiles(modelId);
    final paths = <String>{
      if (model.localPath != null) model.localPath!,
      for (final record in records)
        if (record['local_path'] case final String path) path,
    };
    final retainedPaths = <String>{};
    final allModels = await listModels();
    for (final other in allModels) {
      if (other.id == modelId) continue;
      if (other.localPath != null) {
        retainedPaths.add(
          LlamaCppChatRepository.modelFileIdentity(other.localPath!),
        );
      }
      for (final record in await _database.getModelFiles(other.id)) {
        if (record['local_path'] case final String path) {
          retainedPaths.add(LlamaCppChatRepository.modelFileIdentity(path));
        }
      }
    }
    _checkNotDisposed();
    final removedPaths = paths
        .where(
          (path) => !retainedPaths.contains(
            LlamaCppChatRepository.modelFileIdentity(path),
          ),
        )
        .toSet();
    await LlamaCppChatRepository.withModelFilesMutation(removedPaths, () async {
      final roots = (await _allowedRoots())
          .map((root) => p.normalize(p.absolute(root.path)))
          .toList(growable: false);
      for (final path in paths) {
        final normalized = p.normalize(p.absolute(path));
        if (!roots.any((root) => p.isWithin(root, normalized))) {
          throw StateError(
            'Refusing to remove a model file outside VITALIS storage',
          );
        }
      }
      _checkNotDisposed();
      for (final path in removedPaths) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      if (model.sha256 != null &&
          !allModels.any(
            (other) =>
                other.id != modelId &&
                other.isInstalled &&
                other.sha256?.toLowerCase() == model.sha256!.toLowerCase(),
          )) {
        await _profileStore.invalidateModel(model.sha256!);
      }
      await _database.clearModelInstallation(modelId);
    });
  }

  /// Installs only the immutable bundled identity, after real compatibility
  /// inference and acknowledged cleanup. Existing records survive failures.
  Future<ModelDescriptor> installBundledModel(String primaryPath) async {
    _checkProbeAvailable();
    if (_uninstallInProgress ||
        _importInProgress ||
        _validationOperations != 0 ||
        _verificationOperations != 0) {
      throw ModelStorageBusy();
    }
    _validationOperations++;
    final finished = _beginStorageOperation();
    try {
      final previous = await findById(BundledModelManifest.id);
      _checkNotDisposed();
      if (previous?.sha256 case final String hash) {
        if (hash.toLowerCase() != BundledModelManifest.sha256) {
          throw ModelIdentityMismatch();
        }
      }
      await _verifyFile(
        File(primaryPath),
        expectedSize: BundledModelManifest.byteSize,
        expectedHash: BundledModelManifest.sha256,
      );
      _checkNotDisposed();
      final expected = ModelDescriptor(
        id: BundledModelManifest.id,
        displayName: BundledModelManifest.displayName,
        source: BundledModelManifest.source,
        compatibilityStatus: 'unvalidated',
        localPath: primaryPath,
        sha256: BundledModelManifest.sha256,
        byteSize: BundledModelManifest.byteSize,
        repository: BundledModelManifest.repository,
        revision: BundledModelManifest.revision,
        quantization: BundledModelManifest.quantization,
        parameterCount: BundledModelManifest.parameterCount,
      );
      final validated = await _validateDownloadedModel(
        modelId: expected.id,
        primaryPath: primaryPath,
        expectedDescriptor: expected,
        persist: false,
      );
      _checkNotDisposed();
      await _database.upsertModel(validated.toMap());
      return validated;
    } finally {
      _validationOperations--;
      _finishStorageOperation(finished);
    }
  }

  Future<ModelDescriptor> validateDownloadedModel({
    required String modelId,
    required String primaryPath,
    ModelVerificationPhaseSink? onPhase,
  }) async {
    _checkProbeAvailable();
    if (_uninstallInProgress || _importInProgress) throw ModelStorageBusy();
    _validationOperations++;
    final finished = _beginStorageOperation();
    try {
      return await _validateDownloadedModel(
        modelId: modelId,
        primaryPath: primaryPath,
        onPhase: onPhase,
      );
    } on InferenceRecoveryRequired {
      rethrow;
    } catch (_) {
      _checkNotDisposed();
      rethrow;
    } finally {
      _validationOperations--;
      _finishStorageOperation(finished);
    }
  }

  Future<ModelDescriptor> _validateDownloadedModel({
    required String modelId,
    required String primaryPath,
    ModelVerificationPhaseSink? onPhase,
    bool persist = true,
    ModelDescriptor? expectedDescriptor,
  }) async {
    final current = expectedDescriptor ?? await findById(modelId);
    _checkNotDisposed();
    if (current == null) throw StateError('Model registry entry is missing');
    final file = File(primaryPath);
    if (!await file.exists()) throw StateError('Downloaded model is missing');
    final header = await file.openRead(0, 4).expand((chunk) => chunk).toList();
    _checkNotDisposed();
    if (header.length != 4 || String.fromCharCodes(header) != 'GGUF') {
      throw const FormatException('Downloaded file is not GGUF');
    }
    _reportVerificationPhase(onPhase, ModelVerificationPhase.metadata);
    final metadata = await _metadataReader(primaryPath);
    _checkNotDisposed();
    final architecture = metadata.architecture?.trim();
    final tokenizer = metadata.get<String>('tokenizer.ggml.model')?.trim();
    final template = metadata.get<String>('tokenizer.chat_template')?.trim();
    if (architecture == null || architecture.isEmpty) {
      throw const FormatException('GGUF architecture metadata is missing');
    }
    if (tokenizer == null || tokenizer.isEmpty) {
      throw const FormatException('GGUF tokenizer metadata is missing');
    }
    if (template == null || template.isEmpty) {
      throw const FormatException('GGUF chat template is missing');
    }
    final probeDescriptor = ModelDescriptor(
      id: current.id,
      displayName: current.displayName,
      source: current.source,
      compatibilityStatus: 'probing',
      localPath: primaryPath,
      sha256: current.sha256,
      byteSize: current.byteSize,
      architecture: architecture,
      tokenizer: tokenizer,
      contextTrain: metadata.contextLength,
      chatTemplate: template,
      blockCount: metadata.get<int>('$architecture.block_count'),
      supportsThinking: _supportsThinkingTemplate(template),
    );
    final capabilities = await _capabilitiesProvider.snapshot();
    _checkNotDisposed();
    if (capabilities.isSevere) throw ModelProbeSafetyStop();
    _checkProbeSafety();
    final probeProfile = RuntimeProfile.forCompatibilityProbe(
      probeDescriptor,
      capabilities,
    );
    final probe = _probeFactory(modelPath: primaryPath, profile: probeProfile);
    _reportVerificationPhase(onPhase, ModelVerificationPhase.waitingForRuntime);
    await _runCompatibilityProbe(probe, probeProfile, onPhase: onPhase);
    _checkNotDisposed();
    final validated = ModelDescriptor(
      id: current.id,
      displayName: current.displayName,
      source: current.source,
      compatibilityStatus: 'compatible',
      localPath: primaryPath,
      sha256: current.sha256,
      byteSize: current.byteSize,
      architecture: architecture,
      tokenizer: tokenizer,
      contextTrain: metadata.contextLength,
      chatTemplate: template,
      blockCount: metadata.get<int>('$architecture.block_count'),
      supportsThinking: _supportsThinkingTemplate(template),
      installedAt: _clock(),
      repository: current.repository,
      revision: current.revision,
      quantization: current.quantization,
      parameterCount: current.parameterCount,
      license: current.license,
      remoteMetadataJson: current.remoteMetadataJson,
      installationState: 'installed',
      lastUsedAt: current.lastUsedAt,
      updateRevision: current.updateRevision,
    );
    if (persist) await _database.upsertModel(validated.toMap());
    return validated;
  }

  static bool _supportsThinkingTemplate(String? template) {
    return VerifiedThinkingTemplates.supports(template);
  }

  Future<void> _runCompatibilityProbe(
    LlamaCppChatRepository repository,
    RuntimeProfile profile, {
    ModelVerificationPhaseSink? onPhase,
  }) => _verificationRuntime.run(repository, () async {
    var revoked = false;
    Future<void>? stopping;
    void revokeSafety() {
      if (revoked) return;
      revoked = true;
      // Closing this admitted owner uses the repository's shared native
      // cancellation and context drain. The runtime retains failed cleanup.
      stopping = Future<void>.sync(repository.close).then<void>(
        (_) {},
        onError: (Object error, StackTrace _) {
          AppLogger.instance.warning(
            'Probe safety shutdown unconfirmed (${error.runtimeType})',
          );
        },
      );
    }

    void checkSafety() {
      if (revoked) throw ModelProbeSafetyStop();
      try {
        _checkProbeSafety();
      } on ModelProbeSafetyStop {
        revokeSafety();
        rethrow;
      }
    }

    final subscription = probeSafetyChanges?.listen(
      (safe) {
        if (!safe) revokeSafety();
      },
      onError: (Object _, StackTrace __) => revokeSafety(),
      onDone: revokeSafety,
    );
    try {
      await _evaluateCompatibilityProbe(
        repository,
        profile,
        checkSafety: checkSafety,
        onPhase: onPhase,
      );
      checkSafety();
    } catch (_) {
      if (revoked) throw ModelProbeSafetyStop();
      rethrow;
    } finally {
      await subscription?.cancel();
      await stopping;
    }
  });

  Future<void> _evaluateCompatibilityProbe(
    LlamaCppChatRepository repository,
    RuntimeProfile profile, {
    required void Function() checkSafety,
    ModelVerificationPhaseSink? onPhase,
  }) async {
    _reportVerificationPhase(onPhase, ModelVerificationPhase.inferenceCheck);
    checkSafety();
    await repository.prepare();
    checkSafety();
    final messages = [LLMMessage(role: LLMRole.user, content: 'Say hello.')];
    final promptTokens = await repository.countChatTokens(messages);
    checkSafety();
    if (promptTokens <= 0 ||
        promptTokens + profile.reservedOutputTokens > profile.contextSize) {
      throw StateError('compatibilityProbeContextExceeded');
    }
    var completions = 0;
    var hasText = false;
    Future<void> consume() async {
      await for (final chunk in repository.streamChatWithGenerationOptions(
        'compatibility-probe',
        messages: messages,
        generationOptions: GenerationOptions(
          temperature: 0,
          maxTokens: profile.reservedOutputTokens,
        ),
      )) {
        checkSafety();
        if (completions != 0) throw StateError('compatibilityProbeLateEvent');
        hasText |= (chunk.message?.content ?? '').trim().isNotEmpty;
        if (chunk.done == true) completions++;
      }
    }

    final work = consume();
    try {
      await work.timeout(probeDeadline);
    } catch (_) {
      // timeout stops waiting, not decoding. Keep the stream draining until
      // native cancellation acknowledges and the owned operation terminates.
      await repository.cancelActiveInference();
      await work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
      rethrow;
    }
    checkSafety();
    final metrics = repository.lastMetrics;
    if (completions != 1 ||
        !hasText ||
        metrics == null ||
        metrics.generatedTokens <= 0 ||
        metrics.generatedTokens > profile.reservedOutputTokens ||
        !const {
          'endOfGeneration',
          'stopSequence',
          'outputLimit',
        }.contains(metrics.completionReason)) {
      throw StateError('compatibilityProbeIncomplete');
    }
  }

  Future<void> _verifyFile(
    File file, {
    int? expectedSize,
    String? expectedHash,
  }) async {
    if (!await file.exists())
      throw StateError('Installed model file is missing');
    if (expectedSize != null && await file.length() != expectedSize) {
      throw StateError('Installed model file size does not match');
    }
    if (expectedHash != null) {
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString().toLowerCase() != expectedHash.toLowerCase()) {
        throw StateError('Installed model file hash does not match');
      }
    }
  }

  static Future<List<Directory>> _defaultAllowedRoots() async => [
    Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'models'),
    ),
    Directory(p.join((await getApplicationSupportDirectory()).path, 'models')),
  ];
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
