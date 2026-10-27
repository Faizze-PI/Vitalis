import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/database/database_helper.dart';

// Opt-in host measurement, outside test/: never adds a one-minute workload to
// every unit-test run. These are storage measurements, not model TTFT or UI FPS.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late DatabaseHelper db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    sandbox = await Directory.systemTemp.createTemp('vitalis_storage_measure_');
    await databaseFactory.setDatabasesPath(sandbox.path);
    db = DatabaseHelper.instance;
    await db.database;
  });
  tearDownAll(() async {
    await db.close();
    await sandbox.delete(recursive: true);
  });

  Future<int> createChat() => db.insertChat({
    'title': 'Disposable host measurement',
    'created_at': DateTime.now().toIso8601String(),
    'updated_at': DateTime.now().toIso8601String(),
  });

  void record(String name, List<int> samples, int elapsedMicros) {
    final sorted = [...samples]..sort();
    final total = samples.fold<int>(0, (sum, value) => sum + value);
    final result = {
      'name': name,
      'platform': Platform.operatingSystem,
      'scope': 'Flutter test host SQLite; not production inference or phone UI',
      'operations': samples.length,
      'errors': 0,
      'elapsed_micros': elapsedMicros,
      'operations_per_second': samples.length * 1000000 / elapsedMicros,
      'min_micros': sorted.first,
      'mean_micros': total / samples.length,
      'median_micros': sorted[(sorted.length - 1) ~/ 2],
      'p95_micros': sorted[(sorted.length * .95).ceil() - 1],
      'max_micros': sorted.last,
    };
    stdout.writeln('VITALIS_HOST_METRIC:${jsonEncode(result)}');
    final output = Platform.environment['VITALIS_VALIDATION_METRICS'];
    if (output != null) {
      File(output).writeAsStringSync(
        '${jsonEncode(result)}\n',
        mode: FileMode.append,
        flush: true,
      );
    }
  }

  test('100 sequential insert/read/delete cycles', () async {
    final samples = <int>[];
    final clock = Stopwatch()..start();
    for (var index = 0; index < 100; index++) {
      final before = clock.elapsedMicroseconds;
      final id = await createChat();
      expect((await db.getChat(id))?.title, 'Disposable host measurement');
      await db.deleteChat(id);
      expect(await db.getChat(id), isNull);
      samples.add(clock.elapsedMicroseconds - before);
    }
    record(
      'Sequential CRUD cycles (four database calls per cycle)',
      samples,
      clock.elapsedMicroseconds,
    );
  });

  test('100 concurrent read requests retain correct results', () async {
    final id = await createChat();
    try {
      final samples = <int>[];
      final clock = Stopwatch()..start();
      await Future.wait(
        List.generate(100, (_) async {
          final before = clock.elapsedMicroseconds;
          expect((await db.getChat(id))?.id, id);
          samples.add(clock.elapsedMicroseconds - before);
        }),
      );
      record(
        '100 concurrent host reads (not 100 app users)',
        samples,
        clock.elapsedMicroseconds,
      );
    } finally {
      await db.deleteChat(id);
    }
  });

  test(
    '60-second paced read workload preserves data',
    () async {
      final id = await createChat();
      try {
        final samples = <int>[];
        final clock = Stopwatch()..start();
        // Pacing models bounded activity; it is excluded from per-read latency.
        // No random delays, fabricated durations, or unlimited request loop.
        while (clock.elapsed < const Duration(seconds: 60) &&
            samples.length < 3000) {
          final before = clock.elapsedMicroseconds;
          expect((await db.getChat(id))?.id, id);
          final micros = clock.elapsedMicroseconds - before;
          samples.add(micros);
          final remaining = 20000 - micros;
          if (remaining > 0) {
            await Future<void>.delayed(Duration(microseconds: remaining));
          }
        }
        expect(samples, isNotEmpty);
        expect((await db.getChat(id))?.id, id);
        record(
          '60-second paced host reads (at most 50 starts/second)',
          samples,
          clock.elapsedMicroseconds,
        );
      } finally {
        await db.deleteChat(id);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
