import 'package:flutter/material.dart';
import 'validated_setting_editor_dialog.dart';

class SystemPromptEditorDialog extends StatelessWidget {
  const SystemPromptEditorDialog({
    super.key,
    required this.initialPrompt,
    required this.onSave,
  });
  final String initialPrompt;
  final Future<void> Function(String value) onSave;
  @override
  Widget build(BuildContext context) => ValidatedSettingEditorDialog(
    label: 'System prompt',
    initialValue: initialPrompt,
    onSave: onSave,
    minLines: 5,
    maxLines: 14,
    keyboardType: TextInputType.multiline,
    validate: (value) =>
        value.isEmpty ? 'System prompt cannot be empty.' : null,
  );
}
