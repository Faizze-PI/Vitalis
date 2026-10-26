import 'dart:io';

final class CoverageRequirement {
  const CoverageRequirement(this.pathSuffix, this.minimumPercent);

  final String pathSuffix;
  final double minimumPercent;
}

const requirements = <CoverageRequirement>[
  CoverageRequirement('lib/services/application_error_reporter.dart', 90),
  CoverageRequirement('lib/services/response_frame_timing.dart', 90),
  CoverageRequirement('lib/widgets/response_frame_observer.dart', 90),
  CoverageRequirement('lib/widgets/startup_mutation_access.dart', 90),
  CoverageRequirement('lib/widgets/system_prompt_editor_dialog.dart', 90),
  CoverageRequirement('lib/widgets/validated_setting_editor_dialog.dart', 90),
  CoverageRequirement('lib/models/generation_setting.dart', 90),
  CoverageRequirement('lib/screens/settings_mutation_actions.dart', 90),
  CoverageRequirement('lib/models/startup_capabilities.dart', 90),
  CoverageRequirement('lib/services/startup_coordinator.dart', 90),
  CoverageRequirement('lib/services/startup_capability_source.dart', 90),
  CoverageRequirement('lib/services/model_startup_inspector.dart', 90),
  CoverageRequirement('lib/services/startup_access_guard.dart', 90),
  CoverageRequirement('lib/services/selected_model_readiness.dart', 90),
  CoverageRequirement('lib/services/model_recovery_controller.dart', 90),
  CoverageRequirement('lib/providers/model_library_provider.dart', 80),
  CoverageRequirement('lib/providers/note_provider.dart', 80),
  CoverageRequirement('lib/providers/persona_provider.dart', 80),
  CoverageRequirement('lib/providers/theme_provider.dart', 80),
  CoverageRequirement('lib/models/device_safety_policy.dart', 90),
  CoverageRequirement('lib/services/chat_state_controller.dart', 90),
  CoverageRequirement('lib/database/database_helper.dart', 90),
  CoverageRequirement('lib/database/installation_journal_schema.dart', 90),
  CoverageRequirement('lib/database/model_installation_journal.dart', 90),
  CoverageRequirement('lib/database/model_installation_projection.dart', 90),
  CoverageRequirement('lib/models/model_installation.dart', 90),
  CoverageRequirement('lib/services/model_installation_promoter.dart', 90),
  CoverageRequirement('lib/models/imported_model_file.dart', 90),
  CoverageRequirement('lib/models/restoration_artifact.dart', 90),
  CoverageRequirement('lib/services/model_shard_restorer.dart', 90),
  CoverageRequirement('lib/services/model_shard_staging.dart', 90),
  CoverageRequirement('lib/services/hardware_sentinel_service.dart', 80),
  CoverageRequirement('lib/services/memory_pressure_service.dart', 80),
  CoverageRequirement('lib/services/model_warmup_service.dart', 80),
  CoverageRequirement('lib/services/runtime_auto_tuner.dart', 80),
  CoverageRequirement('lib/services/runtime_benchmark_workload.dart', 90),
  CoverageRequirement('lib/services/runtime_profile_store.dart', 90),
  CoverageRequirement('lib/services/model_warmup_recovery.dart', 90),
  CoverageRequirement('lib/services/runtime_capabilities_provider.dart', 80),
  CoverageRequirement('lib/services/model_registry_service.dart', 80),
  CoverageRequirement('lib/services/model_verification_runtime.dart', 90),
  CoverageRequirement('lib/services/model_download_manager.dart', 80),
  CoverageRequirement('lib/services/model_download_staging.dart', 90),
  CoverageRequirement('lib/services/native_transfer_stop.dart', 90),
  CoverageRequirement('lib/services/model_downloader.dart', 80),
  CoverageRequirement('lib/services/model_storage_preflight.dart', 90),
  CoverageRequirement('lib/services/model_download_service.dart', 80),
  CoverageRequirement('lib/providers/chat_provider.dart', 80),
  CoverageRequirement('lib/providers/chat_settings_persistence.dart', 90),
  CoverageRequirement('lib/providers/generation_provider.dart', 80),
  CoverageRequirement('lib/providers/generation_recovery.dart', 90),
  CoverageRequirement('lib/utils/app_logger.dart', 80),
  CoverageRequirement('lib/src/runtime_session_reservation.dart', 90),
  CoverageRequirement('lib/src/runtime_initialization_guard.dart', 90),
  CoverageRequirement('lib/src/runtime_owner_recovery_guard.dart', 90),
  CoverageRequirement('lib/src/runtime_progress.dart', 90),
  CoverageRequirement('lib/src/runtime_cancellation_control.dart', 90),
  CoverageRequirement('lib/src/runtime_request_finalizer.dart', 90),
  CoverageRequirement('lib/src/runtime_cleanup_quarantine.dart', 90),
  CoverageRequirement('lib/src/runtime_watchdog_policy.dart', 90),
  CoverageRequirement('lib/src/runtime_shutdown_waiter.dart', 90),
  CoverageRequirement('lib/src/runtime_native_termination.dart', 90),
  CoverageRequirement('lib/src/gguf_metadata_reader.dart', 90),
  CoverageRequirement('lib/src/stop_sequence_prefix.dart', 90),
  CoverageRequirement('lib/src/inference_output_timing.dart', 90),
];

// Stage 2 requires native lifecycle qualification in addition to root coverage.
const nativeLifecycleRequirements = <CoverageRequirement>[
  CoverageRequirement('lib/src/native_template_applier.dart', 90),
  CoverageRequirement('lib/src/verified_thinking_templates.dart', 90),
  CoverageRequirement('lib/src/native_runtime_bridge.dart', 90),
  CoverageRequirement('lib/src/llamacpp_model.dart', 90),
  CoverageRequirement('lib/src/persistent_inference_isolate.dart', 90),
  CoverageRequirement('lib/src/inference_isolate_handler.dart', 90),
  CoverageRequirement('lib/src/llamacpp_chat_repository.dart', 90),
];

List<CoverageRequirement> selectedRequirements({
  bool includeNativeLifecycle = false,
}) => [
  ...requirements,
  if (includeNativeLifecycle) ...nativeLifecycleRequirements,
];

void main(List<String> arguments) {
  final required = selectedRequirements(
    includeNativeLifecycle: arguments.contains('--native-lifecycle'),
  );
  final suppliedPaths = arguments
      .where((argument) => argument != '--native-lifecycle')
      .toList();
  final paths = suppliedPaths.isEmpty ? ['coverage/lcov.info'] : suppliedPaths;
  final reports = <List<String>>[];
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('Coverage gate failed: missing $path');
      exitCode = 1;
      return;
    }
    reports.add(file.readAsLinesSync());
  }
  late Map<String, ({int found, int hit})> records;
  try {
    records = mergeCoverageReports(reports);
  } on FormatException catch (error) {
    stderr.writeln('Coverage gate failed: ${error.message}');
    exitCode = 1;
    return;
  }
  final failures = evaluateCoverage(records, required);
  if (failures.isNotEmpty) {
    stderr.writeln('Coverage gate failed:');
    for (final failure in failures) {
      stderr.writeln(' - $failure');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln('Coverage gate passed (${required.length} risk files).');
}

/// Union executable line identities, never sum per-run LF/LH totals.
/// Reports must originate from the same source checkpoint and path convention.
Map<String, ({int found, int hit})> mergeCoverageReports(
  Iterable<List<String>> reports,
) {
  final sources = <String, Map<int, bool>>{};
  for (final report in reports) {
    String? source;
    final lines = <int, bool>{};
    int? declaredFound;
    int? declaredHit;
    for (final entry in report) {
      if (entry.startsWith('SF:')) {
        if (source != null) throw const FormatException('Unterminated record');
        source = entry.substring(3).replaceAll('\\', '/');
        lines.clear();
        declaredFound = null;
        declaredHit = null;
      } else if (source != null && entry.startsWith('DA:')) {
        final fields = entry.substring(3).split(',');
        final number = fields.length >= 2 ? int.tryParse(fields[0]) : null;
        final hits = fields.length >= 2 ? int.tryParse(fields[1]) : null;
        if (number == null || number <= 0 || hits == null || hits < 0) {
          throw const FormatException('Invalid executable line record');
        }
        lines[number] = (lines[number] ?? false) || hits > 0;
      } else if (source != null && entry.startsWith('LF:')) {
        declaredFound = int.tryParse(entry.substring(3));
        if (declaredFound == null || declaredFound < 0) {
          throw const FormatException('Invalid executable line total');
        }
      } else if (source != null && entry.startsWith('LH:')) {
        declaredHit = int.tryParse(entry.substring(3));
        if (declaredHit == null || declaredHit < 0) {
          throw const FormatException('Invalid covered line total');
        }
      } else if (entry == 'end_of_record' && source != null) {
        if (declaredFound != null && declaredFound != lines.length) {
          throw FormatException('Missing line identities for $source');
        }
        if (declaredHit != null &&
            declaredHit != lines.values.where((hit) => hit).length) {
          throw FormatException('Covered line total disagrees for $source');
        }
        final combined = sources.putIfAbsent(source, () => <int, bool>{});
        for (final line in lines.entries) {
          combined[line.key] = (combined[line.key] ?? false) || line.value;
        }
        source = null;
      }
    }
    if (source != null) throw const FormatException('Unterminated record');
  }
  return {
    for (final source in sources.entries)
      source.key: (
        found: source.value.length,
        hit: source.value.values.where((hit) => hit).length,
      ),
  };
}

Map<String, ({int found, int hit})> parseCoverage(List<String> lines) {
  return mergeCoverageReports([lines]);
}

List<String> evaluateCoverage(
  Map<String, ({int found, int hit})> records,
  List<CoverageRequirement> required,
) {
  final failures = <String>[];
  for (final requirement in required) {
    final matches = records.entries.where(
      (entry) => entry.key.endsWith(requirement.pathSuffix),
    );
    if (matches.isEmpty) {
      failures.add('${requirement.pathSuffix} has no coverage record');
      continue;
    }
    final record = matches.single.value;
    final percent = record.found == 0 ? 0 : 100 * record.hit / record.found;
    if (percent + 0.0001 < requirement.minimumPercent) {
      failures.add(
        '${requirement.pathSuffix} is ${percent.toStringAsFixed(2)}%; '
        'requires ${requirement.minimumPercent.toStringAsFixed(0)}%',
      );
    }
  }
  return failures;
}
