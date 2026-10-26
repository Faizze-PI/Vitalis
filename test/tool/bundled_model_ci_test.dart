import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:yaml/yaml.dart';

import '../../tool/export_bundled_model_manifest.dart';

void main() {
  test('CI fixture export uses the application manifest authority', () {
    final manifest = jsonDecode(jsonEncode(bundledModelFixtureManifest()));
    expect(manifest['fileName'], BundledModelManifest.fileName);
    expect(manifest['sha256'], BundledModelManifest.sha256);
    expect(manifest['url'], BundledModelManifest.downloadUrl);
    expect(manifest['byteSize'], BundledModelManifest.byteSize);
    expect(manifest['revision'], BundledModelManifest.revision);
  });

  test('CI derives fixture identity instead of duplicating pinned values', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();
    expect(workflow, contains('dart tool/export_bundled_model_manifest.dart'));
    expect(workflow, isNot(contains(BundledModelManifest.sha256)));
    expect(workflow, isNot(contains(BundledModelManifest.revision)));
    expect(workflow, isNot(contains(BundledModelManifest.fileName)));
    expect(workflow, contains('find test_native'));
    expect(workflow, contains("-name '*_test.dart'"));
    expect(
      File('test_native/model_registry_probe_test.dart').existsSync(),
      isTrue,
    );
  });
  test('every native model gate receives the mandatory manifest fixture', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();
    final parsed = loadYaml(workflow) as Map;
    final steps = parsed['jobs']['native-text-runtime']['steps'] as List;
    final nativeSteps = steps.whereType<Map>().where((step) {
      final run = '${step['run']}';
      return run.contains('test test_native/') ||
          run.contains(r'test "${cases[@]}"') ||
          run.contains('test test/vitalis_text_runtime_gate_test.dart');
    }).toList();
    expect(nativeSteps, hasLength(3));
    final textGate = nativeSteps.singleWhere(
      (step) =>
          '${step['run']}'.contains('vitalis_text_runtime_gate_test.dart'),
    );
    expect(
      (textGate['env'] as Map)['VITALIS_TEST_MODEL_SHA256'],
      r'${{ env.MODEL_SHA256 }}',
      reason: 'Vendored text gate must verify manifest hash itself',
    );
    final discovered = nativeSteps.singleWhere(
      (step) => '${step['run']}'.contains('find test_native'),
    );
    expect(discovered['run'], contains("-name '*_test.dart'"));
    expect(
      discovered['run'],
      contains('! -name helper_cleanup_fault_test.dart'),
    );
    expect(
      nativeSteps.any(
        (step) => '${step['run']}'.contains(
          'test test_native/helper_cleanup_fault_test.dart',
        ),
      ),
      isTrue,
    );
    for (final required in [
      'model_registry_probe_test.dart',
      'benchmark_workload_test.dart',
      'prompt_thread_configuration_test.dart',
    ]) {
      expect(File('test_native/$required').existsSync(), isTrue);
    }
    for (final step in nativeSteps) {
      expect(
        (step['env'] as Map)['VITALIS_TEST_MODEL'],
        r'${{ env.MODEL_PATH }}',
        reason: 'Native gate lost its mandatory fixture environment',
      );
    }
  });
}
