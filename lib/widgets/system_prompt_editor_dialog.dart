import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/startup_access_guard.dart';
import '../utils/app_logger.dart';
import 'startup_mutation_access.dart';

class SystemPromptEditorDialog extends StatefulWidget {
  const SystemPromptEditorDialog({
    super.key,
    required this.initialPrompt,
    required this.onSave,
  });

  final String initialPrompt;
  final Future<void> Function(String value) onSave;

  @override
  State<SystemPromptEditorDialog> createState() =>
      _SystemPromptEditorDialogState();
}

class _SystemPromptEditorDialogState extends State<SystemPromptEditorDialog> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialPrompt);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !mounted) return;
    try {
      final access = context.read<StartupAccessGuard?>();
      if (access == null) {
        throw StartupAccessDenied(StartupAccessOperation.mutateContent);
      }
      access.require(StartupAccessOperation.mutateContent);
      final value = _controller.text.trim();
      if (value.isEmpty) {
        setState(() => _failure = 'System prompt cannot be empty.');
        return;
      }
      setState(() {
        _saving = true;
        _failure = null;
      });
      await widget.onSave(value);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      AppLogger.instance.warning(
        'System prompt save failed (${error.runtimeType})',
      );
      if (mounted) {
        setState(
          () => _failure = error is StartupAccessDenied
              ? 'Editing is unavailable while the app is recovering.'
              : 'The change could not be saved. Your draft is retained.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => StartupMutationAccess(
    builder: (context, canMutate) {
      final message =
          _failure ??
          (canMutate
              ? null
              : 'Editing is unavailable while the app is recovering.');
      return AlertDialog(
        scrollable: true,
        title: const Text('System prompt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              readOnly: !canMutate || _saving,
              minLines: 5,
              maxLines: 14,
              decoration: const InputDecoration(
                labelText: 'System prompt',
                border: OutlineInputBorder(),
              ),
            ),
            if (message != null)
              Semantics(liveRegion: true, child: Text(message)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: canMutate && !_saving ? _save : null,
            child: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(),
                  )
                : const Text('Save'),
          ),
        ],
      );
    },
  );
}
