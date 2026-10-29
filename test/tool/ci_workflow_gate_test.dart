import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_ci_workflow.dart';

void main() {
  final source = File('.github/workflows/ci.yml').readAsStringSync();

  test('maintained CI satisfies local evidence and dependency contracts', () {
    expect(validateWorkflow(source), isEmpty);
  });

  test('Android emulator gate requires support-floor and UIDT coverage', () {
    for (final missing in [
      source.replaceAll('version=35,', 'version=34,'),
      source.replaceAll('version=28,', 'version=29,'),
      source.replaceAll('model=MediumPhone.arm,', 'model=MediumPhone.x86,'),
    ]) {
      expect(
        validateWorkflow(missing),
        contains(
          'Android instrumentation must require API-28 and API-34+ arm64 runs',
        ),
      );
    }
  });

  test('Android emulator results must be retained per API on failure', () {
    final missing = source.replaceAll(
      'name: firebase-instrumentation-results',
      'name: unrelated-emulator-results',
    );
    expect(
      validateWorkflow(missing),
      contains(
        'Android instrumentation evidence must be retained per API on failure',
      ),
    );
  });

  test('Android build cannot omit measured transfer recovery coverage', () {
    final missing = source.replaceAll(
      ':app:transferCoverageVerify',
      ':app:testDebugUnitTest',
    );
    expect(
      validateWorkflow(missing),
      contains(
        'Android build must require measured transfer recovery coverage',
      ),
    );
  });

  test('Android transfer coverage evidence must survive failed gates', () {
    final missing = source.replaceAll(
      'name: android-transfer-evidence',
      'name: unrelated-transfer-artifact',
    );
    expect(
      validateWorkflow(missing),
      contains('Android transfer evidence must be retained on failure'),
    );
  });

  test('malformed nested safety step is rejected', () {
    final malformed = source.replaceFirst(
      '      - name: Collect complete native lifecycle coverage',
      '        - name: Collect complete native lifecycle coverage',
    );
    expect(malformed, isNot(source));
    expect(
      validateWorkflow(malformed),
      contains('Workflow YAML cannot be parsed'),
    );
  });

  test('missing native coverage cannot fall back to root-only gate', () {
    final missing = source.replaceAll('--native-lifecycle', '');
    expect(validateWorkflow(missing), isNotEmpty);
  });

  test('normal matrix cannot accidentally enable fault mode', () {
    final faulty = source.replaceAll(
      '--dart-define=VITALIS_RUNTIME_FAULT_TESTS=false',
      '--dart-define=VITALIS_RUNTIME_FAULT_TESTS=true',
    );
    expect(validateWorkflow(faulty), isNotEmpty);
  });

  test('native text gate cannot omit manifest hash authority', () {
    final missing = source.replaceAll(
      'VITALIS_TEST_MODEL_SHA256: \${{ env.MODEL_SHA256 }}',
      'VITALIS_TEST_MODEL_SHA256: untrusted',
    );
    expect(validateWorkflow(missing), isNotEmpty);
  });

  test('coverage must wait for its native producer', () {
    final missing = source.replaceFirst(
      'needs: [policy, test, native-text-runtime, windows-android-host]',
      'needs: [policy, test]',
    );
    expect(missing, isNot(source));
    expect(validateWorkflow(missing), isNotEmpty);
  });

  test('coverage must download its native artifact', () {
    final missing = source.replaceAll(
      'name: native-test-evidence',
      'name: unrelated-artifact',
    );
    expect(validateWorkflow(missing), isNotEmpty);
  });

  test('missing coverage package scope is rejected', () {
    final missing = source.replaceAll(
      '--coverage-package=vitalis_app|llm_llamacpp',
      '',
    );
    expect(validateWorkflow(missing), isNotEmpty);
  });

  test('missing failed-run artifact retention is rejected', () {
    final missing = source.replaceAll(
      'if-no-files-found: error',
      'if-no-files-found: warn',
    );
    expect(validateWorkflow(missing), isNotEmpty);
  });

  test('matching-source evidence is mandatory', () {
    final missing = source.replaceAll(
      'native/source.txt',
      'native/unchecked.txt',
    );
    expect(validateWorkflow(missing), isNotEmpty);
  });

  test('required jobs cannot be omitted from aggregate acceptance', () {
    final omitted = source.replaceFirst(
      'needs: [analyze, test, native-text-runtime, lifecycle-coverage,',
      'needs: [analyze, test, native-text-runtime,',
    );
    expect(omitted, isNot(source));
    expect(validateWorkflow(omitted), isNotEmpty);
  });

  test('non-success statuses cannot be accepted optimistically', () {
    final permissive = source.replaceAll(
      'node tool/verify_ci_acceptance.js',
      'echo success',
    );
    expect(validateWorkflow(permissive), isNotEmpty);
  });

  test('aggregate acceptance must read actual job results', () {
    final fabricated = source.replaceAll(r'${{ toJSON(needs) }}', '{}');
    expect(validateWorkflow(fabricated), isNotEmpty);
  });
}
