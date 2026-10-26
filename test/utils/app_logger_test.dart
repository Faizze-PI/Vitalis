import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vitalis_app/utils/app_logger.dart';

void main() {
  late Directory root;
  late String ownedRoot;
  final now = DateTime.utc(2026, 9, 9, 12);
  final subjects = <AppLogger>[];

  setUp(() async {
    root = await Directory.systemTemp.createTemp('vitalis_logger_');
    ownedRoot = await root.resolveSymbolicLinks();
    final parent = await Directory.systemTemp.resolveSymbolicLinks();
    if (!ownedRoot.startsWith('$parent${Platform.pathSeparator}')) {
      throw StateError('Logger fixture escaped its temporary parent');
    }
  });

  tearDown(() async {
    for (final subject in subjects) {
      await subject.flush();
    }
    subjects.clear();
    if (await root.exists()) {
      if (await root.resolveSymbolicLinks() != ownedRoot) {
        throw StateError('Logger fixture ownership changed');
      }
      await root.delete(recursive: true);
    }
  });

  AppLogger logger({
    Future<bool?> Function()? load,
    Future<void> Function(bool)? save,
    Future<Directory> Function()? directory,
    Future<bool> Function(File)? remove,
  }) {
    final subject = AppLogger.forTesting(
      directoryResolver: directory ?? () async => root,
      privacyLoader: load ?? () async => false,
      privacySaver: save ?? (_) async {},
      clock: () => now,
      fileRemover: remove,
    );
    subjects.add(subject);
    return subject;
  }

  for (final privacy in [true, false]) {
    for (final mode in ['warning', 'error', 'errorSync']) {
      for (final throwsOnString in [false, true]) {
        test(
          'typed $mode failure never formats payload privacy=$privacy throws=$throwsOnString',
          () async {
            final subject = logger(load: () async => privacy);
            await subject.loadPersistedState();
            final failure = _PrivateDiagnosticFailure(throwsOnString);
            switch (mode) {
              case 'warning':
                await subject.warningFailure('Fixture operation', failure);
              case 'error':
                await subject.errorFailure('Fixture operation', failure);
              case 'errorSync':
                subject.errorFailureSync('Fixture operation', failure);
            }
            await subject.flush();
            final logs = await subject.getLogs();
            expect(
              logs,
              contains('Fixture operation (_PrivateDiagnosticFailure)'),
            );
            expect(logs, contains(mode == 'warning' ? '[WARN]' : '[ERROR]'));
            expect(failure.stringCalls, 0);
            expect(logs, isNot(contains(_PrivateDiagnosticFailure.payload)));
            final files = await root
                .list(recursive: true)
                .where((entry) => entry is File)
                .cast<File>()
                .toList();
            expect(files, isNotEmpty);
            for (final file in files) {
              final text = await file.readAsString();
              expect(text, contains('_PrivateDiagnosticFailure'));
              expect(text, isNot(contains(_PrivateDiagnosticFailure.payload)));
            }
          },
        );
      }
    }
  }

  test(
    'loads privacy state and suppresses informational disk writes',
    () async {
      final subject = logger(load: () async => true);
      await subject.loadPersistedState();

      await subject.info('private information');

      expect(subject.isPrivacyMode, isTrue);
      expect(await subject.getLogs(), isEmpty);
      expect(Directory('${root.path}/logs').existsSync(), isFalse);
    },
  );

  test('writes sanitized entries, rotates, prunes, and clears', () async {
    final subject = logger();
    await subject.loadPersistedState();
    final logs = Directory('${root.path}/logs');
    await logs.create(recursive: true);
    final daily = File('${logs.path}/log_2026-09-09.txt');
    await daily.writeAsBytes(List<int>.filled(2 * 1024 * 1024 + 1, 1));
    final old = File('${logs.path}/old.txt');
    await old.writeAsString('obsolete');
    await old.setLastModified(now.subtract(const Duration(days: 8)));

    for (var index = 0; index < 10; index++) {
      await subject.warning('token=secret-$index');
    }

    expect(File('${daily.path}.1').existsSync(), isTrue);
    expect(old.existsSync(), isFalse);
    final text = await daily.readAsString();
    expect(text, isNot(contains('secret-')));
    expect(await subject.getLogs(maxLines: 2), contains('[WARN]'));

    final cleanup = await subject.clearLogs();
    expect(cleanup.complete, isTrue);
    expect(cleanup.failedOperations, 0);
    expect(cleanup.removedFiles, greaterThan(0));
    expect(await subject.getLogs(), isEmpty);
    expect(logs.listSync().whereType<File>(), isEmpty);
  });

  test('synchronous facade records bounded local diagnostics', () async {
    final subject = logger();
    await subject.loadPersistedState();
    subject.infoSync('hello');
    subject.errorSync('failure');
    await subject.flush();

    final logs = await subject.getLogs();
    expect(logs, contains('[INFO]'));
    expect(logs, contains('[ERROR]'));
  });

  test(
    'partial log cleanup reports retained files rather than success',
    () async {
      final logs = Directory('${root.path}/logs')..createSync();
      final retained = File('${logs.path}/keep.txt')
        ..writeAsStringSync('Disposable retained log');
      final removed = File('${logs.path}/remove.txt')
        ..writeAsStringSync('Disposable removable log');
      final subject = logger(
        remove: (file) async {
          if (p.equals(file.path, retained.path)) return false;
          await file.delete();
          return true;
        },
      );
      final cleanup = await subject.clearLogs();
      expect(cleanup.complete, isFalse);
      expect(cleanup.removedFiles, 1);
      expect(cleanup.failedOperations, 1);
      expect(await retained.exists(), isTrue);
      expect(await removed.exists(), isFalse);
    },
  );

  test(
    'unavailable log storage reports failure without hiding retained memory',
    () async {
      final subject = logger(
        directory: () async => throw StateError('/private/logs token=secret'),
      );
      await subject.warning('Disposable warning');
      final cleanup = await subject.clearLogs();
      expect(cleanup.complete, isFalse);
      expect(cleanup.removedFiles, 0);
      expect(cleanup.failedOperations, 1);
      expect(await subject.getLogs(), contains('Disposable warning'));
    },
  );

  test('synchronous informational logs obey privacy mode', () async {
    final subject = logger(load: () async => true);
    await subject.loadPersistedState();
    subject.infoSync('private content');
    await subject.flush();
    expect(await subject.getLogs(), isEmpty);
    expect(Directory('${root.path}/logs').existsSync(), isFalse);
  });

  test('flush waits for slow storage and every queued write', () async {
    final directory = Completer<Directory>();
    final subject = logger(directory: () => directory.future);
    subject.errorSync('first');
    subject.errorSync('second');
    var drained = false;
    final barrier = subject.flush().then((_) {
      drained = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);
    directory.complete(root);
    await barrier;
    final text = await File(
      '${root.path}/logs/log_2026-09-09.txt',
    ).readAsString();
    expect(text, contains('first'));
    expect(text, contains('second'));
  });

  test('privacy disabling waits for persistence acknowledgement', () async {
    final saved = Completer<void>();
    final subject = logger(save: (_) => saved.future);
    final operation = subject.setPrivacyMode(false);
    await Future<void>.delayed(Duration.zero);
    expect(subject.isPrivacyMode, isTrue);
    saved.complete();
    await operation;
    expect(subject.isPrivacyMode, isFalse);
  });

  test(
    'failed privacy enable keeps runtime protection without durable success',
    () async {
      final subject = logger(
        save: (_) async => throw StateError('/private/token=secret'),
      );
      await subject.loadPersistedState();
      expect(subject.isPrivacyMode, isFalse);
      await expectLater(
        subject.setPrivacyMode(true),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'redaction',
            isNot(contains('token=secret')),
          ),
        ),
      );
      expect(subject.isPrivacyMode, isTrue);
      expect(subject.sinkFailureCount, 1);
      subject.infoSync('Disposable informational message');
      await subject.flush();
      expect(await subject.getLogs(), isEmpty);
    },
  );

  test(
    'failed privacy write does not poison a subsequent acknowledged retry',
    () async {
      var attempts = 0;
      final subject = logger(
        save: (_) async {
          if (++attempts == 1) throw StateError('Injected persistence failure');
        },
      );
      await expectLater(subject.setPrivacyMode(false), throwsStateError);
      expect(subject.isPrivacyMode, isTrue);
      await subject.setPrivacyMode(false);
      expect(subject.isPrivacyMode, isFalse);
      expect(attempts, 2);
      expect(subject.sinkFailureCount, 1);
    },
  );

  test(
    'privacy writes serialize and stale disable cannot undo protection',
    () async {
      final first = Completer<void>();
      final second = Completer<void>();
      final writes = <bool>[];
      final subject = logger(
        save: (value) {
          writes.add(value);
          return writes.length == 1 ? first.future : second.future;
        },
      );
      final disabling = subject.setPrivacyMode(false);
      await Future<void>.delayed(Duration.zero);
      final enabling = subject.setPrivacyMode(true);
      expect(writes, [false]);
      first.complete();
      await disabling;
      expect(subject.isPrivacyMode, isTrue);
      expect(writes, [false, true]);
      second.complete();
      await enabling;
      expect(subject.isPrivacyMode, isTrue);
    },
  );

  test(
    'late preference loading cannot overwrite a newer privacy choice',
    () async {
      final loaded = Completer<bool?>();
      final subject = logger(load: () => loaded.future);
      final loading = subject.loadPersistedState();
      await subject.setPrivacyMode(true);
      loaded.complete(false);
      await loading;
      expect(subject.isPrivacyMode, isTrue);
    },
  );

  test('preference and sink failures are counted without recursion', () async {
    final subject = logger(
      load: () => throw StateError('load failed'),
      save: (_) => throw StateError('save failed'),
      directory: () => throw StateError('sink failed'),
    );

    await subject.loadPersistedState();
    await expectLater(subject.setPrivacyMode(false), throwsStateError);
    await subject.error('cannot persist');
    await Future<void>.delayed(Duration.zero);

    expect(subject.isPrivacyMode, isTrue);
    expect(subject.sinkFailureCount, greaterThanOrEqualTo(3));
  });
}

final class _PrivateDiagnosticFailure implements Exception {
  _PrivateDiagnosticFailure(this.throwsOnString);
  static const payload = 'PRIVATE_FAILURE_PAYLOAD_FIXTURE';
  final bool throwsOnString;
  int stringCalls = 0;
  @override
  String toString() {
    stringCalls++;
    if (throwsOnString) throw StateError(payload);
    return payload;
  }
}
