part of 'settings_screen.dart';

extension _SettingsMutationActions on _SettingsScreenState {
  void _requirePersistentSettingsAccess() {
    final access = context.read<StartupAccessGuard?>();
    if (access == null) {
      throw StartupAccessDenied(StartupAccessOperation.mutateContent);
    }
    access.require(StartupAccessOperation.mutateContent);
  }

  Future<void> _resetChatToAuto(
    ModelWarmupService runtime,
    ChatProvider provider,
    int? chatId,
    String modelId,
  ) async {
    if (!mounted || _resettingAuto) return;
    ModelSettings automaticSettings() => provider.settings.copyWith(
      tuningMode: TuningMode.automatic,
      accelerationPreference: AccelerationPreference.cpu,
      clearContextSizeOverride: true,
      clearThreadOverrides: true,
      clearBatchSizeOverride: true,
    );
    try {
      _requireSettingsView(provider, chatId, modelId);
      _setAutoResetPending(true);
      await runtime.resetAutoProfile(automaticSettings());
      if (!mounted) return;
      _requireSettingsView(provider, chatId, modelId);
      // Reset only runtime override fields on the current selected settings.
      // Sampling/persona edits made during cache invalidation remain intact.
      await provider.updateSettings(automaticSettings());
    } catch (error) {
      _reportSettingsActionFailure(error);
    } finally {
      _setAutoResetPending(false);
    }
  }

  void _requireSettingsView(
    ChatProvider provider,
    int? chatId,
    String modelId,
  ) {
    final access = context.read<StartupAccessGuard?>();
    if (access == null) {
      throw StartupAccessDenied(StartupAccessOperation.mutateContent);
    }
    access.require(StartupAccessOperation.mutateContent);
    if (provider.currentChat?.id != chatId ||
        provider.settings.modelId != modelId) {
      throw StateError('Settings selection changed');
    }
  }

  void _reportSettingsActionFailure(Object error) {
    if (mounted) {
      StartupMutationAccess.reportFailure(context, error);
    } else {
      AppLogger.instance.warning(
        'Settings action failed after navigation (${error.runtimeType})',
      );
    }
  }

  void _previewChatSettings(
    ChatProvider provider,
    ModelSettings settings,
    int? chatId,
    String modelId,
  ) {
    if (!mounted) return;
    try {
      _requireSettingsView(provider, chatId, modelId);
      provider.updateSettingsLocally(settings);
    } catch (error) {
      _reportSettingsActionFailure(error);
    }
  }

  Future<void> _persistChatSettings(
    ChatProvider provider,
    ModelSettings settings,
    int? chatId,
    String modelId,
  ) async {
    if (!mounted) return;
    try {
      _requireSettingsView(provider, chatId, modelId);
      await provider.updateSettings(settings);
    } catch (error) {
      _reportSettingsActionFailure(error);
    }
  }
}
