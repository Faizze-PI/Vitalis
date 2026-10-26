import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart' show InferenceRuntimeBusy;
import '../constants/app_constants.dart';
import '../constants/app_colors.dart';
import '../constants/app_metrics.dart';
import '../constants/app_strings.dart';
import '../providers/chat_provider.dart';
import '../providers/theme_provider.dart';
import '../services/model_download_service.dart';
import '../services/model_registry_service.dart';
import '../services/model_warmup_service.dart';
import '../services/runtime_capabilities_provider.dart';
import '../models/model_settings.dart';
import '../models/model_descriptor.dart';
import '../models/bundled_model_manifest.dart';
import '../services/selected_model_readiness.dart';
import '../utils/app_logger.dart';
import '../utils/debug_state.dart';
import '../app_router.dart';
import '../widgets/startup_mutation_access.dart';
import '../widgets/system_prompt_editor_dialog.dart';
import '../services/startup_access_guard.dart';

part 'settings_mutation_actions.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.logger});
  final AppLogger? logger;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<String> _appVersionFuture;
  late Future<bool> _vulkanAvailableFuture;
  bool _privacyMode = true;
  bool _importing = false;
  bool _resettingAuto = false;
  bool _themeChanging = false;
  bool _privacyChanging = false;
  bool _resettingBundledDownload = false;
  bool _clearingLogs = false;
  late final ModelRegistryService _modelRegistry;
  late final AppLogger _logger;

  void _setAutoResetPending(bool value) {
    if (mounted) setState(() => _resettingAuto = value);
  }

  Future<void> _toggleTheme(ThemeProvider provider) async {
    if (!mounted || _themeChanging) return;
    try {
      _requirePersistentSettingsAccess();
      setState(() => _themeChanging = true);
      await provider.toggle();
    } catch (error) {
      _reportSettingsActionFailure(error);
    } finally {
      if (mounted) setState(() => _themeChanging = false);
    }
  }

  Future<void> _changePrivacyMode(bool value) async {
    if (!mounted || _privacyChanging) return;
    try {
      _requirePersistentSettingsAccess();
      setState(() => _privacyChanging = true);
      await _logger.setPrivacyMode(value);
      if (value) {
        final cleanup = await _logger.clearLogs();
        if (!cleanup.complete) {
          throw StateError('Log cleanup could not be completed.');
        }
      }
    } catch (error) {
      _reportSettingsActionFailure(error);
    } finally {
      if (mounted) {
        setState(() {
          _privacyMode = _logger.isPrivacyMode;
          _privacyChanging = false;
        });
      }
    }
  }

  void _invalidateBundledReadiness(SelectedModelReadiness? readiness) {
    if (readiness?.modelId == BundledModelManifest.id) readiness!.invalidate();
  }

  Future<void> _resetBundledDownload(ModelDownloadService service) async {
    if (!mounted || _resettingBundledDownload) return;
    var attempted = false;
    SelectedModelReadiness? readiness;
    try {
      _requirePersistentSettingsAccess();
      setState(() => _resettingBundledDownload = true);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text(AppStrings.resetModel),
          content: const Text(
            '${AppStrings.resetModelConfirm}\n\n'
            'Target: ${BundledModelManifest.displayName}. '
            'Other models and saved chats are retained.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(AppStrings.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(AppStrings.confirm),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      _requirePersistentSettingsAccess();
      readiness = context.read<SelectedModelReadiness?>();
      attempted = true;
      await service.resetDownloadState();
      _invalidateBundledReadiness(readiness);
    } catch (error) {
      // Busy rejection proves no file mutation; other attempted failures may
      // require reassessment rather than continuing with cached readiness.
      if (attempted &&
          error is! InferenceRuntimeBusy &&
          error is! ModelStorageBusy) {
        _invalidateBundledReadiness(readiness);
      }
      _reportSettingsActionFailure(error);
    } finally {
      if (mounted) setState(() => _resettingBundledDownload = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _logger = widget.logger ?? AppLogger.instance;
    _modelRegistry = context.read<ModelRegistryService>();
    _appVersionFuture = PackageInfo.fromPlatform()
        .then((info) => 'App Version ${info.version} (${info.buildNumber})')
        .catchError((_) => 'App Version unavailable');
    _privacyMode = _logger.isPrivacyMode;
    _vulkanAvailableFuture = const AndroidRuntimeCapabilitiesProvider()
        .snapshot()
        .then((capabilities) => capabilities.supportsBackend('vulkan'));
  }

  Future<void> _clearLogs() async {
    if (!mounted || _clearingLogs) return;
    try {
      _requirePersistentSettingsAccess();
      setState(() => _clearingLogs = true);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(AppStrings.clearLogs),
          content: const Text(AppStrings.clearLogsConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(AppStrings.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(AppStrings.confirm),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      _requirePersistentSettingsAccess();
      final result = await _logger.clearLogs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.complete
                  ? '${AppStrings.clearLogs} — done'
                  : 'Some logs could not be removed. Please retry.',
            ),
          ),
        );
      }
    } catch (error) {
      _reportSettingsActionFailure(error);
    } finally {
      if (mounted) setState(() => _clearingLogs = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      final chatProvider = context.watch<ChatProvider>();
      final settings = chatProvider.settings;
      final themeProvider = context.watch<ThemeProvider>();
      final ownerId = chatProvider.currentChat?.id;
      void preview(ModelSettings next) =>
          _previewChatSettings(chatProvider, next, ownerId, settings.modelId);
      Future<void> persist(ModelSettings next) =>
          _persistChatSettings(chatProvider, next, ownerId, settings.modelId);

      return StartupMutationAccess(
        builder: (context, canMutate) => Scaffold(
          appBar: AppBar(title: const Text(AppStrings.settingsTitle)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // --- Appearance ---
              Semantics(
                header: true,
                child: const Text(
                  AppStrings.appearance,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: AppStrings.darkMode,
                child: SwitchListTile(
                  title: const Text(AppStrings.darkMode),
                  subtitle: const Text(AppStrings.toggleDark),
                  value: themeProvider.isDark,
                  onChanged: !canMutate || _themeChanging
                      ? null
                      : (_) => _toggleTheme(themeProvider),
                ),
              ),
              const SizedBox(height: 24),

              // --- Privacy ---
              Semantics(
                header: true,
                child: const Text(
                  AppStrings.privacy,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: AppStrings.privacyMode,
                child: SwitchListTile(
                  title: const Text(AppStrings.privacyMode),
                  subtitle: Text(
                    _privacyMode
                        ? 'INFO logs disabled. WARN/ERROR only.'
                        : 'All diagnostic data logged.',
                  ),
                  value: _privacyMode,
                  onChanged: canMutate && !_privacyChanging
                      ? _changePrivacyMode
                      : null,
                ),
              ),
              ExpansionTile(
                title: const Text(AppStrings.whatIsLogged),
                leading: const Icon(Icons.info_outline, size: 20),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      AppStrings.loggedFields,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Semantics(
                label: AppStrings.clearLogs,
                button: true,
                child: ListTile(
                  leading: const Icon(Icons.delete_sweep, size: 20),
                  title: const Text(AppStrings.clearLogs),
                  onTap: canMutate && !_clearingLogs ? _clearLogs : null,
                ),
              ),
              Semantics(
                label: AppStrings.privacyPolicy,
                button: true,
                child: ListTile(
                  leading: const Icon(Icons.privacy_tip, size: 20),
                  title: const Text(AppStrings.privacyPolicy),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text(AppStrings.privacyPolicy),
                        content: const SingleChildScrollView(
                          child: Text(
                            'Conversations, notes, personas, and settings stay on your device. '
                            'Inference runs locally. No cloud inference or conversation upload is used.\n\n'
                            'Model Library uses HTTPS to search and download public models from Hugging Face. '
                            'Your search text, requested model identifiers, and normal connection information '
                            '(such as your IP address) are visible to Hugging Face and its download hosts. '
                            'Chats, notes, personas, prompts, and local model paths are not included in these requests.\n\n'
                            'Contact: support@vitalis.app',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text(AppStrings.close),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),

              // --- Model Info ---
              Semantics(
                header: true,
                child: const Text(
                  AppStrings.modelInfo,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.view_in_ar),
                title: const Text('Model Library'),
                subtitle: const Text(
                  'Browse public Hugging Face GGUF models, downloads, and installed models.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.modelLibrary),
              ),
              FutureBuilder<ModelDescriptor?>(
                future: _modelRegistry.findById(settings.modelId),
                builder: (context, snapshot) {
                  final model = snapshot.data;
                  return Column(
                    children: [
                      _infoRow(
                        AppStrings.modelName,
                        model?.displayName ?? 'Model unavailable',
                      ),
                      _infoRow(
                        AppStrings.quantization,
                        model?.quantization ?? AppStrings.unknown,
                      ),
                      _infoRow(
                        AppStrings.parameters,
                        model?.parameterCount == null
                            ? AppStrings.unknown
                            : '${(model!.parameterCount! / 1000000000).toStringAsFixed(1)}B',
                      ),
                      _infoRow(
                        AppStrings.contextWindow,
                        '${model?.contextTrain ?? AppConstants.defaultContextSize} tokens (training maximum)',
                      ),
                      _infoRow(
                        AppStrings.fileSize,
                        model?.byteSize == null
                            ? AppStrings.notDownloaded
                            : '${(model!.byteSize! / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB',
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),

              // --- Model Settings ---
              Semantics(
                header: true,
                child: const Text(
                  AppStrings.modelSettings,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('System prompt'),
                subtitle: Text(
                  settings.systemPrompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: canMutate
                    ? () => _editSystemPrompt(chatProvider, settings)
                    : null,
              ),
              FutureBuilder<ModelDescriptor?>(
                future: _modelRegistry.findById(settings.modelId),
                builder: (context, snapshot) {
                  final supportsThinking =
                      snapshot.data?.supportsThinking == true;
                  return SwitchListTile(
                    title: const Text('Thinking mode'),
                    subtitle: Text(
                      supportsThinking
                          ? 'Off is faster and disables reasoning through the verified model template.'
                          : 'Unavailable until this model template is verified.',
                    ),
                    value:
                        supportsThinking &&
                        settings.thinkingMode == ThinkingMode.on,
                    onChanged: supportsThinking && canMutate
                        ? (enabled) => persist(
                            chatProvider.settings.copyWith(
                              thinkingMode: enabled
                                  ? ThinkingMode.on
                                  : ThinkingMode.off,
                            ),
                          )
                        : null,
                  );
                },
              ),
              DropdownButtonFormField<TuningMode>(
                initialValue: settings.tuningMode,
                decoration: const InputDecoration(labelText: 'Runtime tuning'),
                items: const [
                  DropdownMenuItem(
                    value: TuningMode.automatic,
                    child: Text('Automatic'),
                  ),
                  DropdownMenuItem(
                    value: TuningMode.advanced,
                    child: Text('Advanced'),
                  ),
                ],
                onChanged: !canMutate
                    ? null
                    : (mode) {
                        if (mode != null) {
                          persist(
                            chatProvider.settings.copyWith(tuningMode: mode),
                          );
                        }
                      },
              ),
              if (settings.tuningMode == TuningMode.advanced)
                _buildAdvancedSettings(chatProvider, settings, canMutate),
              _buildSliderSetting(
                enabled: canMutate,
                label: AppStrings.temperatureLabel,
                value: settings.temperature,
                min: 0.0,
                max: 2.0,
                divisions: 20,
                onChanged: (value) =>
                    preview(chatProvider.settings.copyWith(temperature: value)),
                onChangeEnd: (value) =>
                    persist(chatProvider.settings.copyWith(temperature: value)),
              ),
              _buildSliderSetting(
                enabled: canMutate,
                label: AppStrings.topPLabel,
                value: settings.topP,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                onChanged: (value) =>
                    preview(chatProvider.settings.copyWith(topP: value)),
                onChangeEnd: (value) =>
                    persist(chatProvider.settings.copyWith(topP: value)),
              ),
              _buildSliderSetting(
                enabled: canMutate,
                label: AppStrings.topKLabel,
                value: settings.topK.toDouble(),
                min: 1,
                max: 100,
                divisions: 99,
                displayValue: settings.topK.toString(),
                onChanged: (value) => preview(
                  chatProvider.settings.copyWith(topK: value.toInt()),
                ),
                onChangeEnd: (value) => persist(
                  chatProvider.settings.copyWith(topK: value.toInt()),
                ),
              ),
              _buildSliderSetting(
                enabled: canMutate,
                label: AppStrings.maxTokensLabel,
                value: settings.maxTokens.toDouble(),
                min: 64,
                max: 4096,
                divisions: 63,
                displayValue: settings.maxTokens.toString(),
                onChanged: (value) => preview(
                  chatProvider.settings.copyWith(maxTokens: value.toInt()),
                ),
                onChangeEnd: (value) => persist(
                  chatProvider.settings.copyWith(maxTokens: value.toInt()),
                ),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: _importing
                    ? const CircularProgressIndicator()
                    : const Icon(Icons.file_open),
                title: const Text('Import local GGUF model'),
                subtitle: const Text(
                  'Validates and copies the model into private app storage.',
                ),
                onTap: _importing ? null : _importModel,
              ),
              _buildRedownloadButton(canMutate),
            ],
          ),
        ),
      );
    } catch (e) {
      AppLogger.instance.error('Settings unavailable (${e.runtimeType})');
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: AppColors.healthRed,
              ),
              const SizedBox(height: AppMetrics.spaceMd),
              const Text(
                AppStrings.somethingWentWrong,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: AppMetrics.spaceXs),
              ElevatedButton(
                onPressed: () => setState(() {}),
                child: const Text(AppStrings.tryAgain),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _editSystemPrompt(
    ChatProvider provider,
    ModelSettings settings,
  ) async {
    final chatId = provider.currentChat?.id;
    await showDialog<void>(
      context: context,
      builder: (_) => SystemPromptEditorDialog(
        initialPrompt: settings.systemPrompt,
        onSave: (value) {
          if (provider.currentChat?.id != chatId) {
            throw StateError('Chat selection changed while editing');
          }
          return provider.updateSettings(
            provider.settings.copyWith(systemPrompt: value),
          );
        },
      ),
    );
  }

  Widget _buildAdvancedSettings(
    ChatProvider provider,
    ModelSettings settings,
    bool canMutate,
  ) {
    final runtime = context.watch<ModelWarmupService>();
    final ownerId = provider.currentChat?.id;
    void preview(ModelSettings next) =>
        _previewChatSettings(provider, next, ownerId, settings.modelId);
    Future<void> persist(ModelSettings next) =>
        _persistChatSettings(provider, next, ownerId, settings.modelId);
    final provenContext = math.max(
      AppConstants.minimumContextSize,
      runtime.effectiveProfile?.contextSize ??
          AppConstants.conservativeUnknownContextSize,
    );
    final contextSize = (settings.contextSizeOverride ?? provenContext).clamp(
      AppConstants.minimumContextSize,
      provenContext,
    );
    final maximumThreads = math.max(1, Platform.numberOfProcessors);
    final threads =
        (settings.generationThreadsOverride ??
                runtime.effectiveProfile?.generationThreads ??
                1)
            .clamp(1, maximumThreads);
    final maximumBatch = math.min(
      AppConstants.nativeMaximumBatchSize,
      provenContext,
    );
    final batch =
        (settings.batchSizeOverride ??
                runtime.effectiveProfile?.batchSize ??
                AppConstants.defaultBatchSize)
            .clamp(AppConstants.minimumBatchSize, maximumBatch);
    return ExpansionTile(
      initiallyExpanded: true,
      title: const Text('Advanced runtime'),
      subtitle: const Text('Unsafe values are clamped by the runtime.'),
      children: [
        ListTile(
          title: const Text('Automatic tuning'),
          subtitle: Text(
            runtime.fallbackReason ??
                'Status: ${runtime.tuningStatus.name}; effective values are measured locally.',
          ),
          trailing: runtime.lastTunedAt == null
              ? null
              : Text(
                  runtime.lastTunedAt!.toLocal().toString().split('.').first,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
        ),
        if (runtime.effectiveProfile != null)
          ListTile(
            title: const Text('Effective runtime'),
            subtitle: Text(
              '${runtime.effectiveProfile!.contextSize} context · '
              '${runtime.effectiveProfile!.generationThreads} threads · '
              '${runtime.effectiveProfile!.batchSize} batch · '
              '${runtime.effectiveProfile!.gpuLayers == 0 ? 'CPU' : '${runtime.effectiveProfile!.gpuLayers} GPU layers'}',
            ),
          ),
        _buildSliderSetting(
          enabled: canMutate,
          label: 'Context tokens',
          value: contextSize.toDouble(),
          min: AppConstants.minimumContextSize.toDouble(),
          max: provenContext.toDouble(),
          divisions: math.max(
            1,
            (provenContext - AppConstants.minimumContextSize) ~/ 512,
          ),
          displayValue: contextSize.toString(),
          onChanged: (value) => preview(
            provider.settings.copyWith(contextSizeOverride: value.toInt()),
          ),
          onChangeEnd: (value) => persist(
            provider.settings.copyWith(contextSizeOverride: value.toInt()),
          ),
        ),
        _buildSliderSetting(
          enabled: canMutate,
          label: 'CPU threads',
          value: threads.toDouble(),
          min: 1,
          max: maximumThreads.toDouble(),
          divisions: maximumThreads > 1 ? maximumThreads - 1 : 1,
          displayValue: threads.toString(),
          onChanged: (value) => preview(
            provider.settings.copyWith(
              generationThreadsOverride: value.toInt(),
              promptThreadsOverride: value.toInt(),
            ),
          ),
          onChangeEnd: (value) => persist(
            provider.settings.copyWith(
              generationThreadsOverride: value.toInt(),
              promptThreadsOverride: value.toInt(),
            ),
          ),
        ),
        _buildSliderSetting(
          enabled: canMutate,
          label: 'Prompt batch size',
          value: batch.toDouble(),
          min: AppConstants.minimumBatchSize.toDouble(),
          max: maximumBatch.toDouble(),
          divisions: math.max(
            1,
            (maximumBatch - AppConstants.minimumBatchSize) ~/ 32,
          ),
          displayValue: batch.toString(),
          onChanged: (value) => preview(
            provider.settings.copyWith(batchSizeOverride: value.toInt()),
          ),
          onChangeEnd: (value) => persist(
            provider.settings.copyWith(batchSizeOverride: value.toInt()),
          ),
        ),
        FutureBuilder<bool>(
          future: _vulkanAvailableFuture,
          builder: (context, snapshot) {
            final available = snapshot.data ?? false;
            return SwitchListTile(
              title: const Text('Experimental Vulkan GPU'),
              subtitle: Text(
                available
                    ? 'Enabled only after load, inference, cancellation, memory, and thermal self-tests.'
                    : 'Unavailable because this build or device does not expose Vulkan.',
              ),
              value:
                  available &&
                  settings.accelerationPreference ==
                      AccelerationPreference.experimentalGpu,
              onChanged: available && canMutate
                  ? (enabled) => persist(
                      provider.settings.copyWith(
                        accelerationPreference: enabled
                            ? AccelerationPreference.experimentalGpu
                            : AccelerationPreference.cpu,
                      ),
                    )
                  : null,
            );
          },
        ),
        TextButton(
          onPressed: !canMutate || _resettingAuto
              ? null
              : () => _resetChatToAuto(
                  runtime,
                  provider,
                  ownerId,
                  settings.modelId,
                ),
          child: const Text('Reset to Auto'),
        ),
      ],
    );
  }

  Future<void> _importModel() async {
    if (_importing || !mounted) return;
    setState(() => _importing = true);
    try {
      final model = await _modelRegistry.importGguf();
      if (model == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Model imported. Choose Use for this chat in Model Library.',
          ),
        ),
      );
    } catch (error) {
      AppLogger.instance.warning('Model import failed (${error.runtimeType})');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Model import failed. Please retry in Model Library.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Widget _infoRow(String label, String value) {
    return Semantics(
      label: '$label: $value',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 14)),
            Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderSetting({
    required bool enabled,
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    String? displayValue,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text(displayValue ?? value.toStringAsFixed(2)),
            ],
          ),
          Semantics(
            label: label,
            slider: true,
            value: displayValue ?? value.toStringAsFixed(2),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: enabled ? onChanged : null,
              onChangeEnd: enabled ? (onChangeEnd ?? onChanged) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRedownloadButton(bool canMutate) {
    return Consumer<ModelDownloadService>(
      builder: (context, downloadService, _) {
        return Column(
          children: [
            Semantics(
              label: AppStrings.resetModelButton,
              button: true,
              child: ElevatedButton(
                onPressed: !canMutate || _resettingBundledDownload
                    ? null
                    : () => _resetBundledDownload(downloadService),
                child: const Text(AppStrings.resetModelButton),
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<String>(
              future: _appVersionFuture,
              builder: (context, snapshot) =>
                  _DebugTapGate(label: snapshot.data ?? 'Loading app version…'),
            ),
          ],
        );
      },
    );
  }
}

class _DebugTapGate extends StatefulWidget {
  const _DebugTapGate({required this.label});

  final String label;

  @override
  State<_DebugTapGate> createState() => _DebugTapGateState();
}

class _DebugTapGateState extends State<_DebugTapGate> {
  int _tapCount = 0;

  void _onTap() {
    _tapCount++;
    if (_tapCount >= 5) {
      _tapCount = 0;
      DebugState.instance.enable();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.devModeEnabled)),
        );
      }
    } else {
      Future.delayed(const Duration(seconds: 3), () {
        _tapCount = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      button: true,
      child: GestureDetector(
        onTap: _onTap,
        child: Text(widget.label, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}
