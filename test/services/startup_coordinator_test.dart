import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/startup_coordinator.dart';

void main() {
  StartupCoordinator coordinator({
    StartupTask? database,
    StartupTask? logger,
    StartupTask? migration,
    StartupTask? safety,
    Duration databaseTimeout = const Duration(seconds: 1),
    Duration optionalTimeout = const Duration(seconds: 1),
  }) => StartupCoordinator(
    openDatabase: database ?? () async {},
    loadLogger: logger ?? () async {},
    migrateLegacyPreferences: migration ?? () async {},
    initializeSafety: safety ?? () async {},
    clock: () => const Duration(milliseconds: 10),
    databaseTimeout: databaseTimeout,
    optionalTaskTimeout: optionalTimeout,
  );

  test('reaches ready after ordered bootstrap tasks complete', () async {
    final calls = <String>[];
    final subject = coordinator(
      database: () async => calls.add('database'),
      logger: () async => calls.add('logger'),
      migration: () async => calls.add('migration'),
      safety: () async => calls.add('safety'),
    );
    addTearDown(subject.dispose);

    await subject.start();

    expect(calls, ['database', 'logger', 'migration', 'safety']);
    expect(subject.state, StartupState.ready);
    expect(subject.canEnterApp, isTrue);
    expect(subject.trace, contains('10:startup:ready'));
  });

  test(
    'database timeout fails without allowing the application to start',
    () async {
      final never = Completer<void>();
      final subject = coordinator(
        database: () => never.future,
        databaseTimeout: const Duration(milliseconds: 1),
      );
      addTearDown(subject.dispose);

      await subject.start();

      expect(subject.state, StartupState.failed);
      expect(subject.canEnterApp, isFalse);
      expect(subject.failure, contains('No automatic reset'));
      expect(subject.canRetry, isFalse);
      never.complete();
    },
  );

  test('optional task failures produce a usable degraded state', () async {
    final subject = coordinator(
      logger: () => Future<void>.error(StateError('logger unavailable')),
    );
    addTearDown(subject.dispose);

    await subject.start();

    expect(subject.state, StartupState.degraded);
    expect(subject.canEnterApp, isTrue);
    expect(subject.trace, contains('10:logger:deferred'));
  });

  test('concurrent starts share one active bootstrap attempt', () async {
    final gate = Completer<void>();
    var calls = 0;
    final subject = coordinator(
      database: () async {
        calls++;
        await gate.future;
      },
    );
    addTearDown(subject.dispose);

    final first = subject.start();
    final second = subject.start();
    expect(identical(first, second), isTrue);
    gate.complete();
    await Future.wait([first, second]);

    expect(calls, 1);
    expect(subject.state, StartupState.ready);
  });

  test(
    'reentrant listener shares the already-owned startup operation',
    () async {
      final pending = Completer<void>();
      var calls = 0;
      final subject = coordinator(
        database: () {
          calls++;
          return pending.future;
        },
      );
      addTearDown(subject.dispose);
      Future<void>? reentrant;
      subject.addListener(() {
        if (subject.state == StartupState.openingDatabase &&
            reentrant == null) {
          reentrant = subject.start();
        }
      });
      final operation = subject.start();
      expect(reentrant, same(operation));
      pending.complete();
      await operation;
      expect(calls, 1);
    },
  );

  for (final phase in ['migration', 'safety']) {
    test('$phase failure blocks dependent app initialization', () async {
      Future<void> fail() async => throw StateError('unavailable');
      final subject = coordinator(
        migration: phase == 'migration' ? fail : null,
        safety: phase == 'safety' ? fail : null,
      );
      addTearDown(subject.dispose);
      await subject.start();
      expect(subject.state, StartupState.failed);
      expect(subject.canEnterApp, isFalse);
    });
  }

  test('timeout retries cannot overlap unfinished database writes', () async {
    final pending = Completer<void>();
    var calls = 0;
    final subject = coordinator(
      database: () {
        calls++;
        return pending.future;
      },
      databaseTimeout: const Duration(milliseconds: 1),
    );
    addTearDown(subject.dispose);
    await subject.start();
    await subject.start();
    expect(calls, 1);
    expect(subject.canRetry, isFalse);
    pending.complete();
    await Future<void>.delayed(Duration.zero);
    expect(subject.canRetry, isTrue);
    await subject.start();
    expect(calls, 2);
    expect(subject.state, StartupState.ready);
  });

  test('disposed startup never enters later phases or notifies', () async {
    final pending = Completer<void>();
    var migrationCalls = 0;
    final subject = coordinator(
      database: () => pending.future,
      migration: () async {
        migrationCalls++;
      },
    );
    final operation = subject.start();
    subject.dispose();
    pending.complete();
    await operation;
    expect(migrationCalls, 0);
    await expectLater(subject.start(), throwsStateError);
  });
}
