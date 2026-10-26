import 'dart:io';

import 'verify_ci_workflow.dart';

// Runs without Flutter generation so the workflow contract itself can be checked
// before launching expensive native/build gates.
void main() {
  final source = File(
    '.github/workflows/ci.yml',
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final missingVendorPreparation = source.replaceAll(
    'working-directory: third_party/llm_llamacpp',
    'working-directory: .',
  );
  if (!validateWorkflow(missingVendorPreparation).contains(
    'analyze: vendored locked dependencies must resolve before analysis',
  )) {
    throw StateError(
      'Verifier accepts analysis without vendored dev dependencies',
    );
  }
  if (validateWorkflow(source).isNotEmpty) {
    throw StateError('Maintained workflow fails its contracts');
  }
  final mutations = <String, String>{
    'missing Windows Android host fixture': source.replaceAll(
      'dart tool/test_java_socket_policy.dart',
      'echo omitted socket fixture',
    ),
    'late vendored dependency preparation': source
        .replaceFirst(
          '      - name: Resolve vendored analysis dependencies\n'
              '        run: |\n'
              '          "\$GITHUB_WORKSPACE/tool/run_gate.sh" pub get --enforce-lockfile\n'
              '        working-directory: third_party/llm_llamacpp\n',
          '',
        )
        .replaceFirst(
          '  test:\n',
          '      - run: "pub get --enforce-lockfile"\n'
              '        working-directory: third_party/llm_llamacpp\n\n'
              '  test:\n',
        ),
    'missing split fixture provisioning': source.replaceAll(
      'node tool/build_split_test_fixture.js',
      'echo omitted split helper',
    ),
    'missing split fixture binding': source.replaceAll(
      'VITALIS_SPLIT_TEST_FIXTURE:',
      'UNBOUND_SPLIT_TEST_FIXTURE:',
    ),
    'missing text fixture authority': source.replaceAll(
      'VITALIS_TEST_MODEL_SHA256: \${{ env.MODEL_SHA256 }}',
      'VITALIS_TEST_MODEL_SHA256: untrusted',
    ),
    'normal matrix enables fault mode': source.replaceAll(
      '--dart-define=VITALIS_RUNTIME_FAULT_TESTS=false',
      '--dart-define=VITALIS_RUNTIME_FAULT_TESTS=true',
    ),
    'fabricated job results': source.replaceAll(r'${{ toJSON(needs) }}', '{}'),
    'missing producer dependency': source.replaceFirst(
      'needs: [policy, test, native-text-runtime]',
      'needs: [policy, test]',
    ),
    'missing native artifact': source.replaceAll(
      'name: native-test-evidence',
      'name: unrelated-artifact',
    ),
    'malformed nested step': source.replaceFirst(
      '      - name: Collect complete native lifecycle coverage',
      '        - name: Collect complete native lifecycle coverage',
    ),
    'root-only coverage': source.replaceAll('--native-lifecycle', ''),
    'missing package scope': source.replaceAll(
      '--coverage-package=vitalis_app|llm_llamacpp',
      '',
    ),
    'missing failed-run evidence': source.replaceAll(
      'if-no-files-found: error',
      'if-no-files-found: warn',
    ),
    'unchecked source': source.replaceAll(
      'native/source.txt',
      'native/unchecked.txt',
    ),
    'omitted required job': source.replaceFirst(
      'needs: [analyze, test, native-text-runtime, lifecycle-coverage,',
      'needs: [analyze, test, native-text-runtime,',
    ),
    'optimistic acceptance': source.replaceAll(
      'node tool/verify_ci_acceptance.js',
      'echo success',
    ),
  };
  for (final entry in mutations.entries) {
    if (entry.value == source || validateWorkflow(entry.value).isEmpty) {
      throw StateError('Verifier failed to reject ${entry.key}');
    }
  }
  stdout.writeln(
    'CI workflow self-test: valid fixture and ${mutations.length} rejected mutations',
  );
}
