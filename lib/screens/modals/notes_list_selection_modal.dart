import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants/app_strings.dart';
import '../../models/note.dart';
import '../../providers/note_provider.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/startup_mutation_access.dart';
import '../../widgets/saved_text_preview.dart';
import 'note_edit_modal.dart';

class NotesListSelectionModal extends StatefulWidget {
  const NotesListSelectionModal({super.key, this.selectionEnabled = true});
  final bool selectionEnabled;

  @override
  State<NotesListSelectionModal> createState() =>
      _NotesListSelectionModalState();
}

class _NotesListSelectionModalState extends State<NotesListSelectionModal> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NoteProvider>().loadNotes();
    });
  }

  void _selectNote(Note note) {
    Navigator.pop(context, note);
  }

  Future<void> _createNote() async {
    if (!mounted) return;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const NoteEditModal(),
    );
    if (result != null && mounted) {
      try {
        await context.read<NoteProvider>().createNote(
          result['title']!,
          result['content']!,
        );
      } catch (error) {
        if (mounted) StartupMutationAccess.reportFailure(context, error);
      }
    }
  }

  Future<void> _editNote(Note note) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => NoteEditModal(note: note),
    );
    if (result != null && mounted) {
      final updated = Note(
        id: note.id,
        title: result['title']!,
        content: result['content']!,
        createdAt: note.createdAt,
        updatedAt: DateTime.now(),
      );
      try {
        await context.read<NoteProvider>().updateNote(updated);
      } catch (error) {
        if (mounted) StartupMutationAccess.reportFailure(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StartupMutationAccess(
      builder: (context, canMutate) => Consumer<NoteProvider>(
        builder: (context, noteProvider, _) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      widget.selectionEnabled ? AppStrings.selectNote : 'Notes',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!canMutate)
                    const Text(
                      'Saved notes are read-only while the app is recovering.',
                    ),
                  if (noteProvider.isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (noteProvider.notes.isEmpty)
                    Semantics(
                      label: AppStrings.noNotes,
                      child: const Center(child: Text(AppStrings.noNotes)),
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          ...noteProvider.notes.map(
                            (note) => Semantics(
                              label:
                                  '${canMutate && widget.selectionEnabled ? AppStrings.selectNote : 'View note'}: ${note.title}',
                              button: true,
                              child: ListTile(
                                leading: const Icon(Icons.note),
                                title: Text(note.title),
                                subtitle: Text(
                                  note.content,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Semantics(
                                      label:
                                          '${AppStrings.editNote}: ${note.title}',
                                      button: true,
                                      child: IconButton(
                                        icon: const Icon(Icons.edit, size: 18),
                                        onPressed: canMutate
                                            ? () => _editNote(note)
                                            : null,
                                      ),
                                    ),
                                    Semantics(
                                      label:
                                          '${AppStrings.deleteNote}: ${note.title}',
                                      button: true,
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 18,
                                        ),
                                        onPressed: !canMutate
                                            ? null
                                            : () async {
                                                final confirmed =
                                                    await ConfirmDialog.show(
                                                      context: context,
                                                      title:
                                                          AppStrings.deleteNote,
                                                      message: AppStrings
                                                          .deleteNoteConfirm
                                                          .replaceFirst(
                                                            '{title}',
                                                            note.title,
                                                          ),
                                                      confirmLabel:
                                                          AppStrings.delete,
                                                    );
                                                if (confirmed == true &&
                                                    mounted) {
                                                  try {
                                                    await context
                                                        .read<NoteProvider>()
                                                        .deleteNote(note.id!);
                                                  } catch (error) {
                                                    if (mounted)
                                                      StartupMutationAccess.reportFailure(
                                                        context,
                                                        error,
                                                      );
                                                  }
                                                }
                                              },
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: canMutate && widget.selectionEnabled
                                    ? () => _selectNote(note)
                                    : () => showSavedTextPreview(
                                        context,
                                        title: note.title,
                                        content: note.content,
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  Semantics(
                    label: AppStrings.createNewNote,
                    button: true,
                    child: ListTile(
                      leading: const Icon(Icons.add),
                      title: const Text(AppStrings.createNewNote),
                      enabled: canMutate,
                      onTap: canMutate ? _createNote : null,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
