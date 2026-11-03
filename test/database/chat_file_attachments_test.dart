import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:vitalis_app/constants/app_constants.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/services/local_file_workspace.dart';

void main() {
  late Directory root;
  final helper = DatabaseHelper.instance;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    root = await Directory.systemTemp.createTemp('vitalis-chat-files-');
    await databaseFactory.setDatabasesPath(root.path);
  });
  tearDown(() async {
    await helper.close();
    await root.delete(recursive: true);
  });
  Future<int> chat(String name) async => (await helper.database).insert(
    'chats',
    {'title': name, 'created_at': '2026-11-04', 'updated_at': '2026-11-04'},
  );
  WorkspaceFile file(String id, String name) =>
      WorkspaceFile(id: id * 32, name: name, bytes: 4, sha256: 'a' * 64);
  test(
    'persists ordered per-chat files; detach and chat deletion preserve other assignments',
    () async {
      final first = await chat('First'), second = await chat('Second');
      final a = file('a', 'a.csv'), b = file('b', 'b.txt');
      await helper.attachFile(first, a);
      await helper.attachFile(first, b);
      await helper.attachFile(first, a);
      await helper.attachFile(second, a);
      expect((await helper.getAttachedFiles(first)).map((f) => f.name), [
        'a.csv',
        'b.txt',
      ]);
      expect(await helper.fileAttachmentCount(a.id), 2);
      await helper.close();
      expect((await helper.getAttachedFiles(first)).length, 2);
      await helper.detachFile(first, a.id);
      expect(await helper.fileAttachmentCount(a.id), 1);
      await (await helper.database).delete(
        'chats',
        where: 'id = ?',
        whereArgs: [second],
      );
      expect(await helper.fileAttachmentCount(a.id), 0);
      expect((await helper.getAttachedFiles(first)).single.id, b.id);
    },
  );
  test('version-8 upgrade preserves prior chats and messages', () async {
    final id = await chat('Preserved');
    final db = await helper.database;
    await db.insert('messages', {
      'chat_id': id,
      'role': 'user',
      'content': 'keep',
      'timestamp': '2026-11-04',
    });
    await db.execute('DROP TABLE IF EXISTS chat_file_attachments');
    await db.setVersion(8);
    await helper.close();
    final reopened = await helper.database;
    expect(await reopened.getVersion(), AppConstants.databaseVersion);
    expect((await reopened.query('messages')).single['content'], 'keep');
    await helper.attachFile(id, file('c', 'new.txt'));
    expect((await helper.getAttachedFiles(id)).single.name, 'new.txt');
    expect(await reopened.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
  test(
    'failed version-8 migration rolls back and preserves saved messages',
    () async {
      final id = await chat('Preserved');
      final db = await helper.database;
      await db.insert('messages', {
        'chat_id': id,
        'role': 'user',
        'content': 'keep',
        'timestamp': '2026-11-04',
      });
      await db.execute('DROP TABLE chat_file_attachments');
      await db.execute(
        'CREATE VIEW chat_file_attachments AS SELECT 1 AS blocked',
      );
      await db.setVersion(8);
      await helper.close();
      await expectLater(helper.database, throwsA(anything));
      final inspected = await databaseFactory.openDatabase(
        p.join(root.path, AppConstants.databaseName),
        options: OpenDatabaseOptions(version: 8),
      );
      expect(await inspected.getVersion(), 8);
      expect((await inspected.query('messages')).single['content'], 'keep');
      expect((await inspected.query('chats')).single['title'], 'Preserved');
      await inspected.execute('DROP VIEW chat_file_attachments');
      await inspected.close();
      expect(
        await (await helper.database).getVersion(),
        AppConstants.databaseVersion,
      );
    },
  );

  test('rejects unsafe file identities without adding records', () async {
    final id = await chat('Disposable');
    await expectLater(
      helper.attachFile(
        id,
        const WorkspaceFile(
          id: '../outside',
          name: 'bad',
          bytes: 1,
          sha256: 'bad',
        ),
      ),
      throwsArgumentError,
    );
    expect(await helper.getAttachedFiles(id), isEmpty);
    expect(await File(p.join(root.path, 'outside')).exists(), isFalse);
  });
}
