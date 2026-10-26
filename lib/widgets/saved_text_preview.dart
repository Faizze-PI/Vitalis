import 'package:flutter/material.dart';

/// Displays already-loaded saved text without changing its record or selection.
Future<void> showSavedTextPreview(
  BuildContext context, {
  required String title,
  required String content,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: SingleChildScrollView(child: SelectableText(content)),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  ),
);
