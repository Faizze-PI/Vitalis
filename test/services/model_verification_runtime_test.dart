import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/services/model_verification_runtime.dart';

void main() {
  test(
    'scope close joins active shutdown and drains the remaining actor',
    () async {
      final runtime = ModelVerificationRuntime();
      final owner = _Owner()..closeAcknowledgement = Completer<void>();
      final actionStarted = Completer<void>();
      final actionFinished = Completer<void>();
      final operation = runtime.run(owner, () async {
        actionStarted.complete();
        await actionFinished.future;
      });
      await actionStarted.future;
      final close = runtime.close();
      expect(identical(close, runtime.close()), isTrue);
      expect(
        runtime.checkAvailable,
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
      var closed = false;
      close.then((_) => closed = true);
      await owner.closeStarted.future;
      expect(closed, isFalse);
      owner.closeAcknowledgement!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(
        closed,
        isFalse,
        reason: 'Terminating the context must also drain its actor',
      );
      actionFinished.complete();
      await operation;
      await close;
      expect(owner.closeCalls, 1);
      expect(closed, isTrue);
      await expectLater(
        runtime.run(_Owner(), () async {}),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
    },
  );

  test(
    'idle scope shutdown is shared and does not start native work',
    () async {
      final runtime = ModelVerificationRuntime();
      final first = runtime.close();
      expect(identical(first, runtime.close()), isTrue);
      await first;
      expect(
        runtime.checkAvailable,
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
    },
  );

  test(
    'failed scope close stays failed; recovery never revives disposal',
    () async {
      final runtime = ModelVerificationRuntime();
      final owner = _Owner()..failClose = true;
      await expectLater(
        runtime.run(owner, () async {}),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      final close = runtime.close();
      await expectLater(close, throwsA(isA<InferenceRecoveryRequired>()));
      expect(identical(close, runtime.close()), isTrue);
      expect(
        await runtime.recoverOwnedCleanup(),
        RuntimeRecoveryOutcome.recovered,
      );
      expect(
        runtime.checkAvailable,
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
      await expectLater(close, throwsA(isA<InferenceRecoveryRequired>()));
    },
  );

  for (final outcome in RuntimeRecoveryOutcome.values) {
    test(
      'scope close joins recovery before retiring (outcome: $outcome)',
      () async {
        final runtime = ModelVerificationRuntime();
        final owner = _Owner()
          ..failClose = true
          ..outcome = outcome
          ..recoveryAcknowledgement = Completer<void>();
        await expectLater(
          runtime.run(owner, () async {}),
          throwsA(isA<InferenceRecoveryRequired>()),
        );
        final recovery = runtime.recoverOwnedCleanup();
        final close = runtime.close();
        final observedClose = close.then<Object?>(
          (_) => null,
          onError: (Object error) => error,
        );
        owner.recoveryAcknowledgement!.complete();
        expect(await recovery, outcome);
        if (outcome == RuntimeRecoveryOutcome.recovered) {
          expect(await observedClose, isNull);
        } else {
          expect(await observedClose, isA<InferenceRecoveryRequired>());
        }
        expect(owner.recoveryCalls, 1);
      },
    );
  }

  test(
    'active verification rejects competing work through close acknowledgement',
    () async {
      final runtime = ModelVerificationRuntime();
      final owner = _Owner()..closeAcknowledgement = Completer<void>();
      final work = runtime.run(owner, () async => 'result');
      await owner.closeStarted.future;
      expect(runtime.requiresRecovery, isFalse);
      expect(runtime.isRecovering, isFalse);
      expect(runtime.checkAvailable, throwsA(isA<InferenceRuntimeBusy>()));
      final competitor = _Owner();
      await expectLater(
        runtime.run(competitor, () async {}),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      expect(competitor.closeCalls, 0);
      owner.closeAcknowledgement!.complete();
      expect(await work, 'result');
      runtime.checkAvailable();
      expect(owner.kind, RuntimeOperationKind.verification);
      expect(owner.closeCalls, 1);
    },
  );

  test('rejected admission never closes a foreign owner', () async {
    final runtime = ModelVerificationRuntime();
    final owner = _Owner()..busy = true;
    await expectLater(
      runtime.run(owner, () async {}),
      throwsA(isA<InferenceRuntimeBusy>()),
    );
    expect(owner.closeCalls, 0);
    runtime.checkAvailable();
    await expectLater(
      runtime.recoverOwnedCleanup(),
      throwsA(isA<InferenceRuntimeBusy>()),
    );
  });

  test(
    'action error still awaits close without quarantining a healthy owner',
    () async {
      final runtime = ModelVerificationRuntime();
      final owner = _Owner();
      await expectLater(
        runtime.run(owner, () async => throw const FormatException('fixture')),
        throwsFormatException,
      );
      expect(owner.closeCalls, 1);
      expect(runtime.requiresRecovery, isFalse);
      runtime.checkAvailable();
    },
  );

  test(
    'failed close retains owner through shared recovery and confirmed handoff',
    () async {
      final runtime = ModelVerificationRuntime();
      final owner = _Owner()..failClose = true;
      await expectLater(
        runtime.run(owner, () async {}),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      expect(runtime.requiresRecovery, isTrue);
      expect(runtime.checkAvailable, throwsA(isA<InferenceRecoveryRequired>()));
      owner.recoveryAcknowledgement = Completer<void>();
      final recovery = runtime.recoverOwnedCleanup();
      final joined = runtime.recoverOwnedCleanup();
      expect(identical(recovery, joined), isTrue);
      expect(runtime.isRecovering, isTrue);
      expect(runtime.checkAvailable, throwsA(isA<InferenceRuntimeBusy>()));
      owner.recoveryAcknowledgement!.complete();
      expect(await recovery, RuntimeRecoveryOutcome.recovered);
      expect(owner.recoveryCalls, 1);
      expect(runtime.requiresRecovery, isFalse);
      await runtime.run(_Owner(), () async {});
    },
  );

  for (final throws in [false, true]) {
    test(
      'unconfirmed recovery retains verification quarantine (throws: $throws)',
      () async {
        final runtime = ModelVerificationRuntime();
        final owner = _Owner()
          ..failClose = true
          ..failRecovery = throws
          ..outcome = RuntimeRecoveryOutcome.terminationUnconfirmed;
        await expectLater(
          runtime.run(owner, () async {}),
          throwsA(isA<InferenceRecoveryRequired>()),
        );
        expect(
          await runtime.recoverOwnedCleanup(),
          RuntimeRecoveryOutcome.terminationUnconfirmed,
        );
        expect(runtime.requiresRecovery, isTrue);
        expect(
          runtime.checkAvailable,
          throwsA(isA<InferenceRecoveryRequired>()),
        );
        owner.failRecovery = false;
        owner.outcome = RuntimeRecoveryOutcome.recovered;
        expect(
          await runtime.recoverOwnedCleanup(),
          RuntimeRecoveryOutcome.recovered,
        );
        runtime.checkAvailable();
      },
    );
  }
}

final class _Owner implements LlamaCppChatRepository {
  bool busy = false;
  bool failClose = false;
  bool failRecovery = false;
  int closeCalls = 0;
  int recoveryCalls = 0;
  RuntimeOperationKind? kind;
  RuntimeRecoveryOutcome outcome = RuntimeRecoveryOutcome.recovered;
  final closeStarted = Completer<void>();
  Completer<void>? closeAcknowledgement;
  Completer<void>? recoveryAcknowledgement;
  Future<void>? _closeFuture;

  @override
  Future<T> withExclusiveSession<T>(
    Future<T> Function() action, {
    RuntimeOperationKind kind = RuntimeOperationKind.interactive,
  }) async {
    if (busy) throw InferenceRuntimeBusy();
    this.kind = kind;
    return action();
  }

  @override
  Future<void> close() => _closeFuture ??= _finishClose();

  Future<void> _finishClose() async {
    closeCalls++;
    if (!closeStarted.isCompleted) closeStarted.complete();
    await closeAcknowledgement?.future;
    if (failClose) throw StateError('controlled close failure');
  }

  @override
  Future<RuntimeRecoveryOutcome> recoverAfterClose() async {
    recoveryCalls++;
    await recoveryAcknowledgement?.future;
    if (failRecovery) throw StateError('controlled recovery failure');
    return outcome;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
