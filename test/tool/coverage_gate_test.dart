import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_coverage.dart' as gate;

void main() {
  test('configured template components cannot evade native coverage gate', () {
    const paths = [
      'lib/src/native_template_applier.dart',
      'lib/src/verified_thinking_templates.dart',
    ];
    final required = gate
        .selectedRequirements(includeNativeLifecycle: true)
        .where((entry) => paths.contains(entry.pathSuffix))
        .toList();
    expect(gate.evaluateCoverage({}, required), hasLength(2));
    expect(
      gate.evaluateCoverage({
        for (final path in paths) path: (found: 100, hit: 89),
      }, required),
      hasLength(2),
    );
    expect(
      gate.evaluateCoverage({
        for (final path in paths) path: (found: 100, hit: 90),
      }, required),
      isEmpty,
    );
  });

  test(
    'storage preflight requires measured coverage and rejects missing data',
    () {
      const path = 'lib/services/model_storage_preflight.dart';
      final selected = gate.requirements
          .where((r) => r.pathSuffix == path)
          .toList();
      expect(selected, hasLength(1));
      expect(gate.evaluateCoverage({}, selected), hasLength(1));
      expect(
        gate.evaluateCoverage({path: (found: 100, hit: 89)}, selected),
        hasLength(1),
      );
      expect(
        gate.evaluateCoverage({path: (found: 100, hit: 90)}, selected),
        isEmpty,
      );
    },
  );

  test(
    'installation recovery components require measured 90 percent coverage',
    () {
      for (final path in [
        'lib/database/installation_journal_schema.dart',
        'lib/database/model_installation_journal.dart',
        'lib/database/model_installation_projection.dart',
        'lib/models/model_installation.dart',
        'lib/services/model_installation_promoter.dart',
        'lib/models/imported_model_file.dart',
        'lib/models/restoration_artifact.dart',
        'lib/services/model_shard_restorer.dart',
        'lib/services/model_shard_staging.dart',
        'lib/services/model_download_staging.dart',
        'lib/services/native_transfer_stop.dart',
      ]) {
        final requirement = gate.requirements.singleWhere(
          (r) => r.pathSuffix == path,
        );
        expect(requirement.minimumPercent, 90);
        expect(gate.evaluateCoverage({}, [requirement]), hasLength(1));
        expect(
          gate.evaluateCoverage({path: (found: 100, hit: 89)}, [requirement]),
          hasLength(1),
        );
        expect(
          gate.evaluateCoverage({path: (found: 100, hit: 90)}, [requirement]),
          isEmpty,
        );
      }
    },
  );

  test(
    'native lifecycle scope is explicit and adds no duplicate requirements',
    () {
      final root = gate.selectedRequirements();
      final selected = gate.selectedRequirements(includeNativeLifecycle: true);
      final expectedPaths = {
        ...root.map((entry) => entry.pathSuffix),
        ...gate.nativeLifecycleRequirements.map((entry) => entry.pathSuffix),
      };
      expect(selected.map((entry) => entry.pathSuffix).toSet(), expectedPaths);
      expect(selected, hasLength(expectedPaths.length));
      expect(
        root.map((entry) => entry.pathSuffix).toSet(),
        hasLength(root.length),
      );
      expect(
        selected
            .singleWhere(
              (entry) =>
                  entry.pathSuffix ==
                  'lib/services/model_verification_runtime.dart',
            )
            .minimumPercent,
        90,
      );
      expect(
        gate.evaluateCoverage({}, gate.nativeLifecycleRequirements),
        hasLength(7),
      );
    },
  );

  test(
    'supporting preference and download lifecycle components cannot be missing',
    () {
      for (final path in [
        'lib/providers/theme_provider.dart',
        'lib/services/model_downloader.dart',
        'lib/services/model_download_service.dart',
      ]) {
        final required = gate.requirements.singleWhere(
          (entry) => entry.pathSuffix == path,
        );
        expect(required.minimumPercent, 80);
        expect(gate.evaluateCoverage({}, [required]), hasLength(1));
        expect(
          gate.evaluateCoverage({path: (found: 100, hit: 79)}, [required]),
          hasLength(1),
        );
        expect(
          gate.evaluateCoverage({path: (found: 100, hit: 80)}, [required]),
          isEmpty,
        );
      }
    },
  );

  test('native lifecycle gate requires 90 percent in every component', () {
    Map<String, ({int found, int hit})> records(int hit) => {
      for (final required in gate.nativeLifecycleRequirements)
        required.pathSuffix: (found: 100, hit: hit),
    };
    expect(
      gate.evaluateCoverage(records(89), gate.nativeLifecycleRequirements),
      hasLength(gate.nativeLifecycleRequirements.length),
    );
    expect(
      gate.evaluateCoverage(records(90), gate.nativeLifecycleRequirements),
      isEmpty,
    );
  });

  test('multiple reports union line hits without double counting', () {
    final records = gate.mergeCoverageReports([
      [r'SF:repo\lib\a.dart', 'DA:1,0', 'DA:2,3', 'LF:2', 'end_of_record'],
      [
        'SF:repo/lib/a.dart',
        'DA:1,1',
        'DA:2,0',
        'DA:3,0',
        'LF:3',
        'end_of_record',
      ],
    ]);
    expect(records['repo/lib/a.dart'], (found: 3, hit: 2));
  });

  test(
    'summary totals cannot substitute for missing merge line identities',
    () {
      expect(
        () => gate.mergeCoverageReports([
          ['SF:repo/lib/a.dart', 'LF:10', 'LH:9', 'end_of_record'],
        ]),
        throwsFormatException,
      );
    },
  );

  test('merge rejects invalid line records and unfinished records', () {
    for (final record in ['DA:0,1', 'DA:1,-1', 'DA:no,1', 'DA:1']) {
      expect(
        () => gate.mergeCoverageReports([
          ['SF:repo/lib/a.dart', record, 'end_of_record'],
        ]),
        throwsFormatException,
      );
    }
    expect(
      () => gate.mergeCoverageReports([
        ['SF:repo/lib/a.dart', 'DA:1,1'],
      ]),
      throwsFormatException,
    );
  });

  test('coverage parser normalizes paths and records line totals', () {
    final records = gate.parseCoverage(const [
      r'SF:C:\work\lib\service.dart',
      'DA:1,1',
      'DA:2,1',
      'DA:3,1',
      'DA:4,1',
      'DA:5,1',
      'DA:6,1',
      'DA:7,1',
      'DA:8,1',
      'DA:9,1',
      'DA:10,0',
      'LF:10',
      'LH:9',
      'end_of_record',
    ]);

    expect(records.values.single, (found: 10, hit: 9));
    expect(records.keys.single, endsWith('lib/service.dart'));
  });

  test(
    'single report rejects missing identities and contradictory summaries',
    () {
      for (final lines in [
        ['SF:lib/a.dart', 'LF:10', 'LH:10', 'end_of_record'],
        ['SF:lib/a.dart', 'DA:1,0', 'LF:1', 'LH:1', 'end_of_record'],
        ['SF:lib/a.dart', 'DA:1,1', 'LF:1', 'LH:-1', 'end_of_record'],
        ['SF:lib/a.dart', 'DA:1,1'],
      ]) {
        expect(() => gate.parseCoverage(lines), throwsFormatException);
      }
    },
  );

  test('coverage gate reports missing and below-threshold files', () {
    final failures = gate.evaluateCoverage(
      {'repo/lib/a.dart': (found: 10, hit: 7)},
      const [
        gate.CoverageRequirement('lib/a.dart', 80),
        gate.CoverageRequirement('lib/b.dart', 80),
      ],
    );

    expect(failures, hasLength(2));
    expect(failures.first, contains('70.00%'));
    expect(failures.last, contains('no coverage record'));
  });
}
