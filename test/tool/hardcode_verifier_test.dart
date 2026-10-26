import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_hardcode_register.dart' as verifier;

void main() {
  late Directory root;
  late File register;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vitalis_hardcodes_');
    register = File('${root.path}/register.csv');
    await register.writeAsString(
      'id,subsystem,current_constraint,impact,disposition,replacement,verification,status\n'
      'HC-001,test,value,impact,CENTRALIZE_POLICY,policy,test,IMPLEMENTED\n',
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('accepts a registered behavioral constant', () async {
    final source = File('${root.path}/valid.dart');
    await source.writeAsString(
      "const timeout = Duration(seconds: 3); // hardcode: HC-001\n",
    );

    expect(
      verifier.verifyHardcodes(
        registerPath: register.path,
        dartTargets: [source],
      ),
      isEmpty,
    );
  });

  test('rejects unclassified and unknown constants', () async {
    final source = File('${root.path}/invalid.dart');
    await source.writeAsString(
      "const retries = 3;\n"
      "const timeoutSeconds = 4; // hardcode: HC-999\n",
    );

    final failures = verifier.verifyHardcodes(
      registerPath: register.path,
      dartTargets: [source],
    );

    expect(failures, hasLength(2));
    expect(failures.first, contains('unclassified'));
    expect(failures.last, contains('unknown HC-999'));
  });

  test('rejects an explicitly required source that is missing', () {
    final source = File('${root.path}/required.dart');
    final failures = verifier.verifyHardcodes(
      registerPath: register.path,
      dartTargets: [source],
    );
    expect(failures, hasLength(1));
    expect(failures.single, contains(source.path));
    expect(failures.single, contains('missing'));
  });

  Future<void> createSource(String path) async {
    final file = File('${root.path}/$path');
    await file.create(recursive: true);
    await file.writeAsString('const retries = 3; // hardcode: HC-001\n');
  }

  test('discovery includes app vendor and native build-hook sources', () async {
    await createSource('lib/runtime.dart');
    await createSource('third_party/llm_llamacpp/lib/runtime.dart');
    await createSource('third_party/llm_llamacpp/hook/build.dart');
    final failures = <String>[];
    final files = verifier.discoverDartHardcodeSources(root, failures);
    expect(failures, isEmpty);
    expect(
      files.map((file) => file.absolute.uri),
      unorderedEquals([
        File('${root.path}/lib/runtime.dart').absolute.uri,
        File(
          '${root.path}/third_party/llm_llamacpp/lib/runtime.dart',
        ).absolute.uri,
        File(
          '${root.path}/third_party/llm_llamacpp/hook/build.dart',
        ).absolute.uri,
      ]),
    );
  });

  test('discovery rejects absent source roots and build hook', () {
    final failures = <String>[];
    verifier.discoverDartHardcodeSources(root, failures);
    expect(failures, hasLength(3));
    expect(failures.any((failure) => failure.contains('lib')), isTrue);
    expect(
      failures.any((failure) => failure.contains('hook/build.dart')),
      isTrue,
    );
  });

  test('empty source roots do not satisfy discovery', () async {
    await Directory('${root.path}/lib').create(recursive: true);
    await Directory(
      '${root.path}/third_party/llm_llamacpp/lib',
    ).create(recursive: true);
    await createSource('third_party/llm_llamacpp/hook/build.dart');
    final failures = <String>[];
    verifier.discoverDartHardcodeSources(root, failures);
    expect(failures, hasLength(2));
    expect(failures.every((failure) => failure.contains('empty')), isTrue);
  });

  test(
    'generated-only vendor sources cannot masquerade as maintained coverage',
    () async {
      await createSource('lib/runtime.dart');
      await createSource(
        'third_party/llm_llamacpp/lib/src/bindings/generated.dart',
      );
      await createSource('third_party/llm_llamacpp/hook/build.dart');
      final failures = <String>[];
      verifier.discoverDartHardcodeSources(root, failures);
      expect(failures, hasLength(1));
      expect(failures.single, contains('third_party/llm_llamacpp/lib'));
    },
  );

  test('removing a previously verified source cannot produce a pass', () async {
    final source = File('${root.path}/removed.dart');
    await source.writeAsString('const retries = 3; // hardcode: HC-001\n');
    expect(
      verifier.verifyHardcodes(
        registerPath: register.path,
        dartTargets: [source],
      ),
      isEmpty,
    );
    await source.delete();
    expect(
      verifier.verifyHardcodes(
        registerPath: register.path,
        dartTargets: [source],
      ),
      isNotEmpty,
    );
  });

  test('rejects malformed duplicate and incomplete register rows', () async {
    await register.writeAsString(
      'id,subsystem,current_constraint,impact,disposition,replacement,verification,status\n'
      'HC-001,test,value,impact,INVALID,,,PENDING\n'
      'HC-001,test,value,impact,CENTRALIZE_POLICY,policy,test,PENDING\n',
    );

    final failures = verifier.verifyHardcodes(
      registerPath: register.path,
      dartTargets: const [],
    );

    expect(
      failures.any((value) => value.contains('unknown disposition')),
      isTrue,
    );
    expect(failures.any((value) => value.contains('must name')), isTrue);
    expect(failures.any((value) => value.contains('Duplicate')), isTrue);
  });

  test('Java policy classes and arithmetic constants are not exempt', () async {
    final source = File('${root.path}/TransferPolicy.java');
    await source.writeAsString('''
class TransferPolicy {
  static final long RETRY_MILLIS = 2 * 1000;
}
''');
    final failures = verifier.verifyHardcodes(
      registerPath: register.path,
      dartTargets: const [],
      javaTargets: [source],
    );
    expect(failures, hasLength(1));
    expect(failures.single, contains('RETRY_MILLIS'));
    expect(failures.single, contains('unclassified'));
  });

  test(
    'Java parser rejects unknown IDs but ignores commented declarations',
    () async {
      final source = File('${root.path}/Limits.java');
      await source.writeAsString('''
class Limits {
  // static final int NOT_CODE = 5;
  static final int KNOWN = 5; // hardcode: HC-001
  static final int UNKNOWN = 6; // hardcode: HC-999
}
''');
      final failures = verifier.verifyHardcodes(
        registerPath: register.path,
        dartTargets: const [],
        javaTargets: [source],
      );
      expect(failures, hasLength(1));
      expect(failures.single, contains('unknown HC-999'));
    },
  );

  test('Java strings cannot forge a trailing disposition comment', () async {
    final source = File('${root.path}/Keys.java');
    await source.writeAsString('''
class Keys {
  static final String KEY = "// hardcode: HC-001";
}
''');
    final failures = verifier.verifyHardcodes(
      registerPath: register.path,
      dartTargets: const [],
      javaTargets: [source],
    );
    expect(failures, hasLength(1));
    expect(failures.single, contains('unclassified'));
  });

  test('required Java source removal fails instead of shrinking the audit', () {
    final failures = verifier.verifyHardcodes(
      registerPath: register.path,
      dartTargets: const [],
      javaTargets: [File('${root.path}/Missing.java')],
    );
    expect(failures, hasLength(1));
    expect(failures.single, contains('missing'));
  });

  test('Java syntax errors cannot masquerade as an empty inventory', () async {
    final source = File('${root.path}/Broken.java');
    await source.writeAsString('class Broken { static final int LIMIT = ; }');
    final failures = verifier.verifyHardcodes(
      registerPath: register.path,
      dartTargets: const [],
      javaTargets: [source],
    );
    expect(failures, hasLength(1));
    expect(failures.single, contains('Java hardcode parser failed'));
  });

  test(
    'Java audit handles spaced paths without executing initializers',
    () async {
      final source = File('${root.path}/path with spaces/Identity.java');
      await source.create(recursive: true);
      await source.writeAsString('''
class Identity {
  static { if (true) throw new AssertionError("must not execute"); }
  static final String CHANNEL = "registered"; // hardcode: HC-001
}
''');
      expect(
        verifier.verifyHardcodes(
          registerPath: register.path,
          dartTargets: const [],
          javaTargets: [source],
        ),
        isEmpty,
      );
    },
  );

  test('Java discovery rejects absent and empty application roots', () async {
    final missing = <String>[];
    expect(verifier.discoverJavaHardcodeSources(root, missing), isEmpty);
    expect(missing.single, contains('missing'));
    final directory = Directory(
      '${root.path}/android/app/src/main/java/com/vitalis/vitalis_app',
    );
    await directory.create(recursive: true);
    final empty = <String>[];
    expect(verifier.discoverJavaHardcodeSources(root, empty), isEmpty);
    expect(empty.single, contains('empty'));
    final source = File('${directory.path}/Bridge.java');
    await source.writeAsString('class Bridge {}');
    final failures = <String>[];
    expect(
      verifier.discoverJavaHardcodeSources(root, failures).map((f) => f.uri),
      [source.uri],
    );
    expect(failures, isEmpty);
  });
}
