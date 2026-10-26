import 'package:flutter/material.dart';
import '../constants/app_metrics.dart';
import '../constants/app_strings.dart';
import '../models/note.dart';

class AttachedNotesBar extends StatelessWidget {
  const AttachedNotesBar({
    super.key,
    required this.notes,
    required this.onRemove,
  });

  final List<Note> notes;
  final Future<void> Function(Note) onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppMetrics.spaceSm),
      child: Row(
        children: [
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(right: AppMetrics.spaceXs),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      MediaQuery.sizeOf(context).width - AppMetrics.spaceSm * 2,
                ),
                child: InputChip(
                  key: ValueKey(note.id),
                  avatar: Icon(Icons.note, color: colors.onSurface),
                  backgroundColor: colors.surfaceContainerHighest,
                  label: Semantics(
                    label: '${AppStrings.attachedNote} ${note.title}',
                    child: Text(
                      '${AppStrings.notePrefix}${note.title}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  labelStyle: TextStyle(color: colors.onSurface),
                  deleteIconColor: colors.onSurface,
                  deleteButtonTooltipMessage:
                      'Remove attached note: ${note.title}',
                  onDeleted: () => onRemove(note),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
