import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:llm_llamacpp/src/runtime_session_reservation.dart';

void main() {
  test(
    'recovery retains an enclosing session until its action finishes',
    () async {
      final session = RuntimeSessionReservation();
      final owner = Object();
      session.acquire(owner, RuntimeOperationKind.verification);
      session.requireOwnedRecovery(owner);
      expect(
        await session.recover(owner, () async => true),
        RuntimeRecoveryOutcome.recovered,
      );
      expect(session.isHeld, isTrue);
      expect(session.kind, RuntimeOperationKind.verification);
      expect(
        () => session.acquire(Object(), RuntimeOperationKind.interactive),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      session.finish(owner, terminationConfirmed: true);
      expect(session.isHeld, isFalse);
    },
  );

  test(
    'session exit during recovery does not retain an abandoned lease',
    () async {
      final session = RuntimeSessionReservation();
      final owner = Object();
      final acknowledgement = Completer<bool>();
      session.acquire(owner, RuntimeOperationKind.verification);
      session.requireOwnedRecovery(owner);
      final recovering = session.recover(owner, () => acknowledgement.future);
      expect(
        () => session.finish(owner, terminationConfirmed: false),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      acknowledgement.complete(true);
      expect(await recovering, RuntimeRecoveryOutcome.recovered);
      expect(session.isHeld, isFalse);
      session.acquire(Object(), RuntimeOperationKind.interactive);
    },
  );

  test(
    'failed idle context cleanup can be recovered only by its owner',
    () async {
      final session = RuntimeSessionReservation();
      final owner = Object();
      session.claimContext(owner);
      expect(session.requireOwnedRecovery(Object()), isFalse);
      expect(session.snapshot().requiresRecovery, isFalse);
      expect(session.requireOwnedRecovery(owner), isTrue);
      expect(session.snapshot().kind, RuntimeOperationKind.disposal);
      expect(session.snapshot().requiresRecovery, isTrue);
      await expectLater(
        session.recover(Object(), () async => true),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      final result = await session.recover(owner, () async {
        session.releaseContext(owner);
        return true;
      });
      expect(result, RuntimeRecoveryOutcome.recovered);
      expect(session.snapshot().hasRetainedContext, isFalse);
      expect(session.requireOwnedRecovery(owner), isFalse);
    },
  );
  test('snapshot separates retained context from a reserved operation', () {
    final session = RuntimeSessionReservation();
    final owner = Object();
    session.claimContext(owner);
    final retained = session.snapshot();
    expect(retained.hasRetainedContext, isTrue);
    expect(retained.ownerId, isNull);
    expect(retained.kind, isNull);
    expect(retained.hasNativeWork, isFalse);
    session.acquire(owner, RuntimeOperationKind.tuning);
    final active = session.snapshot(
      nativeRequestId: 7,
      cancellationRequested: true,
    );
    expect(active.ownerId, retained.contextOwnerId);
    expect(active.kind, RuntimeOperationKind.tuning);
    expect(active.hasNativeWork, isTrue);
    expect(active.cancellationRequested, isTrue);
    expect(active.sessionGeneration, greaterThan(retained.sessionGeneration));
    session.finish(owner, terminationConfirmed: true);
    expect(
      active.kind,
      RuntimeOperationKind.tuning,
      reason: 'Old snapshot must not mutate',
    );
    expect(session.snapshot().ownerId, isNull);
    expect(session.snapshot().contextOwnerId, retained.contextOwnerId);
    session.releaseContext(owner);
    expect(session.snapshot().hasRetainedContext, isFalse);
    session.claimContext(owner);
    expect(
      session.snapshot().sessionGeneration,
      greaterThan(active.sessionGeneration),
    );
  });
  test('snapshot classifies owner-scoped native activity', () {
    final session = RuntimeSessionReservation();
    final owner = Object();
    session.claimContext(owner);

    final active = session.snapshot(
      nativeRequestId: 11,
      activeOwner: owner,
      activeKind: RuntimeOperationKind.tuning,
    );

    expect(active.state, RuntimeReservationState.reserved);
    expect(active.kind, RuntimeOperationKind.tuning);
    expect(active.ownerId, active.contextOwnerId);
    expect(active.nativeRequestId, 11);
    expect(active.hasNativeWork, isTrue);
    final idle = session.snapshot();
    expect(idle.state, RuntimeReservationState.idle);
    expect(idle.kind, isNull);
    expect(idle.ownerId, isNull);
    expect(idle.hasRetainedContext, isTrue);
  });
  test('snapshot distinguishes initialization wait and quarantine', () {
    final session = RuntimeSessionReservation();
    expect(session.snapshot(initializationPending: true).hasNativeWork, isTrue);
    expect(
      session.snapshot(initializationRecoveryRequired: true).requiresRecovery,
      isTrue,
    );
    expect(session.snapshot().requiresRecovery, isFalse);
    final cancelled = session.snapshot(cancellationRecoveryRequired: true);
    expect(cancelled.cancellationRecoveryRequired, isTrue);
    expect(cancelled.initializationRecoveryRequired, isFalse);
    expect(cancelled.requiresRecovery, isTrue);
    expect(session.snapshot().cancellationRecoveryRequired, isFalse);
  });
  test('anonymous legacy context is retained, not falsely unowned', () {
    final session = RuntimeSessionReservation();
    session.claimContext(null);
    expect(session.snapshot().hasRetainedContext, isTrue);
    expect(session.snapshot().contextOwnerId, isNull);
    expect(
      () => session.claimContext(Object()),
      throwsA(isA<InferenceRuntimeBusy>()),
    );
  });
  test(
    'snapshot preserves recovery outcome and never exposes owner objects',
    () async {
      final session = RuntimeSessionReservation();
      final owner = Object();
      session.acquire(owner, RuntimeOperationKind.verification);
      session.finish(owner, terminationConfirmed: false);
      final quarantined = session.snapshot();
      expect(quarantined.requiresRecovery, isTrue);
      await session.recover(owner, () async => false);
      expect(
        session.snapshot().recoveryOutcome,
        RuntimeRecoveryOutcome.terminationUnconfirmed,
      );
      await session.recover(owner, () async => true);
      expect(
        session.snapshot().recoveryOutcome,
        RuntimeRecoveryOutcome.recovered,
      );
      expect(session.snapshot().requiresRecovery, isFalse);
      session.acquire(Object(), RuntimeOperationKind.interactive);
      expect(session.snapshot().ownerId, isNot(quarantined.ownerId));
      expect(session.snapshot().recoveryOutcome, isNull);
    },
  );
  test(
    'context survives request lease and blocks other owners until release',
    () {
      final reservation = RuntimeSessionReservation();
      final first = Object();
      final second = Object();
      reservation.claimContext(first);
      reservation.acquire(first, RuntimeOperationKind.interactive);
      reservation.finish(first, terminationConfirmed: true);
      expect(reservation.ownsContext(first), isTrue);
      expect(
        () => reservation.claimContext(second),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      expect(
        () => reservation.acquire(second, RuntimeOperationKind.verification),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      expect(
        () => reservation.releaseContext(second),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      reservation.releaseContext(first);
      reservation.claimContext(second);
      expect(reservation.ownsContext(second), isTrue);
    },
  );
  late RuntimeSessionReservation session;
  late Object owner;
  setUp(() {
    session = RuntimeSessionReservation();
    owner = Object();
  });

  void requireRecovery() {
    session.acquire(owner, RuntimeOperationKind.verification);
    session.finish(owner, terminationConfirmed: false);
  }

  test('normal completion releases identity and operation kind', () {
    session.acquire(owner, RuntimeOperationKind.tuning);
    expect(session.kind, RuntimeOperationKind.tuning);
    expect(session.canAccess(Object()), isFalse);
    session.finish(owner, terminationConfirmed: true);
    expect(session.state, RuntimeReservationState.idle);
    expect(session.kind, isNull);
    expect(session.canAccess(Object()), isTrue);
  });

  test('competing finish cannot release another owner', () {
    session.acquire(owner, RuntimeOperationKind.interactive);
    expect(
      () => session.finish(Object(), terminationConfirmed: true),
      throwsA(isA<InferenceRuntimeBusy>()),
    );
    expect(session.state, RuntimeReservationState.reserved);
  });

  test('unconfirmed termination blocks every new reservation', () {
    requireRecovery();
    expect(session.state, RuntimeReservationState.recoveryRequired);
    expect(
      () => session.acquire(owner, RuntimeOperationKind.interactive),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    expect(
      () => session.acquire(Object(), RuntimeOperationKind.verification),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    expect(
      () => session.finish(owner, terminationConfirmed: true),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    expect(session.state, RuntimeReservationState.recoveryRequired);
  });

  test('second acquisition cannot replace an active owner', () {
    session.acquire(owner, RuntimeOperationKind.interactive);
    expect(
      () => session.acquire(Object(), RuntimeOperationKind.tuning),
      throwsA(isA<InferenceRuntimeBusy>()),
    );
    expect(session.kind, RuntimeOperationKind.interactive);
    expect(session.canAccess(owner), isTrue);
  });

  test(
    'only the owner can recover and duplicate calls share cleanup',
    () async {
      requireRecovery();
      var attempts = 0;
      final terminated = Completer<bool>();
      Future<bool> cleanup() {
        attempts++;
        return terminated.future;
      }

      await expectLater(
        session.recover(Object(), cleanup),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      expect(attempts, 0);
      final first = session.recover(owner, cleanup);
      final second = session.recover(owner, cleanup);
      expect(identical(first, second), isTrue);
      expect(session.state, RuntimeReservationState.recovering);
      expect(session.isHeld, isTrue);
      expect(attempts, 1);
      terminated.complete(true);
      expect(await first, RuntimeRecoveryOutcome.recovered);
      expect(session.state, RuntimeReservationState.idle);
      session.acquire(Object(), RuntimeOperationKind.interactive);
    },
  );

  for (final throws in [false, true]) {
    test('unsuccessful recovery retains ownership (throws: $throws)', () async {
      requireRecovery();
      final result = await session.recover(owner, () async {
        if (throws) throw StateError('private fixture detail');
        return false;
      });
      expect(result, RuntimeRecoveryOutcome.terminationUnconfirmed);
      expect(session.state, RuntimeReservationState.recoveryRequired);
      expect(session.canAccess(Object()), isFalse);
      expect(
        await session.recover(owner, () async => true),
        RuntimeRecoveryOutcome.recovered,
      );
    });
  }

  test('recovery cannot interrupt a healthy reservation', () async {
    session.acquire(owner, RuntimeOperationKind.warmup);
    await expectLater(
      session.recover(owner, () async => true),
      throwsA(isA<InferenceRuntimeBusy>()),
    );
    expect(session.state, RuntimeReservationState.reserved);
  });
}
