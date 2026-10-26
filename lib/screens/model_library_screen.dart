import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/hub_model.dart';
import '../models/model_descriptor.dart';
import '../models/model_download_job.dart';
import '../models/model_storage_error.dart';
import '../providers/chat_provider.dart';
import '../providers/model_library_provider.dart';
import '../services/remote_gguf_inspector.dart';
import '../services/notification_permission_service.dart';
import '../services/model_recovery_controller.dart';
import '../widgets/model_recovery_status_label.dart';

class ModelLibraryScreen extends StatefulWidget {
  const ModelLibraryScreen({super.key});

  @override
  State<ModelLibraryScreen> createState() => _ModelLibraryScreenState();
}

class _ModelLibraryScreenState extends State<ModelLibraryScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  String _publisher = '';
  Timer? _debounce;
  HubSort _sort = HubSort.downloads;
  _ModelSizeFilter _sizeFilter = _ModelSizeFilter.any;
  late final TabController _tabs;
  int _lastTab = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)..addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initializeLibrary());
    });
  }

  void _onTabChanged() {
    if (_tabs.index == _lastTab) return;
    setState(() => _lastTab = _tabs.index);
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _initializeLibrary() async {
    if (!mounted) return;
    try {
      await context.read<ModelLibraryProvider>().initialize();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not load Model Library. Try again.'),
          action: SnackBarAction(label: 'Retry', onPressed: _initializeLibrary),
        ),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Model Library'),
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(
          MediaQuery.textScalerOf(context)
              .scale(kMinInteractiveDimension)
              .clamp(kToolbarHeight, double.infinity),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final style = Theme.of(context).textTheme.titleSmall!;
            const labels = ['Browse', 'Installed', 'Downloads'];
            final fits = labels.every((label) {
              final painter = TextPainter(
                text: TextSpan(text: label, style: style),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final fits =
                  painter.width + 32 <= constraints.maxWidth / labels.length;
              painter.dispose();
              return fits;
            });
            if (!fits) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: _tabs.index,
                  itemHeight: null,
                  hint: const Text('Model Library section'),
                  items: [
                    for (var index = 0; index < labels.length; index++)
                      DropdownMenuItem(
                        value: index,
                        child: Text(labels[index]),
                      ),
                  ],
                  onChanged: (index) {
                    if (index != null) _tabs.animateTo(index);
                  },
                ),
              );
            }
            return TabBar(
              controller: _tabs,
              tabs: [for (final label in labels) Tab(text: label)],
            );
          },
        ),
      ),
    ),
    body: Consumer<ModelLibraryProvider>(
      builder: (context, library, _) => TabBarView(
        controller: _tabs,
        children: [_search(library), _installed(library), _downloads(library)],
      ),
    ),
  );

  Widget _search(ModelLibraryProvider library) => CustomScrollView(
    slivers: [
      SliverToBoxAdapter(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Semantics(
                label: 'Search Hugging Face models',
                textField: true,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search by model or publisher',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: 'Search',
                      onPressed: () =>
                          _submitSearch(library, _searchController.text),
                      icon: const Icon(Icons.arrow_forward),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (value) => _submitSearch(library, value),
                  onChanged: (value) {
                    _debounce?.cancel();
                    _debounce = Timer(
                      const Duration(milliseconds: 450),
                      () => _runSearch(library, value),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Tooltip(
                  message: 'Search filters',
                  child: TextButton.icon(
                    onPressed: () => _showFilters(library),
                    icon: const Icon(Icons.tune),
                    label: const Text('Filters'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                  ),
                ),
              ),
            ),
            if (library.status == ModelLibraryStatus.offline)
              const ListTile(
                leading: Icon(Icons.cloud_off),
                title: Text('Showing cached results'),
              ),
            if (library.status == ModelLibraryStatus.error)
              ListTile(
                leading: const Icon(Icons.cloud_off),
                title: Text(library.error ?? 'Search unavailable'),
              ),
            if (library.status == ModelLibraryStatus.loading)
              const LinearProgressIndicator(),
          ],
        ),
      ),
      if (library.status == ModelLibraryStatus.idle && library.results.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recommended',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Download a model, then chat offline on your device.',
                ),
                _remoteCard(
                  library,
                  library.bundledRecommendation,
                  fixedVariant: library.bundledVariant,
                ),
              ],
            ),
          ),
        ),
      if (_filteredResults(library).isEmpty &&
          library.status != ModelLibraryStatus.idle)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: Text('Search public GGUF models')),
        )
      else
        SliverList.builder(
          itemCount:
              _filteredResults(library).length + (library.canLoadMore ? 1 : 0),
          itemBuilder: (context, index) {
            final visible = _filteredResults(library);
            if (index == visible.length) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: OutlinedButton(
                  onPressed: library.loadMore,
                  child: const Text('Load more'),
                ),
              );
            }
            return _remoteCard(library, visible[index]);
          },
        ),
    ],
  );

  List<HubModelSummary> _filteredResults(ModelLibraryProvider library) =>
      library.results
          .where((model) {
            final parameters = model.parameterCount;
            return switch (_sizeFilter) {
              _ModelSizeFilter.any => true,
              _ModelSizeFilter.upTo4B =>
                parameters != null && !model.isLargeModel,
              _ModelSizeFilter.over4B => model.isLargeModel,
              _ModelSizeFilter.unknown => parameters == null,
            };
          })
          .toList(growable: false);

  Future<void> _showFilters(ModelLibraryProvider library) async {
    _debounce?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    final selection =
        await showModalBottomSheet<
          ({String publisher, HubSort sort, _ModelSizeFilter size})
        >(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _SearchFiltersSheet(
            publisher: _publisher,
            sort: _sort,
            size: _sizeFilter,
          ),
        );
    if (!mounted || selection == null) return;
    setState(() {
      _publisher = selection.publisher;
      _sort = selection.sort;
      _sizeFilter = selection.size;
    });
    await _submitSearch(library, _searchController.text);
  }

  Future<void> _runSearch(ModelLibraryProvider library, String query) =>
      library.search(query, sort: _sort, publisher: _publisher);

  Future<void> _submitSearch(ModelLibraryProvider library, String query) {
    FocusManager.instance.primaryFocus?.unfocus();
    return _runSearch(library, query);
  }

  Widget _remoteCard(
    ModelLibraryProvider library,
    HubModelSummary model, {
    GgufVariant? fixedVariant,
  }) => Card(
    child: ListTile(
      isThreeLine: true,
      leading: const Icon(Icons.memory),
      title: Text(model.id),
      subtitle: Text(
        [
          if (model.parameterCount != null) _parameters(model.parameterCount!),
          if (model.license != null) model.license!,
          if (model.isLargeModel) '⚠ Large model',
        ].join(' • '),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openRemote(library, model, fixedVariant),
    ),
  );

  Widget _installed(ModelLibraryProvider library) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      FilledButton.tonalIcon(
        onPressed: () => _importLocal(library),
        icon: const Icon(Icons.file_open),
        label: const Text('Import Local GGUF'),
      ),
      if (library.canOpenModelFolder) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _openModelFolder(library),
          icon: const Icon(Icons.folder_open),
          label: const Text('Open Model Folder'),
        ),
      ],
      const SizedBox(height: 12),
      if (library.installed.where((model) => model.isInstalled).isEmpty)
        const ListTile(title: Text('No installed models yet')),
      for (final model in library.installed) _installedTile(library, model),
    ],
  );

  Widget _installedTile(
    ModelLibraryProvider library,
    ModelDescriptor model,
  ) => ListTile(
    leading: Icon(model.isInstalled ? Icons.check_circle : Icons.error_outline),
    title: Text(model.displayName),
    subtitle: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          model.isInstalled
              ? [
                  model.quantization,
                  _optionalParameters(model.parameterCount),
                ].whereType<String>().join(' • ')
              : 'Model unavailable — this chat will not be changed automatically.',
        ),
        ModelRecoveryStatusLabel(
          state: library.recoveryState(model.id),
          phase: library.recoveryPhase(model.id),
        ),
      ],
    ),
    trailing:
        model.isInstalled ||
            model.source == 'huggingface' ||
            model.localPath != null
        ? PopupMenuButton<_InstalledModelAction>(
            enabled:
                library.recoveryState(model.id) != ModelRecoveryState.verifying,
            tooltip: 'Model actions',
            onSelected: (action) =>
                _handleInstalledAction(library, model, action),
            itemBuilder: (_) => [
              if (model.localPath != null)
                const PopupMenuItem(
                  value: _InstalledModelAction.verify,
                  child: Text('Verify and recover'),
                ),
              if (model.localPath != null && model.sha256 != null)
                const PopupMenuItem(
                  value: _InstalledModelAction.restore,
                  child: Text('Find missing model file'),
                ),
              if (model.isInstalled) ...[
                PopupMenuItem(
                  value: _InstalledModelAction.use,
                  child: Text(
                    context.read<ChatProvider?>()?.currentChat == null
                        ? 'Start chat with this model'
                        : 'Use for this chat',
                  ),
                ),
                if (model.source == 'huggingface')
                  const PopupMenuItem(
                    value: _InstalledModelAction.update,
                    child: Text('Check for updates'),
                  ),
                const PopupMenuItem(
                  value: _InstalledModelAction.uninstall,
                  child: Text('Uninstall'),
                ),
              ] else if (model.source == 'huggingface')
                const PopupMenuItem(
                  value: _InstalledModelAction.repair,
                  child: Text('Download again'),
                ),
            ],
          )
        : null,
  );

  Widget _downloads(ModelLibraryProvider library) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      if (library.jobs.isEmpty) const ListTile(title: Text('No downloads yet')),
      for (final job in library.jobs)
        ListTile(
          leading: _downloadIcon(job.state),
          title: Text(job.repository),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(job.state.name),
              if (job.progress != null)
                LinearProgressIndicator(value: job.progress),
            ],
          ),
          trailing: _downloadActions(library, job),
        ),
    ],
  );

  Widget? _downloadActions(ModelLibraryProvider library, ModelDownloadJob job) {
    final canStop = switch (job.state) {
      ModelDownloadJobState.queued ||
      ModelDownloadJobState.downloading ||
      ModelDownloadJobState.paused ||
      ModelDownloadJobState.validating ||
      ModelDownloadJobState.failed => true,
      _ => false,
    };
    final primary = switch (job.state) {
      ModelDownloadJobState.downloading => IconButton(
        tooltip: 'Pause download',
        onPressed: () => library.pause(job.id),
        icon: const Icon(Icons.pause),
      ),
      ModelDownloadJobState.paused ||
      ModelDownloadJobState.failed => IconButton(
        tooltip: job.state == ModelDownloadJobState.paused
            ? 'Resume download'
            : 'Retry download',
        onPressed: () => library.resume(job),
        icon: Icon(
          job.state == ModelDownloadJobState.paused
              ? Icons.play_arrow
              : Icons.refresh,
        ),
      ),
      _ => null,
    };
    if (!canStop && primary == null) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (primary != null) primary,
        if (canStop)
          IconButton(
            tooltip: 'Cancel download',
            onPressed: () => _confirmCancelDownload(library, job),
            icon: const Icon(Icons.close),
          ),
      ],
    );
  }

  Future<void> _confirmCancelDownload(
    ModelLibraryProvider library,
    ModelDownloadJob job,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this download?'),
        content: const Text(
          'Only this download job’s partial files will be removed. '
          'Installed models and chats are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep download'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel download'),
          ),
        ],
      ),
    );
    if (confirmed == true) await library.cancel(job.id);
  }

  Future<void> _openRemote(
    ModelLibraryProvider library,
    HubModelSummary model,
    GgufVariant? fixedVariant,
  ) async {
    var loadingShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final variants = fixedVariant == null
          ? await library.variants(model)
          : [fixedVariant];
      if (!mounted) return;
      Navigator.pop(context);
      loadingShown = false;
      if (variants.isEmpty) throw StateError('No complete GGUF files found');
      final chosen = await showModalBottomSheet<GgufVariant>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => ListView(
          children: [
            ListTile(
              title: Text(model.id),
              subtitle: Text('${model.revision.substring(0, 8)} • Public GGUF'),
            ),
            for (final variant in variants)
              ListTile(
                title: Text(variant.displayName),
                subtitle: Text(
                  [
                    variant.quantization ?? 'Unknown quantization',
                    _bytes(variant.totalBytes),
                    if (variant.isSplit) '${variant.files.length} files',
                  ].join(' • '),
                ),
                trailing: const Icon(Icons.download),
                onTap: () => Navigator.pop(sheetContext, variant),
              ),
          ],
        ),
      );
      if (chosen == null || !mounted) return;
      final details = await Future.wait<Object>([
        library.assessFit(model, chosen),
        library.inspectRemote(chosen),
      ]);
      final fit = details[0] as DeviceFitAssessment;
      final metadata = details[1] as RemoteGgufMetadata;
      if (!mounted) return;
      final accepted = await _confirmDownload(model, chosen, fit, metadata);
      if (!accepted || !mounted) return;
      final notificationPermission = await NotificationPermissionService()
          .ensureForDownload();
      if (!mounted) return;
      if (notificationPermission == NotificationPermissionStatus.denied ||
          notificationPermission == NotificationPermissionStatus.unavailable) {
        await _showNotificationRequirement(notificationPermission);
        return;
      }
      final pending = library.download(model, chosen);
      _tabs.animateTo(2);
      final job = await pending;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Download ${job.state.name}')));
    } catch (error) {
      if (!mounted) return;
      if (loadingShown) Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Model unavailable: $error')));
    }
  }

  Future<void> _showNotificationRequirement(
    NotificationPermissionStatus status,
  ) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Notifications are needed for model downloads'),
      content: Text(
        status == NotificationPermissionStatus.denied
            ? 'Vitalis needs notification permission to show and control a durable Android download. No download was started.'
            : 'Vitalis could not verify notification support for a durable Android download. No download was started.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  Future<bool> _confirmDownload(
    HubModelSummary model,
    GgufVariant variant,
    DeviceFitAssessment fit,
    RemoteGgufMetadata metadata,
  ) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            model.isLargeModel || fit.level == DeviceFitLevel.memoryRisk
                ? '⚠ Check device fit'
                : 'Download model?',
          ),
          content: Text(
            '${variant.displayName}\n${_bytes(variant.totalBytes)}\n\n'
            'Publisher: ${model.author ?? model.id.split('/').first}\n'
            'License: ${model.license ?? 'Unknown'}\n'
            'Parameters: ${_optionalParameters(model.parameterCount) ?? 'Unknown'}\n'
            'Quantization: ${variant.quantization ?? 'Unknown'}\n'
            'Architecture: ${metadata.architecture ?? 'Unknown'}\n'
            'Tokenizer: ${metadata.tokenizer ?? 'Unknown'}\n'
            'Chat template: ${metadata.chatTemplate == null ? 'Unknown' : 'Detected'}\n'
            'Training context: ${metadata.trainingContext?.toString() ?? 'Unknown'}\n'
            'Files: ${variant.files.length}\n'
            'Revision: ${model.revision}\n'
            'Hash authority: ${variant.files.every((file) => file.sha256 != null) ? 'Publisher LFS SHA-256' : 'Revision/ETag plus local SHA-256'}\n\n'
            '${model.isLargeModel ? 'This model has more than 4 billion parameters and may be very slow or run out of memory on this device.\n\n' : ''}'
            '${fit.reason}\n'
            '${fit.estimatedMemoryBytes == null ? '' : 'Estimated working memory: ${_bytes(fit.estimatedMemoryBytes)}\n'}\n'
            'The download is public, pinned to revision ${model.revision.substring(0, 8)}, and runs locally after installation.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  fit.level == DeviceFitLevel.insufficientDisk ||
                      fit.level == DeviceFitLevel.incompatible
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Download'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _useModel(ModelDescriptor model) async {
    try {
      await context.read<ChatProvider>().switchModel(model.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${model.displayName} is ready for this chat'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Model switch failed: $error')));
      }
    }
  }

  Future<void> _handleInstalledAction(
    ModelLibraryProvider library,
    ModelDescriptor model,
    _InstalledModelAction action,
  ) async {
    if (action == _InstalledModelAction.restore) {
      try {
        final restored = await library.restoreMissingFile(model);
        if (mounted && restored != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Model restored. Use for this chat is a separate action.',
              ),
            ),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                error is ModelIdentityMismatch
                    ? 'This is a different model. Use Import Local GGUF to add it separately.'
                    : ModelRecoveryStatusLabel.message(
                        library.recoveryState(model.id),
                        library.recoveryPhase(model.id),
                      ),
              ),
            ),
          );
        }
      }
      return;
    }
    if (action == _InstalledModelAction.repair) {
      try {
        final pending = library.repair(model);
        _tabs.animateTo(2);
        final job = await pending;
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Repair ${job.state.name}')));
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Repair failed: $error')));
        }
      }
      return;
    }
    if (action == _InstalledModelAction.use) {
      await _useModel(model);
      return;
    }
    if (action == _InstalledModelAction.verify) {
      try {
        await library.verify(model);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${model.displayName} verified')),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ModelRecoveryStatusLabel.message(
                  library.recoveryState(model.id),
                  library.recoveryPhase(model.id),
                ),
              ),
            ),
          );
        }
      }
      return;
    }
    if (action == _InstalledModelAction.update) {
      try {
        final update = await library.checkUpdate(model);
        if (!mounted) return;
        if (!update.available || update.latest == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${model.displayName} is up to date')),
          );
          return;
        }
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Download model update?'),
            content: Text(
              'The update is pinned to revision ${update.latest!.revision}. '
              'Your installed revision stays unchanged until the new files '
              'are fully downloaded and validated.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Download update'),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          final job = await library.downloadUpdate(model);
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Update ${job.state.name}')));
          }
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Update check failed: $error')),
          );
        }
      }
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Uninstall ${model.displayName}?'),
        content: const Text(
          'Only this model\'s files and tuning profile will be removed. '
          'Chats and messages are preserved and will show the model as unavailable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Uninstall'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<ChatProvider>().prepareModelRemoval(model.id);
      await library.uninstall(model);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${model.displayName} uninstalled')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Uninstall failed: $error')));
      }
    }
  }

  Future<void> _importLocal(ModelLibraryProvider library) async {
    try {
      final model = await library.importLocal();
      if (model != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${model.displayName} imported')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $error')));
      }
    }
  }

  Future<void> _openModelFolder(ModelLibraryProvider library) async {
    try {
      await library.openModelFolder();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open model folder: $error')),
        );
      }
    }
  }

  String _parameters(int count) => count >= 1000000000
      ? '${(count / 1000000000).toStringAsFixed(1)}B parameters'
      : '${(count / 1000000).toStringAsFixed(0)}M parameters';
  String? _optionalParameters(int? count) =>
      count == null ? null : _parameters(count);
  String _bytes(int? bytes) => bytes == null
      ? 'Size unknown'
      : '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  Icon _downloadIcon(ModelDownloadJobState state) => switch (state) {
    ModelDownloadJobState.completed => const Icon(Icons.check_circle),
    ModelDownloadJobState.failed => const Icon(Icons.error),
    ModelDownloadJobState.paused => const Icon(Icons.pause_circle),
    ModelDownloadJobState.cancelled => const Icon(Icons.cancel),
    _ => const Icon(Icons.download),
  };
}

enum _ModelSizeFilter { any, upTo4B, over4B, unknown }

enum _InstalledModelAction { use, verify, restore, update, repair, uninstall }

class _SearchFiltersSheet extends StatefulWidget {
  const _SearchFiltersSheet({
    required this.publisher,
    required this.sort,
    required this.size,
  });
  final String publisher;
  final HubSort sort;
  final _ModelSizeFilter size;
  @override
  State<_SearchFiltersSheet> createState() => _SearchFiltersSheetState();
}

class _SearchFiltersSheetState extends State<_SearchFiltersSheet> {
  late final _publisher = TextEditingController(text: widget.publisher);
  late HubSort _sort = widget.sort;
  late _ModelSizeFilter _size = widget.size;
  @override
  void dispose() {
    _publisher.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      16,
      16,
      16,
      16 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Search filters', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _publisher,
          decoration: const InputDecoration(
            labelText: 'Publisher filter (optional)',
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<HubSort>(
          initialValue: _sort,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Sort'),
          items: const [
            DropdownMenuItem(
              value: HubSort.relevance,
              child: Text('Relevance'),
            ),
            DropdownMenuItem(
              value: HubSort.downloads,
              child: Text('Popularity'),
            ),
            DropdownMenuItem(
              value: HubSort.recentlyUpdated,
              child: Text('Recently updated'),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _sort = value);
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<_ModelSizeFilter>(
          initialValue: _size,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Model size'),
          items: const [
            DropdownMenuItem(
              value: _ModelSizeFilter.any,
              child: Text('Any size'),
            ),
            DropdownMenuItem(
              value: _ModelSizeFilter.upTo4B,
              child: Text('Up to 4B'),
            ),
            DropdownMenuItem(
              value: _ModelSizeFilter.over4B,
              child: Text('Over 4B'),
            ),
            DropdownMenuItem(
              value: _ModelSizeFilter.unknown,
              child: Text('Unknown size'),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _size = value);
          },
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            publisher: _publisher.text.trim(),
            sort: _sort,
            size: _size,
          )),
          child: const Text('Apply filters'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}
