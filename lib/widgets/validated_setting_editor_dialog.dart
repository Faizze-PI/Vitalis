import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/startup_access_guard.dart';
import '../utils/app_logger.dart';
import 'startup_mutation_access.dart';

class ValidatedSettingEditorDialog extends StatefulWidget {
  const ValidatedSettingEditorDialog({
    super.key,
    required this.initialValue,
    required this.onSave,
    required this.label,
    this.description,
    this.validate,
    this.presets = const [],
    this.keyboardType = TextInputType.text,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String label;
  final String? description;
  final String? Function(String value)? validate;
  final List<String> presets;
  final TextInputType keyboardType;
  final int minLines;
  final int maxLines;
  final String initialValue;
  final Future<void> Function(String value) onSave;

  @override
  State<ValidatedSettingEditorDialog> createState() =>
      _ValidatedSettingEditorDialogState();
}

class _ValidatedSettingEditorDialogState
    extends State<ValidatedSettingEditorDialog> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
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
      final validation = widget.validate?.call(value);
      if (validation != null) {
        setState(() => _failure = validation);
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
        '${widget.label} save failed (${error.runtimeType})',
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
          widget.validate?.call(_controller.text.trim()) ??
          (canMutate
              ? null
              : 'Editing is unavailable while the app is recovering.');
      return AlertDialog(
        scrollable: true,
        title: Text(widget.label),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.description != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(widget.description!),
              ),
            if (widget.presets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final value in widget.presets)
                      ActionChip(
                        label: Text(value),
                        tooltip: 'Use $value',
                        onPressed: !canMutate || _saving
                            ? null
                            : () {
                                _controller.value = TextEditingValue(
                                  text: value,
                                  selection: TextSelection.collapsed(
                                    offset: value.length,
                                  ),
                                );
                                setState(() => _failure = null);
                              },
                      ),
                  ],
                ),
              ),
            TextField(
              controller: _controller,
              readOnly: !canMutate || _saving,
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              keyboardType: widget.keyboardType,
              onChanged: (_) => setState(() => _failure = null),
              decoration: InputDecoration(
                labelText: widget.label,
                border: const OutlineInputBorder(),
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
