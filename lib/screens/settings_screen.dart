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
import '../models/generation_setting.dart';
import '../widgets/validated_setting_editor_dialog.dart';
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
part 'settings_app_sections.dart';
part 'settings_chat_sections.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.logger}) : _chatSettings = false;
  const SettingsScreen.chat({super.key, this.logger}) : _chatSettings = true;
  final bool _chatSettings;
  final AppLogger? logger;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<String> _appVersionFuture;
  Future<bool>? _vulkanAvailableFuture;
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
      final chatProvider = widget._chatSettings
          ? context.watch<ChatProvider>()
          : null;
      final themeProvider = widget._chatSettings
          ? null
          : context.watch<ThemeProvider>();

      return StartupMutationAccess(
        builder: (context, canMutate) => Scaffold(
          appBar: AppBar(
            title: Text(
              widget._chatSettings ? 'Chat settings' : AppStrings.settingsTitle,
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: widget._chatSettings
                ? _buildChatSections(chatProvider!, canMutate)
                : _buildAppSections(themeProvider!, canMutate),
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

  Future<void> _showOwnedSettingsEditor(
    ChatProvider provider,
    int? chatId,
    String modelId,
    Widget Function() editor,
  ) async {
    if (!mounted) return;
    try {
      _requireSettingsView(provider, chatId, modelId);
      final dialog = editor();
      await showDialog<void>(context: context, builder: (_) => dialog);
    } catch (error) {
      _reportSettingsActionFailure(error);
    }
  }

  Future<void> _editGenerationSetting(
    ChatProvider provider,
    GenerationSetting field,
    int? chatId,
    String modelId,
  ) => _showOwnedSettingsEditor(
    provider,
    chatId,
    modelId,
    () => ValidatedSettingEditorDialog(
      label: field.label,
      description: field.description,
      initialValue: field.valueOf(provider.settings),
      validate: field.validate,
      presets: field == GenerationSetting.maxTokens
          ? GenerationSettingsPresentationPolicy.outputPresets
          : const [],
      keyboardType: TextInputType.numberWithOptions(
        signed: true,
        decimal: !field.isInteger,
      ),
      onSave: (value) {
        _requireSettingsView(provider, chatId, modelId);
        return provider.updateSettings(field.apply(provider.settings, value));
      },
    ),
  );

  Future<void> _editSystemPrompt(
    ChatProvider provider,
    ModelSettings settings,
    int? chatId,
  ) => _showOwnedSettingsEditor(
    provider,
    chatId,
    settings.modelId,
    () => SystemPromptEditorDialog(
      initialPrompt: settings.systemPrompt,
      onSave: (value) {
        _requireSettingsView(provider, chatId, settings.modelId);
        return provider.updateSettings(
          provider.settings.copyWith(systemPrompt: value),
        );
      },
    ),
  );

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
          future: _vulkanAvailableFuture ??=
              const AndroidRuntimeCapabilitiesProvider().snapshot().then(
                (capabilities) => capabilities.supportsBackend('vulkan'),
              ),
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

  Widget _infoRow(String label, String value) => Semantics(
    label: '$label: $value',
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppMetrics.spaceXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppMetrics.spaceXxs),
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    ),
  );

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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: AppMetrics.spaceXs,
            runSpacing: AppMetrics.spaceXxs,
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
