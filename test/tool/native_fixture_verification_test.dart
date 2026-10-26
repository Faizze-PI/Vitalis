import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../third_party/llm_llamacpp/test/verified_model_fixture.dart';

void main() {
  // SHA-256 standard public test vector for ASCII abc, not a model authority.
  const expected =
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';
  late Directory temporary;
  late File fixture;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('vitalis_fixture_guard_');
    fixture = File('${temporary.path}/fixture.bin');
    await fixture.writeAsString('abc');
  });
  tearDown(() => temporary.delete(recursive: true));

  test('missing fixture path fails rather than skipping', () async {
    await expectLater(
      verifiedModelFixture(
        environment: {'VITALIS_TEST_MODEL_SHA256': expected},
      ),
      throwsStateError,
    );
  });
  test(
    'missing expected authority fails rather than trusting the file',
    () async {
      await expectLater(
        verifiedModelFixture(environment: {'VITALIS_TEST_MODEL': fixture.path}),
        throwsStateError,
      );
    },
  );
  test('malformed expected authority fails', () async {
    await expectLater(
      verifiedModelFixture(
        environment: {
          'VITALIS_TEST_MODEL': fixture.path,
          'VITALIS_TEST_MODEL_SHA256': 'not-a-hash',
        },
      ),
      throwsStateError,
    );
  });
  test('unreadable fixture fails with a redacted diagnostic', () async {
    await fixture.delete();
    await expectLater(
      verifiedModelFixture(
        environment: {
          'VITALIS_TEST_MODEL': fixture.path,
          'VITALIS_TEST_MODEL_SHA256': expected,
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'redacted code',
          'nativeFixtureUnreadable',
        ),
      ),
    );
  });
  test('mismatched content cannot become an accepted fixture', () async {
    await fixture.writeAsString('changed');
    await expectLater(
      verifiedModelFixture(
        environment: {
          'VITALIS_TEST_MODEL': fixture.path,
          'VITALIS_TEST_MODEL_SHA256': expected,
        },
      ),
      throwsStateError,
    );
  });
  test('matching content passes with case-insensitive supplied hash', () async {
    expect(
      await verifiedModelFixture(
        environment: {
          'VITALIS_TEST_MODEL': fixture.path,
          'VITALIS_TEST_MODEL_SHA256': expected.toUpperCase(),
        },
      ),
      fixture.path,
    );
  });
}
