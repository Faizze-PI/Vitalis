import 'package:flutter/material.dart';
import '../constants/app_strings.dart';
import '../constants/app_metrics.dart';

class ConversationStatusBar extends StatelessWidget {
  const ConversationStatusBar({
    super.key,
    required this.safe,
    required this.rssMb,
    this.battery,
    this.lastTps,
  });
  final bool safe;
  final int rssMb;
  final int? battery;
  final double? lastTps;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final level = battery;
    final rate = lastTps;
    return Semantics(
      label: AppStrings.healthStatus,
      explicitChildNodes: true,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: AppMetrics.spaceMd),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppMetrics.spaceMd,
          0,
          AppMetrics.spaceMd,
          AppMetrics.spaceSm,
        ),
        minTileHeight: AppMetrics.inputMinHeight,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          safe ? Icons.shield_outlined : Icons.pause_circle_outline,
          size: AppMetrics.iconSizeMd,
          color: safe ? colors.onSurfaceVariant : colors.error,
        ),
        title: Text(
          safe ? 'Device ready' : 'Device protection active',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: safe ? colors.onSurfaceVariant : colors.error,
          ),
        ),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DefaultTextStyle(
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: colors.onSurfaceVariant),
              child: Wrap(
                spacing: AppMetrics.spaceMd,
                runSpacing: AppMetrics.spaceXs,
                children: [
                  Tooltip(
                    message: 'Process resident memory (RSS)',
                    child: Text(
                      rssMb > 0 ? 'Memory: $rssMb MB' : 'Memory: Unknown',
                    ),
                  ),
                  Text(
                    level != null && level >= 0 && level <= 100
                        ? 'Battery: $level%'
                        : 'Battery: Unknown',
                  ),
                  Text(
                    rate != null && rate.isFinite && rate > 0
                        ? 'Last generation: ${rate.toStringAsFixed(1)} tok/s'
                        : 'Last generation: Not measured',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
