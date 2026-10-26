import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';

void main() {
  test('target leases deduplicate aliases and release after failure', () async {
    final first = LlamaCppChatRepository.modelFileIdentity('lease-target.gguf');
    final alias = LlamaCppChatRepository.modelFileIdentity(
      './lease-target.gguf',
    );
    expect(first, alias);
    await expectLater(
      LlamaCppChatRepository.withModelFilesMutation([first, alias], () async {
        await expectLater(
          LlamaCppChatRepository.withModelFilesMutation([first], () async {}),
          throwsA(isA<InferenceRuntimeBusy>()),
        );
        await LlamaCppChatRepository.withModelFilesMutation([
          'unrelated-lease-target.gguf',
        ], () async {});
        throw StateError('fixture mutation failure');
      }),
      throwsStateError,
    );
    await LlamaCppChatRepository.withModelFilesMutation([first], () async {});
  });

  test('multi-target contention releases already acquired leases', () async {
    await LlamaCppChatRepository.withModelFilesMutation(
      ['blocked-target.gguf'],
      () async {
        await expectLater(
          LlamaCppChatRepository.withModelFilesMutation([
            'first-target.gguf',
            'blocked-target.gguf',
          ], () async {}),
          throwsA(isA<InferenceRuntimeBusy>()),
        );
        await LlamaCppChatRepository.withModelFilesMutation([
          'first-target.gguf',
        ], () async {});
      },
    );
  });
  test(
    'file mutation reservation rejects preparation until it settles',
    () async {
      final competitor = LlamaCppChatRepository.withModelPath('unused.gguf');
      try {
        await LlamaCppChatRepository.withUnloadedRuntime(() async {
          await expectLater(
            competitor.prepare(),
            throwsA(isA<InferenceRuntimeBusy>()),
          );
          await expectLater(
            competitor.withExclusiveSession(() async {}),
            throwsA(isA<InferenceRuntimeBusy>()),
          );
          await expectLater(
            LlamaCppChatRepository.withUnloadedRuntime(() async {}),
            throwsA(isA<InferenceRuntimeBusy>()),
          );
        });
        var admitted = false;
        await competitor.withExclusiveSession(() async {
          admitted = true;
        });
        expect(admitted, isTrue);
      } finally {
        await competitor.close();
      }
    },
  );

  test('file mutation error releases only its finished reservation', () async {
    await expectLater(
      LlamaCppChatRepository.withUnloadedRuntime(() async {
        throw StateError('fixture file failure');
      }),
      throwsStateError,
    );
    var admitted = false;
    await LlamaCppChatRepository.withUnloadedRuntime(() async {
      admitted = true;
    });
    expect(admitted, isTrue);
  });
  test(
    'invalid repository shutdown policy fails the shared close future',
    () async {
      final repository = _DelayedCloseRepository(
        shutdownTimeout: const Duration(microseconds: -1),
      );
      final closing = repository.close();
      await expectLater(closing, throwsArgumentError);
      expect(repository.close(), same(closing));
      expect(repository.cancelCalls, 0);
      expect(repository.cleanupFailed, isTrue);
      expect(repository.isDisposed, isTrue);
    },
  );
  testWidgets('repository close deadline retains unacknowledged shutdown', (
    tester,
  ) async {
    final repository = _DelayedCloseRepository(shutdownTimeout: Duration.zero);
    Object? failure;
    final closing = repository.close();
    final observing = closing.then<void>(
      (_) {},
      onError: (Object error) {
        failure = error;
      },
    );
    try {
      await tester.pump(const Duration(minutes: 2));
      expect(failure, isA<InferenceRecoveryRequired>());
      expect(repository.cleanupFailed, isTrue);
      expect(repository.isDisposed, isTrue);
      expect(repository.close(), same(closing));
      expect(repository.cancelCalls, 1);
      repository.ack.complete();
      await tester.pump();
      expect(
        repository.cleanupFailed,
        isTrue,
        reason: 'Late acknowledgement cannot clear failed close',
      );
    } finally {
      if (!repository.ack.isCompleted) repository.ack.complete();
      await tester.pump();
      await observing;
    }
  });

  test(
    'close shares acknowledgement and rejects new work immediately',
    () async {
      final repository = _DelayedCloseRepository();
      final first = repository.close();
      final second = repository.close();
      expect(identical(first, second), isTrue);
      expect(repository.isDisposed, isTrue);
      expect(repository.cancelCalls, 1);
      var finished = false;
      unawaited(
        first.then((_) {
          finished = true;
        }),
      );
      await Future<void>.value();
      expect(finished, isFalse);
      await expectLater(
        repository.prepare(),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
      await expectLater(
        repository.countChatTokens([]),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
      await expectLater(
        repository.loadModel('unused.gguf'),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
      await expectLater(
        repository
            .streamChat(
              'test',
              messages: [LLMMessage(role: LLMRole.user, content: 'test')],
            )
            .drain<void>(),
        throwsA(isA<InferenceRepositoryDisposed>()),
      );
      repository.ack.complete();
      await first;
      repository.dispose();
      expect(repository.cancelCalls, 1);
    },
  );

  test('failed disposal stays observable through close', () async {
    final repository = _DelayedCloseRepository();
    repository.dispose();
    final result = expectLater(repository.close(), throwsStateError);
    repository.ack.completeError(StateError('fixture cancellation failure'));
    await result;
    expect(repository.cleanupFailed, isTrue);
    expect(repository.isDisposed, isTrue);
    expect(
      await repository.recoverAfterClose(),
      RuntimeRecoveryOutcome.terminationUnconfirmed,
    );
    expect(repository.cleanupFailed, isTrue);
  });
  test('disposed repository cannot acquire a new session', () async {
    final repository = LlamaCppChatRepository.withModelPath('unused.gguf');
    repository.dispose();
    var entered = false;
    await expectLater(
      repository.withExclusiveSession(() async {
        entered = true;
      }),
      throwsStateError,
    );
    expect(entered, isFalse);
  });
  test(
    'reserved context rejects competing operations without native loading',
    () async {
      final owner = LlamaCppChatRepository.withModelPath('unused-owner.gguf');
      final other = LlamaCppChatRepository.withModelPath('unused-other.gguf');
      final entered = Completer<void>();
      final release = Completer<void>();
      final session = owner.withExclusiveSession(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final captured = owner.operationSnapshot;
      expect(captured.state, RuntimeReservationState.reserved);
      expect(captured.kind, RuntimeOperationKind.interactive);
      expect(captured.ownerId, isNotNull);
      expect(captured.hasNativeWork, isFalse);
      await expectLater(other.prepare(), throwsStateError);
      await expectLater(other.cancelActiveInference(), throwsStateError);
      await expectLater(other.unloadPersistentModel(), throwsStateError);
      await expectLater(other.countChatTokens([]), throwsStateError);
      await expectLater(
        other.withExclusiveSession(() async {}),
        throwsStateError,
      );
      // A rejected repository's disposal must not cancel the reserved session.
      other.dispose();
      release.complete();
      await session;
      expect(owner.operationSnapshot.ownerId, isNull);
      expect(captured.ownerId, isNotNull);
      expect(
        await LlamaCppChatRepository.withModelPath(
          'fresh.gguf',
        ).withExclusiveSession(() async => 'released'),
        'released',
      );
    },
  );

  test(
    'failed action with no native requests releases the reservation',
    () async {
      final first = LlamaCppChatRepository.withModelPath('unused-first.gguf');
      final second = LlamaCppChatRepository.withModelPath('unused-second.gguf');
      await expectLater(
        first.withExclusiveSession<void>(() async {
          throw StateError('fixture');
        }),
        throwsStateError,
      );
      expect(await second.withExclusiveSession(() async => true), isTrue);
    },
  );
}

class _DelayedCloseRepository extends LlamaCppChatRepository {
  _DelayedCloseRepository({
    Duration shutdownTimeout = RuntimeWatchdogDefaults.noProgressTimeout,
  }) : super.withModelPath('unused.gguf', shutdownTimeout: shutdownTimeout);
  final ack = Completer<void>();
  int cancelCalls = 0;
  @override
  Future<void> cancelActiveInference() {
    cancelCalls++;
    return ack.future;
  }
}
