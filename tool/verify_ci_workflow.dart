import 'dart:io';

import 'package:yaml/yaml.dart';

// Local product contracts, not a replacement for GitHub's workflow validator.
List<String> validateWorkflow(String text) {
  final failures = <String>[];
  dynamic document;
  try {
    document = loadYaml(text);
  } on YamlException {
    return ['Workflow YAML cannot be parsed'];
  }
  if (document is! Map || document['jobs'] is! Map) {
    return ['Workflow jobs must be a mapping'];
  }
  final jobs = document['jobs'] as Map;
  final windowsHost = jobs['windows-android-host'];
  final windowsSteps = windowsHost is Map ? windowsHost['steps'] : null;
  if (windowsHost is! Map ||
      windowsHost['runs-on'] != 'windows-latest' ||
      windowsSteps is! List ||
      !windowsSteps.whereType<Map>().any(
        (step) =>
            step['shell'] == 'pwsh' &&
            '${step['run']}'.contains('dart tool/test_java_socket_policy.dart'),
      )) {
    failures.add('Windows Android host must run its socket regression');
  }
  final analysisJob = jobs['analyze'];
  final analysisSteps = analysisJob is Map ? analysisJob['steps'] : null;
  var firstAnalysis = -1;
  var vendorPreparation = -1;
  if (analysisSteps is List) {
    for (var index = 0; index < analysisSteps.length; index++) {
      final step = analysisSteps[index];
      if (step is! Map) continue;
      final run = '${step['run'] ?? ''}';
      if (firstAnalysis < 0 && RegExp(r'\banalyze\s').hasMatch(run)) {
        firstAnalysis = index;
      }
      if (step['working-directory'] == 'third_party/llm_llamacpp' &&
          !step.containsKey('if') &&
          run.contains('pub get --enforce-lockfile')) {
        vendorPreparation = index;
      }
    }
  }
  if (firstAnalysis < 0 ||
      vendorPreparation < 0 ||
      vendorPreparation >= firstAnalysis) {
    failures.add(
      'analyze: vendored locked dependencies must resolve before analysis',
    );
  }
  List<String> dependencies(dynamic job) {
    final needs = job is Map ? job['needs'] : null;
    if (needs is String) return [needs];
    if (needs is List && needs.every((value) => value is String)) {
      return needs.cast<String>();
    }
    return [];
  }

  String commands(String id) {
    final job = jobs[id];
    if (job is! Map || job['steps'] is! List) return '';
    return (job['steps'] as List)
        .whereType<Map>()
        .map((step) => step['run'] ?? '')
        .join('\n');
  }

  for (final entry in jobs.entries) {
    final job = entry.value;
    if (job is! Map || job['steps'] is! List) {
      failures.add('${entry.key}: steps must be a list');
      continue;
    }
    for (final step in job['steps'] as List) {
      if (step is! Map || step.containsKey('run') == step.containsKey('uses')) {
        failures.add(
          '${entry.key}: each step must have exactly one run or uses',
        );
      }
    }
    for (final needed in dependencies(job)) {
      if (!jobs.containsKey(needed) || needed == entry.key) {
        failures.add('${entry.key}: invalid dependency $needed');
      }
    }
  }
  for (final id in ['test', 'native-text-runtime']) {
    final command = commands(id);
    if (!command.contains('--coverage') ||
        !command.contains('--coverage-package=vitalis_app|llm_llamacpp') ||
        !command.contains('git rev-parse HEAD') ||
        !command.contains('cp coverage/lcov.info')) {
      failures.add('$id: missing coverage/source evidence collection');
    }
    final job = jobs[id];
    final steps = job is Map ? job['steps'] : null;
    final hasUpload =
        steps is List &&
        steps.whereType<Map>().any((step) {
          final settings = step['with'];
          return '${step['uses']}'.startsWith('actions/upload-artifact@') &&
              step['if'] == 'always()' &&
              settings is Map &&
              settings['if-no-files-found'] == 'error';
        });
    if (!hasUpload)
      failures.add('$id: missing failure-preserving artifact upload');
  }
  final native = commands('native-text-runtime');
  final nativeJob = jobs['native-text-runtime'];
  final nativeSteps = nativeJob is Map ? nativeJob['steps'] : null;
  final textFixtureVerified =
      nativeSteps is List &&
      nativeSteps.whereType<Map>().any((step) {
        final environment = step['env'];
        return '${step['run']}'.contains(
              'vitalis_text_runtime_gate_test.dart',
            ) &&
            environment is Map &&
            environment['VITALIS_TEST_MODEL_SHA256'] ==
                r'${{ env.MODEL_SHA256 }}';
      });
  if (!textFixtureVerified) {
    failures.add('Native text gate must verify the manifest fixture hash');
  }
  final normalModeIsExplicit =
      nativeSteps is List &&
      nativeSteps.whereType<Map>().any((step) {
        final run = '${step['run']}';
        return run.contains('find test_native') &&
            run.contains('--dart-define=VITALIS_RUNTIME_FAULT_TESTS=false') &&
            !run.contains('--dart-define=VITALIS_RUNTIME_FAULT_TESTS=true');
      });
  if (!normalModeIsExplicit) {
    failures.add(
      'Normal native matrix must explicitly disable test fault mode',
    );
  }
  if (nativeSteps is List) {
    final steps = nativeSteps.whereType<Map>().toList();
    final helperIndex = steps.indexWhere(
      (step) =>
          '${step['run']}'.contains('node tool/build_split_test_fixture.js'),
    );
    final matrixIndex = steps.indexWhere(
      (step) => '${step['run']}'.contains('find test_native'),
    );
    final env = matrixIndex < 0 ? null : steps[matrixIndex]['env'];
    if (helperIndex < 0 ||
        matrixIndex <= helperIndex ||
        env is! Map ||
        env['VITALIS_SPLIT_TEST_FIXTURE'] !=
            r'${{ env.VITALIS_SPLIT_TEST_FIXTURE }}') {
      failures.add(
        'Native split fixture must be provisioned and explicitly bound before its matrix',
      );
    }
  }
  if (!native.contains('find test_native') ||
      !native.contains('! -name helper_cleanup_fault_test.dart') ||
      !native.contains('--dart-define=VITALIS_RUNTIME_FAULT_TESTS=true') ||
      !native.contains('fault-lcov.info')) {
    failures.add('Native coverage must discover tests and isolate fault mode');
  }
  final coverage = commands('lifecycle-coverage');
  final coverageJob = jobs['lifecycle-coverage'];
  final coverageNeeds = dependencies(coverageJob).toSet();
  final coverageSteps = coverageJob is Map ? coverageJob['steps'] : null;
  final downloads = coverageSteps is List
      ? coverageSteps.whereType<Map>().where(
          (step) => '${step['uses']}'.startsWith('actions/download-artifact@'),
        )
      : <Map>[];
  final downloadedNames = downloads.map((step) {
    final settings = step['with'];
    return settings is Map ? settings['name'] : null;
  }).toSet();
  final windowsCoverage = commands('windows-android-host');
  final windowsUploads = windowsSteps is List
      ? windowsSteps.whereType<Map>().where((step) {
          final settings = step['with'];
          return '${step['uses']}'.startsWith('actions/upload-artifact@') &&
              step['if'] == 'always()' &&
              settings is Map &&
              settings['name'] == 'windows-storage-coverage' &&
              settings['if-no-files-found'] == 'error';
        })
      : <Map>[];
  if (!coverageNeeds.contains('windows-android-host') ||
      !downloadedNames.contains('windows-storage-coverage') ||
      windowsUploads.isEmpty ||
      !windowsCoverage.contains(
        'test/services/model_storage_preflight_test.dart',
      ) ||
      !windowsCoverage.contains('--coverage') ||
      !windowsCoverage.contains('.ci-evidence/windows-storage/source.txt') ||
      !windowsCoverage.contains('Copy-Item coverage/lcov.info') ||
      !coverage.contains('.ci-evidence/windows-storage/lcov.info') ||
      !coverage.contains(r'$(cat .ci-evidence/windows-storage/source.txt)')) {
    failures.add(
      'Lifecycle coverage must include same-source Windows storage evidence',
    );
  }
  for (final id in ['build-android', 'build-android-release']) {
    if (!dependencies(jobs[id]).contains('lifecycle-coverage')) {
      failures.add('$id: builds must wait for merged coverage qualification');
    }
  }
  if (!coverageNeeds.contains('test') ||
      !coverageNeeds.contains('native-text-runtime') ||
      !downloadedNames.containsAll([
        'root-test-evidence',
        'native-test-evidence',
      ])) {
    failures.add('Coverage must wait for and download both evidence artifacts');
  }
  if (!coverage.contains('--native-lifecycle') ||
      !coverage.contains('.ci-evidence/root/lcov.info') ||
      !coverage.contains('.ci-evidence/native/lcov.info') ||
      !coverage.contains('.ci-evidence/native/fault-lcov.info') ||
      !coverage.contains('root/source.txt') ||
      !coverage.contains('native/source.txt') ||
      !coverage.contains('GITHUB_SHA')) {
    failures.add(
      'Expanded coverage must consume matching root/native evidence',
    );
  }
  final aggregate = jobs['acceptance'];
  final androidJob = jobs['build-android'];
  final androidSteps = androidJob is Map ? androidJob['steps'] : null;
  final requiresTransferCoverage =
      androidSteps is List &&
      androidSteps.whereType<Map>().any(
        (step) =>
            '${step['run']}'.contains(':app:transferCoverageVerify') &&
            '${step['run']}'.contains('tool/generation_lock.dart') &&
            step['continue-on-error'] != true,
      );
  if (!requiresTransferCoverage) {
    failures.add(
      'Android build must require measured transfer recovery coverage',
    );
  }
  final retainsTransferEvidence =
      androidSteps is List &&
      androidSteps.whereType<Map>().any((step) {
        final settings = step['with'];
        return '${step['uses']}'.startsWith('actions/upload-artifact@') &&
            step['if'] == 'always()' &&
            settings is Map &&
            settings['name'] == 'android-transfer-evidence' &&
            settings['if-no-files-found'] == 'error' &&
            '${settings['path']}'.contains('build/app/reports/jacoco/') &&
            '${settings['path']}'.contains('build/app/test-results/') &&
            '${settings['path']}'.contains('.ci-evidence/android-transfer');
      });
  if (!retainsTransferEvidence) {
    failures.add('Android transfer evidence must be retained on failure');
  }
  final instrumentation = jobs['android-instrumentation'];
  final strategy = instrumentation is Map ? instrumentation['strategy'] : null;
  final matrix = strategy is Map ? strategy['matrix'] : null;
  final levels = matrix is Map ? matrix['api-level'] : null;
  final instrumentationSteps = instrumentation is Map
      ? instrumentation['steps']
      : null;
  final emulatorSteps = instrumentationSteps is List
      ? instrumentationSteps.whereType<Map>().where(
          (step) => '${step['uses']}'.startsWith(
            'reactivecircus/android-emulator-runner@',
          ),
        )
      : <Map>[];
  final firebaseSteps = instrumentationSteps is List
      ? instrumentationSteps.whereType<Map>().toList()
      : <Map>[];
  final firebaseRuns = firebaseSteps.where((step) {
    final run = '${step['run'] ?? ''}';
    return run.contains('gcloud firebase test android run') &&
        run.contains('--type=instrumentation') &&
        run.contains('model=MediumPhone.arm,version=28,') &&
        run.contains('model=MediumPhone.arm,version=35,') &&
        step['continue-on-error'] != true;
  }).isNotEmpty;
  final firebaseEvidence =
      firebaseSteps.any(
        (step) =>
            '${step['run']}'.contains(
              'tool/reporting/collect_firebase_xml.py',
            ) &&
            '${step['run']}'.contains('--api28 ') &&
            '${step['run']}'.contains('--api35 ') &&
            step['if'] == 'always()',
      ) &&
      firebaseSteps.any((step) {
        final settings = step['with'];
        return '${step['uses']}'.startsWith('actions/upload-artifact@') &&
            step['if'] == 'always()' &&
            settings is Map &&
            settings['name'] == 'firebase-instrumentation-results' &&
            settings['if-no-files-found'] == 'error' &&
            '${settings['path']}'.contains('.ci-evidence/firebase-results');
      });
  if (!firebaseRuns &&
      (levels is! List ||
          !levels.contains(28) ||
          !levels.whereType<int>().any((level) => level >= 34) ||
          strategy['fail-fast'] != false ||
          !emulatorSteps.any((step) {
            final settings = step['with'];
            return settings is Map &&
                settings['api-level'] == r'${{ matrix.api-level }}' &&
                settings['arch'] == 'arm64-v8a' &&
                settings['target'] == 'google_apis' &&
                '${settings['script']}'.contains('connectedDebugAndroidTest') &&
                step['continue-on-error'] != true;
          }))) {
    failures.add(
      'Android instrumentation must require API-28 and API-34+ arm64 runs',
    );
  }
  if (!firebaseEvidence &&
      (instrumentationSteps is! List ||
          !instrumentationSteps.whereType<Map>().any((step) {
            final settings = step['with'];
            return '${step['uses']}'.startsWith('actions/upload-artifact@') &&
                step['if'] == 'always()' &&
                settings is Map &&
                settings['name'] ==
                    r'android-instrumentation-${{ matrix.api-level }}' &&
                settings['if-no-files-found'] == 'error' &&
                '${settings['path']}'.contains(
                  'build/app/outputs/androidTest-results/',
                );
          }))) {
    failures.add(
      'Android instrumentation evidence must be retained per API on failure',
    );
  }
  final rootJob = jobs['test'];
  final rootSteps = rootJob is Map ? rootJob['steps'] : null;
  final rootMaps = rootSteps is List
      ? rootSteps.whereType<Map>().toList()
      : <Map>[];
  if (rootMaps.any(
    (step) => '${step['run']}'.contains('tool/verify_coverage.dart'),
  )) {
    failures.add('Root coverage must be evaluated after both host producers');
  }
  if (!rootMaps.any((step) {
    final run = '${step['run'] ?? ''}';
    final environment = step['env'];
    return run.contains('test test test_benchmarks') &&
        run.contains('--machine') &&
        run.contains('.ci-evidence/root/machine.log') &&
        environment is Map &&
        environment['VITALIS_VALIDATION_METRICS'] ==
            r'${{ github.workspace }}/.ci-evidence/root/metrics.jsonl';
  })) {
    failures.add(
      'Full qualification must record all root cases and storage measurements',
    );
  }
  if (!rootMaps.any(
    (step) =>
        step['if'] == 'always()' &&
        '${step['run']}'.contains('pip install') &&
        '${step['run']}'.contains('--require-hashes') &&
        '${step['run']}'.contains('tool/reporting/requirements.txt'),
  )) {
    failures.add(
      'Full qualification reporter dependencies must remain hash-pinned',
    );
  }
  if (!rootMaps.any(
    (step) =>
        step['if'] == 'always()' &&
        '${step['run']}'.contains(
          'python -B tool/reporting/validation_report.py',
        ) &&
        '${step['run']}'.contains('--directory .ci-evidence/root') &&
        '${step['run']}'.contains(r'--source "$GITHUB_SHA"'),
  )) {
    failures.add(
      'Full qualification must generate source-linked reports on failure',
    );
  }
  if (!rootMaps.any((step) {
    final settings = step['with'];
    return '${step['uses']}'.startsWith('actions/upload-artifact@') &&
        step['if'] == 'always()' &&
        settings is Map &&
        settings['name'] == 'VITALIS-Full-Qualification-Excel' &&
        settings['if-no-files-found'] == 'error' &&
        settings['retention-days'] == 30 &&
        '${settings['path']}'.contains('.ci-evidence/root/*.xlsx');
  })) {
    failures.add(
      'Full qualification must retain downloadable Excel evidence on failure',
    );
  }
  final needed = dependencies(aggregate).toSet();
  final aggregateSteps = aggregate is Map ? aggregate['steps'] : null;
  final readsActualResults =
      aggregateSteps is List &&
      aggregateSteps.whereType<Map>().any((step) {
        final environment = step['env'];
        return step['run'] == 'node tool/verify_ci_acceptance.js' &&
            environment is Map &&
            environment['REQUIRED_RESULTS'] == r'${{ toJSON(needs) }}';
      });
  final mandatory = jobs.keys.where(
    (id) => id != 'policy' && id != 'acceptance',
  );
  if (mandatory.any((id) => !needed.contains(id)) ||
      aggregate is! Map ||
      aggregate['if'] != 'always()' ||
      !readsActualResults ||
      !commands('acceptance').contains('node tool/verify_ci_acceptance.js')) {
    failures.add('Acceptance must reject any required non-success job');
  }
  return failures;
}

void main(List<String> arguments) {
  final file = File(
    arguments.isEmpty ? '.github/workflows/ci.yml' : arguments.single,
  );
  final failures = validateWorkflow(file.readAsStringSync());
  if (failures.isNotEmpty) {
    stderr.writeln(failures.join('\n'));
    exitCode = 1;
  } else {
    stdout.writeln('CI YAML and local evidence/dependency contracts pass');
  }
}
