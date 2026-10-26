import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vitalis_app/constants/app_constants.dart';
import 'package:vitalis_app/database/database_helper.dart';

void main() {
  final storage = DatabaseHelper.instance;
  late Directory sandbox;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    sandbox = await Directory.systemTemp.createTemp('vitalis_install_journal_');
    await databaseFactory.setDatabasesPath(sandbox.path);
  });

  setUp(() async {
    await storage.close();
    await databaseFactory.deleteDatabase(
      p.join(sandbox.path, AppConstants.databaseName),
    );
  });

  tearDownAll(() async {
    await storage.close();
    await sandbox.delete(recursive: true);
  });

  Future<void> expectJournalSchema(Database db) async {
    expect(await db.getVersion(), 8);
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    expect(
      tables.map((row) => row['name']),
      containsAll(['model_installation_journal', 'model_installation_shards']),
    );
  }

  test('fresh database provides the version-8 installation journal', () async {
    await expectJournalSchema(await storage.database);
  });

  test(
    'failed version-7 migration rolls back without touching saved data',
    () async {
      final db = await storage.database;
      await db.execute('CREATE TABLE preserved_fixture (value TEXT NOT NULL)');
      await db.insert('preserved_fixture', {'value': 'keep'});
      await db.execute('DROP TABLE model_installation_shards');
      await db.execute('DROP TABLE model_installation_journal');
      await db.execute(
        'CREATE VIEW model_installation_journal AS SELECT 1 AS collision',
      );
      await db.setVersion(7);
      await storage.close();

      await expectLater(storage.database, throwsA(isA<DatabaseException>()));
      final inspected = await databaseFactory.openDatabase(
        p.join(sandbox.path, AppConstants.databaseName),
      );
      try {
        expect(await inspected.getVersion(), 7);
        expect(
          (await inspected.query('preserved_fixture')).single['value'],
          'keep',
        );
        expect(
          await inspected.rawQuery(
            "SELECT name FROM sqlite_master WHERE name = 'model_installation_shards'",
          ),
          isEmpty,
        );
      } finally {
        await inspected.close();
      }
    },
  );

  test(
    'version-7 upgrade preserves saved content and installed identity',
    () async {
      final db = await storage.database;
      final stamp = DateTime(2026).toIso8601String();
      final chatId = await storage.insertChat({
        'title': 'Disposable migration fixture',
        'created_at': stamp,
        'updated_at': stamp,
      });
      await storage.assignModelForChat(chatId, 'installed-fixture');
      await storage.upsertModel({
        'id': 'installed-fixture',
        'display_name': 'Disposable model',
        'source': 'local_import',
        'local_path': 'fixture.gguf',
        'sha256': 'fixture-identity',
        'compatibility_status': 'compatible',
        'installation_state': 'installed',
      });
      final beforeModel = await storage.getModel('installed-fixture');
      final beforeSettings = await storage.getModelSettings(chatId);
      await db.execute('DROP TABLE IF EXISTS model_installation_shards');
      await db.execute('DROP TABLE IF EXISTS model_installation_journal');
      await db.setVersion(7);
      await storage.close();

      await expectJournalSchema(await storage.database);
      expect(await storage.getModel('installed-fixture'), beforeModel);
      expect(await storage.getModelSettings(chatId), beforeSettings);
      expect(
        (await storage.getChat(chatId))?.title,
        'Disposable migration fixture',
      );
    },
  );
}
