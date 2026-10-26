import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/database/windows_database.dart';

void main() {
  test(
    'non-Windows initialization leaves the mobile factory untouched',
    () async {
      databaseFactory = databaseFactoryFfi;
      final original = databaseFactory;
      await initializeWindowsDatabase(
        isWindows: false,
        supportDirectory: () =>
            throw StateError('must not query desktop storage'),
      );
      expect(identical(databaseFactory, original), isTrue);
    },
  );
  test(
    'Windows persistence uses support storage and survives reopening',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'vitalis-storage-',
      );
      try {
        await initializeWindowsDatabase(
          supportDirectory: () async => directory,
          isWindows: true,
        );
        expect(await getDatabasesPath(), directory.path);
        final path = p.join(directory.path, 'fixture.db');
        var database = await openDatabase(path);
        await database.execute('CREATE TABLE fixture (value TEXT NOT NULL)');
        await database.insert('fixture', {'value': 'retained'});
        await database.close();
        database = await openDatabase(path);
        expect(await database.query('fixture'), [
          {'value': 'retained'},
        ]);
        await database.close();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
