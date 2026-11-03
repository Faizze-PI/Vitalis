import 'package:flutter/material.dart';
import 'modals/notes_list_selection_modal.dart';
import 'modals/persona_selection_modal.dart';
import 'file_workspace_screen.dart';

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});
  void _open(BuildContext context, Widget content, String title) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(title)),
            body: content,
          ),
        ),
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Saved')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Files and algorithms'),
            subtitle: const Text('Import local inputs for compatible tasks'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const FileWorkspaceScreen(),
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'Reusable context for your conversations. Choosing content here does not attach it to a chat.',
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.notes_outlined),
            title: const Text('Notes'),
            subtitle: const Text('Read and manage saved notes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(
              context,
              const NotesListSelectionModal(selectionEnabled: false),
              'Notes',
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Personas'),
            subtitle: const Text('Read and manage conversation instructions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(
              context,
              const PersonaSelectionModal(selectionEnabled: false),
              'Personas',
            ),
          ),
        ),
      ],
    ),
  );
}
