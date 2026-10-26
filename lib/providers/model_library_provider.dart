import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';

import '../models/bundled_model_manifest.dart';
import '../models/hub_model.dart';
import '../models/model_descriptor.dart';
import '../models/model_download_job.dart';
import '../services/model_download_manager.dart';
import '../services/model_hub_client.dart';
import '../services/model_registry_service.dart';
import '../services/model_update_service.dart';
import '../services/persistent_hub_search_cache.dart';
import '../services/platform_model_folder_opener.dart';
import '../services/device_fit_estimator.dart';
import '../services/runtime_capabilities_provider.dart';
import '../services/remote_gguf_inspector.dart';
import '../services/model_recovery_controller.dart';
import '../services/selected_model_readiness.dart';
import '../models/model_verification_phase.dart';
import '../utils/app_logger.dart';

enum ModelLibraryStatus { idle, loading, ready, empty, offline, error }

enum ModelLibraryCacheState { available, writeFailed }

class ModelLibraryProvider extends ChangeNotifier {
  ModelLibraryProvider({
    required ModelHubClient hub,
    required ModelRegistryService registry,
    required ModelDownloadManager downloads,
    RuntimeCapabilitiesProvider capabilities =
        const AndroidRuntimeCapabilitiesProvider(),
    ModelFileStore files = const ApplicationModelFileStore(),
    DeviceFitEstimator fitEstimator = const DeviceFitEstimator(),
    PersistentHubSearchCache? searchCache,
    RemoteGgufInspector? remoteInspector,
    ModelUpdateService? updates,
    SelectedModelReadiness? selectedModel,
    PlatformModelFolderOpener folderOpener =
        const ApplicationModelFolderOpener(),
  }) : _hub = hub,
       _registry = registry,
       _downloads = downloads,
       _capabilities = capabilities,
       _files = files,
       _fitEstimator = fitEstimator,
       _searchCache = searchCache ?? DatabaseHubSearchCache(),
       _remoteInspector =
           remoteInspector ??
           BoundedRemoteGgufInspector(reader: DioRemoteRangeReader()),
       _updates =
           updates ?? HubModelUpdateService(hub: hub, downloads: downloads),
       _selectedModel = selectedModel,
       _folderOpener = folderOpener {
    _recovery = ModelRecoveryController(_verifyAndRefresh);
    _recovery.addListener(_publishRecovery);
    _downloads.addJobListener(_onDownloadUpdate);
  }

  late final ModelRecoveryController _recovery;
  bool _disposed = false;
  Future<void>? _initialization;
  int _installedRefreshEpoch = 0;
  ModelLibraryCacheState _cacheState = ModelLibraryCacheState.available;
  ModelLibraryCacheState get cacheState => _cacheState;

  ModelRecoveryState? recoveryState(String id) => _recovery.stateFor(id);
  ModelVerificationPhase? recoveryPhase(String id) => _recovery.phaseFor(id);

  void _publishRecovery() => notifyListeners();

  void _onDownloadUpdate(ModelDownloadJob job) {
    if (_disposed) return;
    _jobs = [job, ..._jobs.where((existing) => existing.id != job.id)];
    notifyListeners();
    if (_disposed) return;
    if (job.state == ModelDownloadJobState.completed) {
      unawaited(_refreshCompletedModels());
    }
  }

  Future<void> _refreshCompletedModels() async {
    if (_disposed) return;
    final epoch = _installedRefreshEpoch + 1;
    try {
      await _refreshInstalledModels();
      if (_disposed || epoch != _installedRefreshEpoch) return;
      notifyListeners();
    } catch (error) {
      if (_disposed || epoch != _installedRefreshEpoch) return;
      AppLogger.instance.warning(
        'Installed model refresh failed (${error.runtimeType})',
      );
      _status = ModelLibraryStatus.error;
      _error =
          'Could not refresh installed models. Reopen Model Library to retry.';
      notifyListeners();
    }
  }

  Future<void> _refreshInstalledModels() async {
    final epoch = ++_installedRefreshEpoch;
    final installed = await _registry.listModels();
    if (!_disposed && epoch == _installedRefreshEpoch) _installed = installed;
  }

  Future<void> _refreshJobs() async {
    final before = {for (final job in _jobs) job.id: job};
    final jobs = await _downloads.restoreJobs();
    if (_disposed) return;
    final changed = {
      for (final job in _jobs)
        if (!identical(before[job.id], job)) job.id: job,
    };
    _jobs = [
      for (final job in jobs) changed.remove(job.id) ?? job,
      ...changed.values,
    ];
  }

  void _requireActive() {
    if (_disposed) throw StateError('Model library is disposed');
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _downloads.removeJobListener(_onDownloadUpdate);
    _searchIdentity++;
    _recovery.removeListener(_publishRecovery);
    _recovery.dispose();
    super.dispose();
  }

  final ModelHubClient _hub;
  final ModelRegistryService _registry;
  final ModelDownloadManager _downloads;
  final RuntimeCapabilitiesProvider _capabilities;
  final ModelFileStore _files;
  final DeviceFitEstimator _fitEstimator;
  final PersistentHubSearchCache _searchCache;
  final RemoteGgufInspector _remoteInspector;
  final ModelUpdateService _updates;
  final SelectedModelReadiness? _selectedModel;
  final PlatformModelFolderOpener _folderOpener;

  bool _importing = false;
  bool get isImporting => _importing;

  ModelLibraryStatus _status = ModelLibraryStatus.idle;
  List<HubModelSummary> _results = const [];
  List<ModelDescriptor> _installed = const [];
  List<ModelDownloadJob> _jobs = const [];
  Uri? _nextPage;
  String? _error;
  int _searchIdentity = 0;
  String _activeQuery = '';
  String? _activePublisher;
  HubSort _activeSort = HubSort.downloads;

  ModelLibraryStatus get status => _status;
  List<HubModelSummary> get results => List.unmodifiable(_results);
  List<ModelDescriptor> get installed => List.unmodifiable(_installed);
  List<ModelDownloadJob> get jobs => List.unmodifiable(_jobs);
  String? get error => _error;
  bool get canLoadMore => _nextPage != null;
  bool get canOpenModelFolder => _folderOpener.isAvailable;

  HubModelSummary get bundledRecommendation => const HubModelSummary(
    id: BundledModelManifest.repository,
    revision: BundledModelManifest.revision,
    author: BundledModelManifest.publisher,
    license: null,
    parameterCount: BundledModelManifest.parameterCount,
    downloads: 0,
    gated: false,
    tags: const ['gguf', 'recommended'],
  );

  GgufVariant get bundledVariant => const GgufVariant(
    repository: BundledModelManifest.repository,
    revision: BundledModelManifest.revision,
    displayName: BundledModelManifest.displayName,
    quantization: BundledModelManifest.quantization,
    files: const [
      GgufFile(
        name: BundledModelManifest.fileName,
        sizeBytes: BundledModelManifest.byteSize,
        sha256: BundledModelManifest.sha256,
      ),
    ],
  );

  Future<void> initialize() async {
    _requireActive();
    final pending = _initialization;
    if (pending != null) return pending;
    final completion = Completer<void>();
    _initialization = completion.future;
    unawaited(
      Future<void>.sync(_initialize).then<void>(
        (_) {
          _initialization = null;
          completion.complete();
        },
        onError: (Object error, StackTrace stack) {
          _initialization = null;
          completion.completeError(error, stack);
        },
      ),
    );
    return completion.future;
  }

  Future<void> _initialize() async {
    final epoch = ++_installedRefreshEpoch;
    final installed = await _registry.listModels();
    if (_disposed) return;
    await _refreshJobs();
    if (_disposed) return;
    if (epoch == _installedRefreshEpoch) _installed = installed;
    _status = ModelLibraryStatus.ready;
    notifyListeners();
  }

  Future<void> search(
    String query, {
    HubSort sort = HubSort.downloads,
    String? publisher,
  }) async {
    if (_disposed) throw StateError('Model library is disposed');
    final normalized = query.trim();
    final normalizedPublisher = publisher?.trim();
    final cacheKey = _cacheKey(
      query: normalized,
      sort: sort,
      publisher: normalizedPublisher,
    );
    final identity = ++_searchIdentity;
    _activeQuery = normalized;
    _activePublisher = normalizedPublisher;
    _activeSort = sort;
    _status = ModelLibraryStatus.loading;
    _error = null;
    notifyListeners();
    final cached = await _safeReadCache(cacheKey);
    if (identity != _searchIdentity) return;
    if (cached?.isFresh == true) {
      _applyPage(cached!.page);
      notifyListeners();
      return;
    }
    try {
      final page = await _hub.search(
        query: normalized,
        sort: sort,
        publisher: normalizedPublisher,
      );
      if (identity != _searchIdentity) return;
      await _writeCache(cacheKey, page, identity);
      if (identity != _searchIdentity) return;
      _applyPage(page);
    } catch (exception) {
      if (identity != _searchIdentity) return;
      if (cached != null) {
        _results = cached.page.models;
        _nextPage = cached.page.nextUrl;
        _status = ModelLibraryStatus.offline;
      } else {
        _results = const [];
        _nextPage = null;
        _error = 'Hugging Face is unavailable. Installed models still work.';
        _status = ModelLibraryStatus.error;
      }
    }
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (_disposed) throw StateError('Model library is disposed');
    final identity = _searchIdentity;
    final page = _nextPage;
    if (page == null || _status == ModelLibraryStatus.loading) return;
    _status = ModelLibraryStatus.loading;
    notifyListeners();
    final cacheKey = _cacheKey(
      query: _activeQuery,
      sort: _activeSort,
      publisher: _activePublisher,
      cursor: page,
    );
    final cached = await _safeReadCache(cacheKey);
    if (identity != _searchIdentity) return;
    if (cached?.isFresh == true) {
      _appendPage(cached!.page);
      notifyListeners();
      return;
    }
    try {
      final next = await _hub.search(page: page);
      if (identity != _searchIdentity) return;
      await _writeCache(cacheKey, next, identity);
      if (identity != _searchIdentity) return;
      _appendPage(next);
    } catch (_) {
      if (identity != _searchIdentity) return;
      if (cached != null) {
        _results = [..._results, ...cached.page.models];
        _nextPage = cached.page.nextUrl;
      }
      _status = ModelLibraryStatus.offline;
    }
    notifyListeners();
  }

  void _applyPage(HubSearchPage page) {
    _results = page.models;
    _nextPage = page.nextUrl;
    _status = _results.isEmpty
        ? ModelLibraryStatus.empty
        : ModelLibraryStatus.ready;
  }

  void _appendPage(HubSearchPage page) {
    final known = _results.map((model) => model.id).toSet();
    _results = [
      ..._results,
      ...page.models.where((model) => known.add(model.id)),
    ];
    _nextPage = page.nextUrl;
    _status = ModelLibraryStatus.ready;
  }

  Future<HubSearchCacheEntry?> _safeReadCache(String key) async {
    try {
      return await _searchCache.read(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String key, HubSearchPage page, int identity) async {
    try {
      await _searchCache.write(key, page);
      if (!_disposed && identity == _searchIdentity) {
        _cacheState = ModelLibraryCacheState.available;
      }
    } catch (_) {
      // Cache persistence is optional; preserve the authoritative Hub response.
      if (!_disposed && identity == _searchIdentity) {
        _cacheState = ModelLibraryCacheState.writeFailed;
      }
    }
  }

  String _cacheKey({
    required String query,
    required HubSort sort,
    required String? publisher,
    Uri? cursor,
  }) => [
    'q=${Uri.encodeQueryComponent(query.toLowerCase())}',
    'sort=${sort.name}',
    'publisher=${Uri.encodeQueryComponent((publisher ?? '').toLowerCase())}',
    'cursor=${Uri.encodeQueryComponent(cursor?.toString() ?? '')}',
  ].join('&');

  Future<List<GgufVariant>> variants(HubModelSummary model) {
    _requireActive();
    return _hub.resolveGgufArtifacts(
      repository: model.id,
      revision: model.revision,
    );
  }

  Future<DeviceFitAssessment> assessFit(
    HubModelSummary model,
    GgufVariant variant,
  ) async {
    _requireActive();
    final capabilities = await _capabilities.snapshot();
    return _fitEstimator.assess(
      model: model,
      variant: variant,
      availableMemoryBytes: capabilities.availableMemoryBytes,
      usableStorageBytes: await _files.usableBytes(),
    );
  }

  Future<RemoteGgufMetadata> inspectRemote(GgufVariant variant) async {
    _requireActive();
    if (variant.files.isEmpty) return RemoteGgufMetadata.unknown;
    final source = Uri(
      scheme: 'https',
      host: 'huggingface.co',
      pathSegments: [
        ...variant.repository.split('/'),
        'resolve',
        variant.revision,
        ...variant.files.first.name.split('/'),
      ],
      queryParameters: const {'download': 'true'},
    );
    try {
      return await _remoteInspector.inspect(source);
    } catch (_) {
      return RemoteGgufMetadata.unknown;
    }
  }

  Future<ModelDownloadJob> download(
    HubModelSummary model,
    GgufVariant variant,
  ) async {
    _requireActive();
    var job = await _downloads.enqueue(model: model, variant: variant);
    _requireActive();
    _jobs = [job, ..._jobs.where((existing) => existing.id != job.id)];
    notifyListeners();
    job = await _downloads.run(job);
    if (_disposed) return job;
    await _refreshInstalledModels();
    if (_disposed) return job;
    _jobs = [job, ..._jobs.where((existing) => existing.id != job.id)];
    notifyListeners();
    return job;
  }

  void pause(String jobId) {
    _requireActive();
    _downloads.pause(jobId);
  }

  Future<void> cancel(String jobId) async {
    _requireActive();
    await _downloads.cancel(jobId);
    if (_disposed) return;
    await _refreshJobs();
    if (_disposed) return;
    await _refreshInstalledModels();
    if (_disposed) return;
    notifyListeners();
  }

  Future<ModelDownloadJob> resume(ModelDownloadJob original) async {
    _requireActive();
    var job = await _downloads.run(original);
    if (_disposed) return job;
    await _refreshInstalledModels();
    if (_disposed) return job;
    _jobs = [job, ..._jobs.where((existing) => existing.id != job.id)];
    notifyListeners();
    return job;
  }

  Future<ModelDescriptor?> importLocal() async {
    _requireActive();
    if (_importing) throw InferenceRuntimeBusy();
    _importing = true;
    notifyListeners();
    try {
      final model = await _registry.importGguf();
      if (_disposed) return model;
      await _refreshInstalledModels();
      return model;
    } finally {
      _importing = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> openModelFolder() {
    _requireActive();
    return _folderOpener.open();
  }

  Future<ModelDescriptor> verify(ModelDescriptor model) =>
      _recovery.recover(model.id);

  Future<ModelDescriptor?> restoreMissingFile(ModelDescriptor model) async {
    _requireActive();
    try {
      return await _recovery.recoverUsing(model.id, () async {
        final restored = await _registry.restoreMissingFile(
          model.id,
          onPhase: _recovery.phaseReporter(model.id),
        );
        if (restored == null) throw ModelSelectionCancelled();
        if (restored.id != model.id)
          throw StateError('Recovery model identity mismatch');
        if (_disposed) return restored;
        await _refreshInstalledModels();
        if (_disposed) return restored;
        if (_selectedModel?.modelId == model.id) {
          await _selectedModel!.select(model.id, refresh: true);
        }
        return restored;
      });
    } on ModelSelectionCancelled {
      return null;
    }
  }

  Future<ModelDescriptor> _verifyAndRefresh(String id) async {
    final verified = await _registry.verifyInstallation(
      id,
      onPhase: _recovery.phaseReporter(id),
    );
    if (verified.id != id) throw StateError('Recovery model identity mismatch');
    if (_disposed) return verified;
    await _refreshInstalledModels();
    if (_disposed) return verified;
    if (_selectedModel?.modelId == id) {
      await _selectedModel!.select(id, refresh: true);
    }
    return verified;
  }

  Future<ModelUpdateAvailability> checkUpdate(ModelDescriptor model) async {
    _requireActive();
    final result = await _updates.check(model);
    if (_disposed) return result;
    await _refreshInstalledModels();
    if (_disposed) return result;
    notifyListeners();
    return result;
  }

  Future<ModelDownloadJob> downloadUpdate(ModelDescriptor model) async {
    _requireActive();
    final job = await _updates.apply(model);
    if (_disposed) return job;
    await _refreshInstalledModels();
    if (_disposed) return job;
    _jobs = [job, ..._jobs.where((existing) => existing.id != job.id)];
    notifyListeners();
    return job;
  }

  Future<void> uninstall(ModelDescriptor model) async {
    _requireActive();
    void invalidateRemovedSelection() {
      if (_selectedModel?.modelId == model.id) _selectedModel!.invalidate();
    }

    try {
      await _registry.uninstall(model.id);
    } on ModelStorageBusy {
      rethrow;
    } on InferenceRuntimeBusy {
      rethrow;
    } on InferenceRecoveryRequired {
      rethrow;
    } catch (_) {
      // File deletion may precede failed registry projection. Reassess before
      // allowing inference; neither substitute a model nor alter chat settings.
      invalidateRemovedSelection();
      rethrow;
    }
    invalidateRemovedSelection();
    if (_disposed) return;
    await _refreshInstalledModels();
    if (_disposed) return;
    notifyListeners();
  }

  Future<ModelDownloadJob> repair(ModelDescriptor model) async {
    _requireActive();
    final repository = model.repository;
    final revision = model.revision;
    if (model.source != 'huggingface' ||
        repository == null ||
        revision == null) {
      throw StateError('This model must be imported again from its local file');
    }
    final variants = await _hub.resolveGgufArtifacts(
      repository: repository,
      revision: revision,
    );
    final matching = variants.where(
      (variant) =>
          variant.displayName == model.displayName ||
          (model.quantization != null &&
              variant.quantization == model.quantization),
    );
    if (matching.isEmpty) {
      throw StateError('The installed model variant is no longer available');
    }
    return download(
      HubModelSummary(
        id: repository,
        revision: revision,
        author: repository.split('/').first,
        license: model.license,
        parameterCount: model.parameterCount,
        downloads: 0,
        gated: false,
        tags: const ['gguf'],
      ),
      matching.first,
    );
  }
}
