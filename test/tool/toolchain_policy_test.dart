import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/verify_toolchain_policy.dart';

void main() {
  final policy =
      jsonDecode(File('tool/toolchain_policy.json').readAsStringSync())
          as Map<String, dynamic>;
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final wrapper = File(
    'android/gradle/wrapper/gradle-wrapper.properties',
  ).readAsStringSync();

  test('checked-in Android declarations agree with central policy', () {
    expect(verifyAndroidDeclarations(policy, gradle, wrapper), isEmpty);
  });

  for (final key in [
    'compileSdk',
    'targetSdk',
    'minSdk',
    'ndk',
    'gradle',
    'gradleDistributionSha256',
    'gradleNetworkTimeoutMillis',
    'androidAbi',
    'javaBytecode',
  ]) {
    test('rejects drift in $key', () {
      final changed = {...policy, key: 'unexpected'};
      expect(verifyAndroidDeclarations(changed, gradle, wrapper), isNotEmpty);
    });
  }

  test('rejects extra ABI and duplicate SDK declarations', () {
    expect(
      verifyAndroidDeclarations(
        policy,
        gradle.replaceFirst(
          'listOf("arm64-v8a")',
          'listOf("arm64-v8a", "x86_64")',
        ),
        wrapper,
      ),
      isNotEmpty,
    );
    expect(
      verifyAndroidDeclarations(
        policy,
        '$gradle\ncompileSdk = ${policy['compileSdk']}\n',
        wrapper,
      ),
      isNotEmpty,
    );
  });

  test('rejects alternate wrapper source even with matching version', () {
    expect(
      verifyAndroidDeclarations(
        policy,
        gradle,
        wrapper.replaceFirst('services.gradle.org', 'untrusted.invalid'),
      ),
      isNotEmpty,
    );
  });

  const fixtureHash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final pinnedPolicy = {...policy, 'gradleDistributionSha256': fixtureHash};
  final fixtureWrapper = wrapper.replaceAll(
    RegExp(r'^distributionSha256Sum=.*\r?\n?', multiLine: true),
    '',
  );
  final pinnedWrapper =
      '${fixtureWrapper.trim()}\ndistributionSha256Sum=$fixtureHash\n';

  test('accepts one matching publisher checksum', () {
    expect(
      verifyAndroidDeclarations(pinnedPolicy, gradle, pinnedWrapper),
      isEmpty,
    );
  });

  for (final invalid in <String, String>{
    'missing': fixtureWrapper,
    'mismatched': pinnedWrapper.replaceFirst(fixtureHash, 'b' * 64),
    'duplicate':
        '$pinnedWrapper'
        'distributionSha256Sum=$fixtureHash\n',
  }.entries) {
    test('rejects ${invalid.key} distribution checksum', () {
      expect(
        verifyAndroidDeclarations(pinnedPolicy, gradle, invalid.value),
        isNotEmpty,
      );
    });
  }

  test('rejects missing or malformed publisher checksum authority', () {
    for (final invalid in <Object?>[null, '', 'a' * 63, 'z' * 64, 123]) {
      expect(
        verifyAndroidDeclarations(
          {...pinnedPolicy, 'gradleDistributionSha256': invalid},
          gradle,
          pinnedWrapper,
        ),
        isNotEmpty,
      );
    }
  });

  test('rejects an absent bootstrap network deadline', () {
    expect(
      verifyAndroidDeclarations(
        policy,
        gradle,
        wrapper.replaceAll(
          RegExp(r'^networkTimeout=.*\r?\n?', multiLine: true),
          '',
        ),
      ),
      isNotEmpty,
    );
  });

  test('rejects invalid bootstrap deadline authority', () {
    for (final invalid in <Object?>[null, 0, -1, '10000']) {
      expect(
        verifyAndroidDeclarations(
          {...policy, 'gradleNetworkTimeoutMillis': invalid},
          gradle,
          wrapper,
        ),
        isNotEmpty,
      );
    }
  });

  test('checked-in bootstrap matches publisher authority', () async {
    expect(
      await verifyGradleBootstrap(
        policy,
        File('android/gradle/wrapper/gradle-wrapper.jar'),
        File('tool/VerifyGradleBootstrap.java'),
      ),
      isEmpty,
    );
  });

  test(
    'checkout retains all wrapper entrypoints and executable Unix mode',
    () async {
      const paths = [
        'android/gradlew',
        'android/gradlew.bat',
        'android/gradle/wrapper/gradle-wrapper.jar',
        'android/gradle/wrapper/gradle-wrapper.properties',
      ];
      final result = await Process.run('git', [
        'ls-files',
        '--stage',
        '--',
        ...paths,
      ]);
      expect(result.exitCode, 0);
      final entries = (result.stdout as String)
          .split('\n')
          .map((line) => line.trim());
      for (final path in paths) {
        expect(
          entries.where((entry) => entry.endsWith('\t$path')),
          hasLength(1),
          reason: '$path must survive a clean checkout',
        );
      }
      expect(
        entries.singleWhere((entry) => entry.endsWith('\tandroid/gradlew')),
        startsWith('100755 '),
      );
    },
  );

  test(
    'Unix wrapper checkout enforces LF independently of host Git defaults',
    () async {
      final result = await Process.run('git', [
        'check-attr',
        '--cached',
        'eol',
        '--',
        'android/gradlew',
      ]);
      expect(result.exitCode, 0);
      expect((result.stdout as String).trim(), 'android/gradlew: eol: lf');
    },
  );

  group('bootstrap content identity', () {
    late Directory fixture;
    late File jar;
    final checker = File('tool/VerifyGradleBootstrap.java');
    final authority = {
      ...policy,
      'gradleWrapperSha256':
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    };
    setUp(() async {
      fixture = await Directory.systemTemp.createTemp(
        'vitalis_bootstrap_identity_',
      );
      jar = File('${fixture.path}/fixture.jar');
      await jar.writeAsString('abc');
    });
    tearDown(() async => fixture.delete(recursive: true));
    test('accepts exact content hash independent of filename', () async {
      expect(await verifyGradleBootstrap(authority, jar, checker), isEmpty);
    });
    test('rejects replaced content', () async {
      await jar.writeAsString('abd');
      expect(await verifyGradleBootstrap(authority, jar, checker), isNotEmpty);
    });
    test('rejects a missing bootstrap', () async {
      await jar.delete();
      expect(await verifyGradleBootstrap(authority, jar, checker), isNotEmpty);
    });
    test('rejects absent or malformed hash authority', () async {
      for (final invalid in <Object?>[null, '', 'g' * 64]) {
        expect(
          await verifyGradleBootstrap(
            {...authority, 'gradleWrapperSha256': invalid},
            jar,
            checker,
          ),
          isNotEmpty,
        );
      }
    });
  });
}
