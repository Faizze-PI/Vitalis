import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/theme_provider.dart';
import '../../utils/debug_state.dart';
import '../../constants/app_strings.dart';

class HamburgerMenu extends StatelessWidget {
  const HamburgerMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.read<ChatProvider>();
    final themeProvider = context.watch<ThemeProvider>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: const Text(
                AppStrings.chatOptions,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            Semantics(
              label: AppStrings.chatHistory,
              button: true,
              child: ListTile(
                leading: const Icon(Icons.history),
                title: const Text(AppStrings.chatHistory),
                onTap: () => Navigator.pop(context, 'chat_history'),
              ),
            ),
            Semantics(
              label: AppStrings.selectPersona,
              button: true,
              child: ListTile(
                leading: const Icon(Icons.person),
                title: Text(
                  chatProvider.currentPersona?.name ?? AppStrings.selectPersona,
                ),
                onTap: () => Navigator.pop(context, 'select_persona'),
              ),
            ),
            Semantics(
              label: AppStrings.attachNote,
              button: true,
              child: ListTile(
                leading: const Icon(Icons.note),
                title: const Text(AppStrings.attachNote),
                onTap: () => Navigator.pop(context, 'attach_note'),
              ),
            ),
            Semantics(
              label: AppStrings.settingsTitle,
              button: true,
              child: ListTile(
                leading: const Icon(Icons.settings),
                title: const Text(AppStrings.settingsTitle),
                onTap: () => Navigator.pop(context, 'settings'),
              ),
            ),
            const Divider(),
            Semantics(
              label: AppStrings.darkModeToggle,
              child: SwitchListTile(
                secondary: const Icon(Icons.dark_mode),
                title: const Text(AppStrings.darkModeToggle),
                value: themeProvider.isDark,
                onChanged: (_) => themeProvider.toggle(),
              ),
            ),
            Semantics(
              label: AppStrings.exportConversation,
              button: true,
              child: ListTile(
                leading: const Icon(Icons.copy),
                title: const Text(AppStrings.exportConversation),
                onTap: () => Navigator.pop(context, 'export'),
              ),
            ),
            _debugTile(context),
          ],
        ),
      ),
    );
  }

  Widget _debugTile(BuildContext context) {
    return FutureBuilder<bool>(
      future: DebugState.instance.isEnabled(),
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return Column(
          children: [
            const Divider(),
            Semantics(
              label: AppStrings.debugMenu,
              button: true,
              child: ListTile(
                leading: const Icon(Icons.developer_mode),
                title: const Text(AppStrings.debugMenu),
                onTap: () => Navigator.pop(context, 'debug'),
              ),
            ),
          ],
        );
      },
    );
  }
}
