import 'package:sqflite/sqflite.dart';

/// HC-079: chat references preserve the immutable file identity and order.
Future<void> createChatFileAttachmentSchema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS chat_file_attachments (
      chat_id INTEGER NOT NULL,
      file_id TEXT NOT NULL CHECK(length(file_id) = 32 AND file_id NOT GLOB '*[^a-f0-9]*'),
      display_name TEXT NOT NULL,
      byte_size INTEGER NOT NULL CHECK(byte_size >= 0),
      sha256 TEXT NOT NULL CHECK(length(sha256) = 64 AND sha256 NOT GLOB '*[^a-f0-9]*'),
      position INTEGER NOT NULL CHECK(position >= 0),
      PRIMARY KEY(chat_id, file_id),
      FOREIGN KEY(chat_id) REFERENCES chats(id) ON DELETE CASCADE
    )
  ''');
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_chat_files_identity ON chat_file_attachments(file_id)',
  );
}
