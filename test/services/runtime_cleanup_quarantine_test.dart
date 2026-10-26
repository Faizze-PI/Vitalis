import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/src/runtime_cleanup_quarantine.dart';
import 'package:llm_llamacpp/src/runtime_cancellation_control.dart';
import 'package:llm_llamacpp/src/runtime_request_finalizer.dart';
import 'package:llm_llamacpp/src/runtime_session_reservation.dart';

void main() {
  test('owner acknowledgement retires only its own retained requests', () {
    final released = <int>[];
    final quarantine = RuntimeCleanupQuarantine(releaseHandle: released.add);
    expect(quarantine.firstRequestId, isNull);
    final owner = Object();
    final competitor = Object();
    quarantine.retain(7, owner);
    expect(quarantine.firstRequestId, 7);
    quarantine.retain(8, competitor);
    expect(quarantine.hasRequests, isTrue);
    expect(quarantine.contains(7), isTrue);
    expect(quarantine.canAccess(owner), isFalse);
    expect(quarantine.confirmOwnerUnload(owner), [7]);
    expect(released, [7]);
    expect(quarantine.canAccess(competitor), isTrue);
    expect(quarantine.confirmOwnerUnload(owner), isEmpty);
    quarantine.confirmOwnerUnload(competitor);
    expect(quarantine.hasRequests, isFalse);
  });

  test('identity cannot be reassigned and null owner is not a wildcard', () {
    final quarantine = RuntimeCleanupQuarantine(releaseHandle: (_) {});
    expect(() => quarantine.retain(-1, null), throwsStateError);
    quarantine.retain(7, null);
    quarantine.retain(7, null);
    expect(() => quarantine.retain(7, Object()), throwsStateError);
    expect(quarantine.canAccess(Object()), isFalse);
    expect(quarantine.confirmOwnerUnload(Object()), isEmpty);
    expect(quarantine.confirmOwnerUnload(null), [7]);
  });

  test(
    'failed handle retirement retains identity for another acknowledged retry',
    () {
      var blocked = true;
      final owner = Object();
      final quarantine = RuntimeCleanupQuarantine(
        releaseHandle: (_) {
          if (blocked) throw StateError('injected handle release failure');
        },
      );
      quarantine.retain(7, owner);
      expect(() => quarantine.confirmOwnerUnload(owner), throwsStateError);
      expect(quarantine.contains(7), isTrue);
      blocked = false;
      expect(quarantine.confirmOwnerUnload(owner), [7]);
    },
  );

  test(
    'cleanup failure retains reservation and control until owner recovery acknowledges',
    () async {
      final owner = Object();
      final competitor = Object();
      final reservation = RuntimeSessionReservation();
      reservation.acquire(owner, RuntimeOperationKind.interactive);
      reservation.claimContext(owner);
      final released = <int>[];
      final control = RuntimeCancellationControl(
        readMonotonicMicros: () => 1,
        requestCancel: (_) {},
        releaseHandle: released.add,
      );
      control.register(7);
      control.attachHandle(7, 123);
      final quarantine = RuntimeCleanupQuarantine(
        releaseHandle: control.finish,
      );
      var blocked = true;
      var published = 0;
      final finalizer = RuntimeRequestFinalizer(publish: (_) => published++);
      finalizer.add(RuntimeCleanupStep.cache, () {
        if (blocked) throw StateError('injected native cleanup failure');
      });
      expect(
        finalizer.finish(Object()),
        RuntimeCleanupOutcome.recoveryRequired,
      );
      quarantine.retain(7, owner);
      expect(reservation.requireOwnedRecovery(owner), isTrue);
      expect(reservation.canAccess(competitor), isFalse);
      expect(quarantine.canAccess(competitor), isFalse);
      expect(control.hasHandle(7), isTrue);
      expect(
        await reservation.recover(owner, () async => false),
        RuntimeRecoveryOutcome.terminationUnconfirmed,
      );
      expect(reservation.needsRecovery, isTrue);
      expect(released, isEmpty);
      blocked = false;
      expect(
        await reservation.recover(owner, () async {
          if (finalizer.retry() != RuntimeCleanupOutcome.confirmed)
            return false;
          quarantine.confirmOwnerUnload(owner);
          reservation.releaseContext(owner);
          return !quarantine.hasRequests;
        }),
        RuntimeRecoveryOutcome.recovered,
      );
      expect(published, 1);
      expect(released, [123]);
      expect(control.retainedRequestCount, 0);
      expect(reservation.canAccess(competitor), isFalse);
      reservation.finish(owner, terminationConfirmed: true);
      expect(reservation.canAccess(competitor), isTrue);
    },
  );
}
