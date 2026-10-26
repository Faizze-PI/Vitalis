import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/chat_provider.dart';
import '../providers/generation_provider.dart';
import '../providers/health_provider.dart';
import '../utils/app_logger.dart';
import '../utils/debug_state.dart';
import '../constants/app_strings.dart';

class DebugSettingsScreen extends StatefulWidget {
  const DebugSettingsScreen({super.key});

  @override
  State<DebugSettingsScreen> createState() => _DebugSettingsScreenState();
}

class _DebugSettingsScreenState extends State<DebugSettingsScreen> {
  Timer? _refreshTimer;
  String _logs = '';

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final logs = await AppLogger.instance.getLogs(maxLines: 50);
    if (mounted) {
      setState(() {
        _logs = logs;
      });
    }
  }

  Future<void> _exportLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export Logs'),
        content: const Text(
          'Logs may contain conversation context. Only share with trusted recipients.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Export'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await Share.share(_logs, subject: 'Vitalis Debug Logs');
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final generationProvider = context.watch<GenerationProvider>();
    final healthProvider = context.watch<HealthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.debugTitle),
        actions: [
          Semantics(
            label: AppStrings.clearLogsTooltip,
            button: true,
            child: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: AppStrings.clearLogsTooltip,
              onPressed: () async {
                final result = await AppLogger.instance.clearLogs();
                if (!mounted) return;
                if (!result.complete) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Some logs could not be removed. Please retry.',
                      ),
                    ),
                  );
                }
                _refresh();
              },
            ),
          ),
          Semantics(
            label: AppStrings.exportLogsTooltip,
            button: true,
            child: IconButton(
              icon: const Icon(Icons.share),
              tooltip: AppStrings.exportLogsTooltip,
              onPressed: _exportLogs,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Semantics(header: true, child: _section(AppStrings.systemSection)),
          Semantics(
            label: '${AppStrings.ramUsage}: $healthProvider.rssMb MB',
            child: _row(AppStrings.ramUsage, '$healthProvider.rssMb MB'),
          ),
          Semantics(
            label:
                '${AppStrings.tokenThroughput}: ${generationProvider.lastTps.toStringAsFixed(1)} tok/s',
            child: _row(
              AppStrings.tokenThroughput,
              '${generationProvider.lastTps.toStringAsFixed(1)} tok/s',
            ),
          ),
          Semantics(
            label:
                '${AppStrings.lastTokens}: ${generationProvider.lastTokenCount}',
            child: _row(
              AppStrings.lastTokens,
              '${generationProvider.lastTokenCount}',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            AppStrings.debugContextUsageLabel,
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 4),
          Semantics(
            label:
                '${AppStrings.debugContextUsageLabel}: ${(chatProvider.contextUsage * 100).toStringAsFixed(0)}%',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: chatProvider.contextUsage,
                minHeight: 8,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(
                  chatProvider.contextUsage > 0.8
                      ? Colors.red
                      : chatProvider.contextUsage > 0.6
                      ? Colors.orange
                      : Colors.green,
                ),
              ),
            ),
          ),
          if (chatProvider.contextUsage > 0.8)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                AppStrings.contextTruncated,
                style: TextStyle(fontSize: 11, color: Colors.red),
              ),
            ),
          const SizedBox(height: 16),
          Semantics(header: true, child: _section(AppStrings.batteryHealth)),
          Semantics(
            label:
                '${AppStrings.level}: ${healthProvider.batteryKnown ? '${healthProvider.batteryLevel}%' : 'Unknown'}',
            child: _row(
              AppStrings.level,
              healthProvider.batteryKnown
                  ? '${healthProvider.batteryLevel}%'
                  : 'Unknown',
            ),
          ),
          Semantics(
            label:
                '${AppStrings.charging}: ${_telemetryBoolean(healthProvider.isCharging)}',
            child: _row(
              AppStrings.charging,
              _telemetryBoolean(healthProvider.isCharging),
            ),
          ),
          Semantics(
            label:
                '${AppStrings.batterySaver}: ${_telemetryState(healthProvider.batterySaver)}',
            child: _row(
              AppStrings.batterySaver,
              _telemetryState(healthProvider.batterySaver),
            ),
          ),
          Semantics(
            label:
                '${AppStrings.heavyOpSafe}: ${healthProvider.isSafeForHeavy ? AppStrings.yes : AppStrings.no}',
            child: _row(
              AppStrings.heavyOpSafe,
              healthProvider.isSafeForHeavy ? AppStrings.yes : AppStrings.no,
            ),
          ),
          Semantics(
            label:
                '${AppStrings.downloadSafe}: ${healthProvider.isSafeForDownload ? AppStrings.yes : AppStrings.no}',
            child: _row(
              AppStrings.downloadSafe,
              healthProvider.isSafeForDownload ? AppStrings.yes : AppStrings.no,
            ),
          ),
          const SizedBox(height: 16),
          Semantics(header: true, child: _section(AppStrings.logsSection)),
          const SizedBox(height: 8),
          Semantics(
            label: AppStrings.logsSection,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: SelectableText(
                  _logs.isEmpty ? AppStrings.emptyLogs : _logs,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Semantics(
            label: AppStrings.disableDevMode,
            button: true,
            child: Center(
              child: TextButton.icon(
                icon: const Icon(Icons.lock_open),
                label: const Text(AppStrings.disableDevMode),
                onPressed: () async {
                  await DebugState.instance.disable();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text(AppStrings.devModeDisabled)),
                    );
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
    );
  }

  String _telemetryBoolean(bool? value) => value == null
      ? 'Unknown'
      : value
      ? AppStrings.yes
      : AppStrings.no;

  String _telemetryState(bool? value) => value == null
      ? 'Unknown'
      : value
      ? AppStrings.active
      : AppStrings.inactive;

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
