// FILE: lib/screens/modals/note_edit_modal.dart
// PURPOSE: Note create/edit dialog with semantics
// STATUS: PRODUCTION-HARDENED — Phase 3 Accessibility, Phase 8 Localization

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/startup_access_guard.dart';
import '../../widgets/startup_mutation_access.dart';
import '../../models/note.dart';
import '../../constants/app_constants.dart';
import '../../constants/app_strings.dart';

class NoteEditModal extends StatefulWidget {
  final Note? note;

  const NoteEditModal({super.key, this.note});

  @override
  State<NoteEditModal> createState() => _NoteEditModalState();
}

class _NoteEditModalState extends State<NoteEditModal> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  String? _validationError;

  @override
  void initState() {
    super.initState();
    if (widget.note != null) {
      _titleController.text = widget.note!.title;
      _contentController.text = widget.note!.content;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _save() {
    final guard = context.read<StartupAccessGuard?>();
    try {
      if (guard == null)
        throw StartupAccessDenied(StartupAccessOperation.mutateContent);
      guard.require(StartupAccessOperation.mutateContent);
    } catch (_) {
      setState(
        () => _validationError =
            'Editing is unavailable while the app is recovering.',
      );
      return;
    }
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty || content.isEmpty) {
      setState(() => _validationError = AppStrings.validationTitleContent);
      return;
    }
    Navigator.pop(context, {'title': title, 'content': content});
  }

  @override
  Widget build(BuildContext context) {
    return StartupMutationAccess(
      builder: (context, canMutate) => Semantics(
        label: widget.note != null ? AppStrings.editNote : AppStrings.newNote,
        child: AlertDialog(
          title: Text(
            widget.note != null ? AppStrings.editNote : AppStrings.newNote,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!canMutate)
                  const Text('Read-only while the app is recovering.'),
                Semantics(
                  label: AppStrings.noteTitle,
                  textField: true,
                  child: TextField(
                    controller: _titleController,
                    readOnly: !canMutate,
                    decoration: const InputDecoration(
                      labelText: AppStrings.noteTitle,
                    ),
                    maxLength: AppConstants.maxNoteTitleLength,
                    buildCounter:
                        (
                          _, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => Text('$currentLength/$maxLength'),
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  label: AppStrings.noteContent,
                  textField: true,
                  child: TextField(
                    controller: _contentController,
                    readOnly: !canMutate,
                    decoration: const InputDecoration(
                      labelText: AppStrings.noteContent,
                      helperText: 'Storage safety limit: 1 MiB',
                    ),
                    maxLines: 5,
                  ),
                ),
                if (_validationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _validationError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            Semantics(
              label: AppStrings.cancel,
              button: true,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(AppStrings.cancel),
              ),
            ),
            Semantics(
              label: AppStrings.save,
              button: true,
              child: TextButton(
                onPressed: canMutate ? _save : null,
                child: const Text(AppStrings.save),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
