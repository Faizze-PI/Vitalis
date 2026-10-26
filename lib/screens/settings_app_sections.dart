part of 'settings_screen.dart';

extension _AppSettingsSections on _SettingsScreenState {
  List<Widget> _buildAppSections(
    ThemeProvider themeProvider,
    bool canMutate,
  ) => [
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
              ? 'Only warnings and errors are kept locally.'
              : 'Local diagnostic events enabled; private content stays excluded.',
        ),
        value: _privacyMode,
        onChanged: canMutate && !_privacyChanging ? _changePrivacyMode : null,
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
                  '',
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

    Text('Models and storage', style: Theme.of(context).textTheme.titleMedium),
    ListTile(
      leading: const Icon(Icons.view_in_ar),
      title: const Text('Model Library'),
      subtitle: const Text(
        'Browse public Hugging Face GGUF models, downloads, and installed models.',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.pushNamed(context, AppRoutes.modelLibrary),
    ),
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
  ];
}
