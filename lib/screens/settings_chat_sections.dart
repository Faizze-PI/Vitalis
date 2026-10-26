part of 'settings_screen.dart';

extension _ChatSettingsSections on _SettingsScreenState {
  List<Widget> _buildChatSections(ChatProvider chatProvider, bool canMutate) {
    final settings = chatProvider.settings;
    final ownerId = chatProvider.currentChat?.id;
    Future<void> persist(ModelSettings next) =>
        _persistChatSettings(chatProvider, next, ownerId, settings.modelId);
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          chatProvider.currentChat == null
              ? 'Choose a conversation to edit its settings.'
              : 'Applies only to ${chatProvider.currentChat!.title}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      if (chatProvider.currentChat != null) ...[
        // --- Model Info ---
        Semantics(
          header: true,
          child: const Text(
            AppStrings.modelInfo,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<ModelDescriptor?>(
          key: ValueKey('model-details-${settings.modelId}'),
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
                  model?.contextTrain == null
                      ? AppStrings.unknown
                      : '${model!.contextTrain} tokens (training maximum)',
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
              ? () => _editSystemPrompt(chatProvider, settings, ownerId)
              : null,
        ),
        FutureBuilder<ModelDescriptor?>(
          key: ValueKey('model-thinking-${settings.modelId}'),
          future: _modelRegistry.findById(settings.modelId),
          builder: (context, snapshot) {
            final supportsThinking = snapshot.data?.supportsThinking == true;
            return SwitchListTile(
              title: const Text('Thinking mode'),
              subtitle: Text(
                supportsThinking
                    ? 'Off is faster and disables reasoning through the verified model template.'
                    : 'Unavailable until this model template is verified.',
              ),
              value:
                  supportsThinking && settings.thinkingMode == ThinkingMode.on,
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
                    persist(chatProvider.settings.copyWith(tuningMode: mode));
                  }
                },
        ),
        if (settings.tuningMode == TuningMode.advanced)
          _buildAdvancedSettings(chatProvider, settings, canMutate),
        for (final field in GenerationSetting.values)
          _generationSettingTile(
            field,
            chatProvider,
            settings,
            ownerId,
            canMutate,
          ),
        const SizedBox(height: 24),
      ],
    ];
  }

  Widget _generationSettingTile(
    GenerationSetting field,
    ChatProvider provider,
    ModelSettings settings,
    int? ownerId,
    bool canMutate,
  ) {
    final value = field.valueOf(settings);
    final error = field.validate(value);
    return ListTile(
      title: Text(field.label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
          if (error != null)
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      trailing: Icon(
        error == null ? Icons.edit_outlined : Icons.warning_amber_outlined,
      ),
      enabled: canMutate,
      onTap: canMutate
          ? () => _editGenerationSetting(
              provider,
              field,
              ownerId,
              settings.modelId,
            )
          : null,
    );
  }
}
