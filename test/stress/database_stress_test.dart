import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late DatabaseHelper db;
  late Directory testDatabaseDirectory;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    testDatabaseDirectory = Directory.systemTemp.createTempSync(
      'vitalis_database_stress_test_',
    );
    await databaseFactory.setDatabasesPath(testDatabaseDirectory.path);
    db = DatabaseHelper.instance;
    await db.database;
  });

  tearDownAll(() async {
    await db.close();
    if (await testDatabaseDirectory.exists()) {
      await testDatabaseDirectory.delete(recursive: true);
    }
  });

  group('Database stress (tier 3)', () {
    test(
      '2000 sequential chat insert and retrieve',
      () async {
        for (int i = 0; i < 2000; i++) {
          final id = await db.insertChat({
            'title': 'Stress Chat $i',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
          expect(id, greaterThan(0));
          final chat = await db.getChat(id);
          expect(chat, isNotNull);
          expect(chat!.title, 'Stress Chat $i');
          await db.deleteChat(id);
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test('1000 messages in one chat', () async {
      final chatId = await db.insertChat({
        'title': 'Bulk Chat',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      for (int i = 0; i < 1000; i++) {
        await db.insertMessage({
          'chat_id': chatId,
          'role': i.isEven ? 'user' : 'assistant',
          'content': 'Message $i content with some padding for realism.',
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
      final msgs = await db.getMessagesForChat(chatId);
      expect(msgs.length, 1000);
      await db.deleteChat(chatId);
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
