import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../tool/generation_lock.dart';
import '../../tool/verify_gate_environment.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('vitalis gate '));
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'exclusive acquisition rejects competing writer; owner can release',
    () async {
      final file = File('${root.path}/generation.lock');
      final first = GenerationLock(file);
      final second = GenerationLock(file);
      final token = await first.acquire();
      expect(await second.recognizes(token), isTrue);
      expect(await second.recognizes('foreign'), isFalse);
      await expectLater(second.acquire(), throwsA(isA<FileSystemException>()));
      await expectLater(second.release(), throwsStateError);
      await first.release();
      await second.acquire();
      await second.release();
    },
  );

  test(
    'incomplete interrupted lock stays blocked, never automatically stolen',
    () async {
      final file = File('${root.path}/generation.lock')..writeAsStringSync('');
      final lease = GenerationLock(file);
      expect(await lease.recognizes('stale'), isFalse);
      await expectLater(lease.acquire(), throwsA(isA<FileSystemException>()));
      expect(file.existsSync(), isTrue);
    },
  );

  Map<String, String> fixture() {
    final sdk = '${root.path}/sdk';
    File('$sdk/platforms/android-36/android.jar')..createSync(recursive: true);
    File('$sdk/ndk/28.2/source.properties')
      ..createSync(recursive: true)
      ..writeAsStringSync('Pkg.Revision = 28.2\n');
    return {
      'ANDROID_HOME': sdk,
      'PUB_CACHE': '${root.path}/cache/pub',
      'GRADLE_USER_HOME': '${root.path}/cache/gradle',
    };
  }

  const policy = {'compileSdk': 36, 'ndk': '28.2'};

  test('installed matching SDK and in-workspace caches pass', () {
    expect(verifyEnvironment(policy, root.path, fixture(), ''), isEmpty);
  });
  test('equivalent cache path spellings do not conflict', () {
    final env = fixture();
    expect(
      verifyEnvironment(policy, root.path, {
        ...env,
        'VITALIS_PUB_CACHE': '${env['PUB_CACHE']}/',
        'VITALIS_GRADLE_CACHE': '${env['GRADLE_USER_HOME']}/.',
      }, ''),
      isEmpty,
    );
  });
  test('directory comparison preserves distinct paths and spaces', () {
    expect(sameDirectoryPath('${root.path}/pub', '${root.path}/pub/.'), isTrue);
    expect(
      sameDirectoryPath('${root.path}/pub', '${root.path}/other'),
      isFalse,
    );
    if (Platform.isWindows) {
      expect(
        sameDirectoryPath(
          '${root.path}/pub'.replaceAll(r'\', '/'),
          '${root.path}/pub'.toUpperCase().replaceAll('/', r'\'),
        ),
        isTrue,
      );
    }
  });
  test('equivalent parent-traversal override remains rejected', () {
    final env = fixture();
    expect(
      verifyEnvironment(policy, root.path, {
        ...env,
        'VITALIS_PUB_CACHE': '${env['PUB_CACHE']}/../pub',
      }, ''),
      isNotEmpty,
    );
  });
  test('rejects SDK environment and local-properties conflicts', () {
    final env = fixture();
    expect(
      verifyEnvironment(policy, root.path, {
        ...env,
        'ANDROID_SDK_ROOT': '${root.path}/missing',
      }, ''),
      isNotEmpty,
    );
    expect(
      verifyEnvironment(policy, root.path, env, 'sdk.dir=${root.path}/missing'),
      isNotEmpty,
    );
  });
  test('rejects cache escape and conflicting override', () {
    final env = fixture();
    expect(
      verifyEnvironment(policy, root.path, {
        ...env,
        'PUB_CACHE': Directory.systemTemp.path,
      }, ''),
      isNotEmpty,
    );
    expect(
      verifyEnvironment(policy, root.path, {
        ...env,
        'VITALIS_PUB_CACHE': '${root.path}/other',
      }, ''),
      isNotEmpty,
    );
  });
  test('rejects parent traversal and checkout root as cache', () {
    expect(
      withinWorkspace(root.path, '${root.path}/missing/../../outside'),
      isFalse,
    );
    expect(withinWorkspace(root.path, root.path), isFalse);
  });
  test('rejects missing platform and mismatched installed NDK', () {
    final env = fixture();
    File(
      '${env['ANDROID_HOME']}/platforms/android-36/android.jar',
    ).deleteSync();
    File(
      '${env['ANDROID_HOME']}/ndk/28.2/source.properties',
    ).writeAsStringSync('Pkg.Revision = 28.20');
    expect(verifyEnvironment(policy, root.path, env, ''), hasLength(2));
  });
}
