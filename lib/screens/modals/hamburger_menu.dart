import 'package:flutter/material.dart';
import '../../constants/app_strings.dart';
import '../../utils/debug_state.dart';
import '../../widgets/startup_mutation_access.dart';

class HamburgerMenu extends StatelessWidget {
  const HamburgerMenu({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                AppStrings.chatOptions,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          StartupMutationAccess(
            builder: (context, enabled) => ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Rename chat'),
              enabled: enabled,
              onTap: enabled ? () => Navigator.pop(context, 'rename') : null,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.memory_outlined),
            title: const Text('Model Library'),
            onTap: () => Navigator.pop(context, 'model_library'),
          ),
          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('Chat settings'),
            onTap: () => Navigator.pop(context, 'settings'),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share_rounded),
            title: const Text(AppStrings.exportConversation),
            onTap: () => Navigator.pop(context, 'export'),
          ),
          FutureBuilder<bool>(
            future: DebugState.instance.isEnabled(),
            builder: (context, snapshot) => snapshot.data == true
                ? ListTile(
                    leading: const Icon(Icons.developer_mode),
                    title: const Text(AppStrings.debugMenu),
                    onTap: () => Navigator.pop(context, 'debug'),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    ),
  );
}
