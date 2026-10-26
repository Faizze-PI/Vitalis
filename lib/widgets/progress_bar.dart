import 'package:flutter/material.dart';
import '../constants/app_metrics.dart';

class ProgressBar extends StatelessWidget {
  final double progress;
  final String? label;

  const ProgressBar({super.key, required this.progress, this.label});

  @override
  Widget build(BuildContext context) {
    final displayLabel = label ?? '${(progress * 100).toStringAsFixed(0)}%';
    return Semantics(
      label: '$displayLabel — ${(progress * 100).toStringAsFixed(0)}%',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null) ...[
            Text(label!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: AppMetrics.spaceXs),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(AppMetrics.progressBarRadius),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: AppMetrics.progressBarHeight,
              backgroundColor: Colors.grey[200],
            ),
          ),
        ],
      ),
    );
  }
}
