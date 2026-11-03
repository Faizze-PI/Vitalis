import 'package:flutter/material.dart';
import '../models/workspace_file.dart';
import '../services/attached_file_reader.dart';
import '../constants/app_metrics.dart';

class AttachedFilesBar extends StatelessWidget {
  const AttachedFilesBar({
    super.key,
    required this.files,
    required this.onRemove,
    this.enabled = true,
  });
  final List<WorkspaceFile> files;
  final Future<void> Function(WorkspaceFile) onRemove;
  final bool enabled;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: AppMetrics.spaceSm),
    child: Row(
      children: [
        for (final file in files)
          Padding(
            padding: const EdgeInsets.only(right: AppMetrics.spaceXs),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth:
                    MediaQuery.sizeOf(context).width - AppMetrics.spaceSm * 2,
              ),
              child: InputChip(
                key: ValueKey('file-${file.id}'),
                avatar: const Icon(Icons.attach_file),
                label: Text(
                  '${AttachedFileReader.supportsName(file.name) ? 'File' : 'Needs decoder'}: ${file.name}',
                  overflow: TextOverflow.ellipsis,
                ),
                deleteButtonTooltipMessage:
                    'Remove attached file: ${file.name}',
                onDeleted: enabled ? () => onRemove(file) : null,
              ),
            ),
          ),
      ],
    ),
  );
}
