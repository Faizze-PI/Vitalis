import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/runtime_owner_recovery_guard.dart';

void main() {
  test(
    'recovery guard rejects ineligible work without executing cleanup',
    () async {
      final guard = RuntimeOwnerRecoveryGuard();
      var calls = 0;
      await expectLater(
        guard.run(
          recoveryAllowed: false,
          recover: () async {
            calls++;
            return RuntimeRecoveryOutcome.recovered;
          },
        ),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      expect(calls, 0);
      expect(guard.isRecovering, isFalse);
    },
  );
  test('reentrant callers share a single owned attempt', () async {
    final guard = RuntimeOwnerRecoveryGuard();
    final native = Completer<RuntimeRecoveryOutcome>();
    Future<RuntimeRecoveryOutcome>? nested;
    final attempt = guard.run(
      recoveryAllowed: true,
      recover: () {
        nested = guard.run(
          recoveryAllowed: false,
          recover: () => throw StateError('must not run'),
        );
        return native.future;
      },
    );
    expect(nested, same(attempt));
    expect(guard.isRecovering, isTrue);
    expect(guard.pending, same(attempt));
    native.complete(RuntimeRecoveryOutcome.recovered);
    expect(await attempt, RuntimeRecoveryOutcome.recovered);
    expect(guard.isRecovering, isFalse);
    expect(guard.pending, isNull);
  });
  for (final throws in [false, true]) {
    test(
      'unconfirmed outcome permits a later acknowledged attempt (throws: $throws)',
      () async {
        final guard = RuntimeOwnerRecoveryGuard();
        final failed = await guard.run(
          recoveryAllowed: true,
          recover: () async {
            if (throws) throw StateError('private transport detail');
            return RuntimeRecoveryOutcome.terminationUnconfirmed;
          },
        );
        expect(failed, RuntimeRecoveryOutcome.terminationUnconfirmed);
        expect(guard.isRecovering, isFalse);
        expect(
          await guard.run(
            recoveryAllowed: true,
            recover: () async => RuntimeRecoveryOutcome.recovered,
          ),
          RuntimeRecoveryOutcome.recovered,
        );
      },
    );
  }
}
