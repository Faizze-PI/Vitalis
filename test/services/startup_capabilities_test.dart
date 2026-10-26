import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/services/startup_coordinator.dart';

void main() {
  StartupCoordinator coordinator(StartupModelAssessment assess) =>
      StartupCoordinator(
        openDatabase: () async {},
        loadLogger: () async {},
        migrateLegacyPreferences: () async {},
        initializeSafety: () async {},
        assessModel: assess,
        optionalTaskTimeout: const Duration(milliseconds: 5),
      );

  for (final readiness in StartupModelReadiness.values) {
    test(
      'owned assessment publishes $readiness without substitution',
      () async {
        final subject = coordinator(() async => readiness);
        addTearDown(subject.dispose);
        await subject.start();
        expect(subject.capabilities.modelReadiness, readiness);
        expect(subject.capabilities.canBrowse, isTrue);
        expect(
          subject.capabilities.canInfer,
          readiness == StartupModelReadiness.ready,
        );
      },
    );
  }

  test('late assessment cannot unlock inference or overlap retry', () async {
    final pending = Completer<StartupModelReadiness>();
    var calls = 0;
    final subject = coordinator(() {
      calls++;
      return pending.future;
    });
    addTearDown(subject.dispose);
    await subject.start();
    expect(subject.capabilities.canBrowse, isTrue);
    expect(subject.capabilities.canInfer, isFalse);
    expect(subject.canRetry, isFalse);
    await subject.start();
    expect(calls, 1);
    pending.complete(StartupModelReadiness.ready);
    await Future<void>.delayed(Duration.zero);
    expect(subject.capabilities.modelReadiness, StartupModelReadiness.unknown);
    expect(subject.capabilities.canInfer, isFalse);
    expect(subject.canRetry, isTrue);
    await subject.start();
    expect(calls, 2);
    expect(subject.capabilities.canInfer, isTrue);
  });

  test('assessment failure remains recoverable and read-only', () async {
    final subject = coordinator(() async => throw StateError('unavailable'));
    addTearDown(subject.dispose);
    await subject.start();
    expect(subject.state, StartupState.degraded);
    expect(subject.capabilities.canRecoverModels, isTrue);
    expect(subject.capabilities.canMutateContent, isFalse);
    expect(subject.capabilities.modelReadiness, StartupModelReadiness.unknown);
  });

  test('disposed assessment rejects late readiness', () async {
    final pending = Completer<StartupModelReadiness>();
    final started = Completer<void>();
    final subject = coordinator(() {
      started.complete();
      return pending.future;
    });
    final operation = subject.start();
    await started.future;
    subject.dispose();
    pending.complete(StartupModelReadiness.ready);
    await operation;
    expect(subject.capabilities.canBrowse, isFalse);
    expect(subject.capabilities.canInfer, isFalse);
  });

  for (final database in [false, true]) {
    for (final migration in [false, true]) {
      for (final safety in [false, true]) {
        for (final model in StartupModelReadiness.values) {
          test('permissions: database=$database migration=$migration '
              'safety=$safety model=$model', () {
            final snapshot = StartupCapabilities(
              databaseReady: database,
              migrationReady: migration,
              safetyReady: safety,
              modelReadiness: model,
            );
            final browse = database && migration;
            final infer =
                browse && safety && model == StartupModelReadiness.ready;
            expect(snapshot.canBrowse, browse);
            expect(snapshot.canRecoverModels, browse);
            expect(snapshot.canInfer, infer);
            expect(snapshot.canMutateContent, infer);
            expect(snapshot.readOnly, browse && !infer);
          });
        }
      }
    }
  }

  test('disposal revokes every permission', () {
    const snapshot = StartupCapabilities(
      databaseReady: true,
      migrationReady: true,
      safetyReady: true,
      modelReadiness: StartupModelReadiness.ready,
      disposed: true,
    );
    expect(snapshot.canBrowse, isFalse);
    expect(snapshot.canRecoverModels, isFalse);
    expect(snapshot.canInfer, isFalse);
    expect(snapshot.canMutateContent, isFalse);
  });

  test('successful bootstrap does not assume a model was verified', () async {
    final subject = StartupCoordinator(
      openDatabase: () async {},
      loadLogger: () async {},
      migrateLegacyPreferences: () async {},
      initializeSafety: () async {},
    );
    await subject.start();
    expect(subject.capabilities.canBrowse, isTrue);
    expect(subject.capabilities.safetyReady, isTrue);
    expect(subject.capabilities.modelReadiness, StartupModelReadiness.unknown);
    expect(subject.capabilities.canInfer, isFalse);
    expect(subject.capabilities.readOnly, isTrue);
    subject.dispose();
    expect(subject.capabilities.canBrowse, isFalse);
  });
}
