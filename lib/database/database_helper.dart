import 'dart:async';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../constants/app_constants.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../models/note.dart';
import '../models/bundled_model_manifest.dart';
import '../models/model_defaults.dart';
import '../models/model_settings.dart';
import '../utils/app_logger.dart';
import 'installation_journal_schema.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._();
  DatabaseHelper._();

  Database? _database;
  Future<Database>? _initFuture;

  Future<Database> get database async {
    if (_database != null) return _database!;
    if (_initFuture != null) return _initFuture!;
    _initFuture = _initDatabase();
    try {
      _database = await _initFuture;
      return _database!;
    } catch (e) {
      _initFuture = null;
      rethrow;
    }
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, AppConstants.databaseName);
    return await openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        try {
          await db.execute('PRAGMA journal_mode = WAL');
        } catch (_) {
          // WAL unsupported in sqflite_common_ffi test environment — acceptable
        }
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE chats (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL DEFAULT 'New Chat',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id INTEGER NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        is_error INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (chat_id) REFERENCES chats(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE personas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        system_prompt TEXT NOT NULL,
        is_default INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE model_settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chat_id INTEGER NOT NULL UNIQUE,
        temperature REAL NOT NULL DEFAULT ${ModelDefaults.temperature},
        top_k INTEGER NOT NULL DEFAULT ${ModelDefaults.topK},
        top_p REAL NOT NULL DEFAULT ${ModelDefaults.topP},
        max_tokens INTEGER NOT NULL DEFAULT ${ModelDefaults.maximumOutputTokens},
        system_prompt TEXT NOT NULL DEFAULT '${ModelDefaults.systemPrompt}',
        model_id TEXT NOT NULL DEFAULT '${BundledModelManifest.id}',
        tuning_mode TEXT NOT NULL DEFAULT 'automatic',
        thinking_mode TEXT NOT NULL DEFAULT 'off',
        acceleration_preference TEXT NOT NULL DEFAULT 'cpu',
        context_size_override INTEGER,
        generation_threads_override INTEGER,
        prompt_threads_override INTEGER,
        batch_size_override INTEGER,
        FOREIGN KEY (chat_id) REFERENCES chats(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE chat_persona (
        chat_id INTEGER NOT NULL,
        persona_id INTEGER NOT NULL,
        PRIMARY KEY (chat_id, persona_id),
        FOREIGN KEY (chat_id) REFERENCES chats(id) ON DELETE CASCADE,
        FOREIGN KEY (persona_id) REFERENCES personas(id) ON DELETE CASCADE
      )
    ''');
    await _createV4Tables(db);
    await _createV6Tables(db);
    await _createV7Tables(db);
    await createInstallationJournalSchema(db);
    await db.execute('''
      INSERT INTO personas (name, system_prompt, is_default)
      VALUES ('Default Assistant', 'You are a helpful assistant.', 1)
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chats_updated_at ON chats(updated_at)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (int v = oldVersion; v < newVersion; v++) {
      switch (v) {
        case 1:
          await db.execute(
            'ALTER TABLE messages ADD COLUMN is_error INTEGER NOT NULL DEFAULT 0',
          );
          break;
        case 2:
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_chats_updated_at ON chats(updated_at)',
          );
          break;
        case 3:
          await db.execute(
            "ALTER TABLE model_settings ADD COLUMN model_id TEXT NOT NULL DEFAULT 'qwen3.5-0.8b-q4-k-m'",
          );
          await db.execute(
            "ALTER TABLE model_settings ADD COLUMN tuning_mode TEXT NOT NULL DEFAULT 'automatic'",
          );
          await db.execute(
            "ALTER TABLE model_settings ADD COLUMN thinking_mode TEXT NOT NULL DEFAULT 'off'",
          );
          await db.execute(
            "ALTER TABLE model_settings ADD COLUMN acceleration_preference TEXT NOT NULL DEFAULT 'cpu'",
          );
          await db.execute(
            'ALTER TABLE model_settings ADD COLUMN context_size_override INTEGER',
          );
          await db.execute(
            'ALTER TABLE model_settings ADD COLUMN generation_threads_override INTEGER',
          );
          await db.execute(
            'ALTER TABLE model_settings ADD COLUMN prompt_threads_override INTEGER',
          );
          await db.execute(
            'ALTER TABLE model_settings ADD COLUMN batch_size_override INTEGER',
          );
          await _createV4Tables(db);
          break;
        case 4:
          await _addColumnIfMissing(db, 'models', 'block_count', 'INTEGER');
          await _addColumnIfMissing(
            db,
            'models',
            'supports_thinking',
            'INTEGER NOT NULL DEFAULT 0',
          );
          break;
        case 5:
          await _createV6Tables(db);
          break;
        case 6:
          // Repair partially applied version-6 migrations before projecting
          // the version-7 cache. Every helper is idempotent.
          await _createV6Tables(db);
          await _createV7Tables(db);
          break;
        case 7:
          await createInstallationJournalSchema(db);
          break;
      }
    }
  }

  Future<void> _addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String column,
    String declaration,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    if (columns.any((entry) => entry['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $declaration');
  }

  Future<void> _createV4Tables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS models (
        id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        local_path TEXT,
        source TEXT NOT NULL,
        sha256 TEXT,
        byte_size INTEGER,
        architecture TEXT,
        tokenizer TEXT,
        context_train INTEGER,
        chat_template TEXT,
        block_count INTEGER,
        supports_thinking INTEGER NOT NULL DEFAULT 0,
        compatibility_status TEXT NOT NULL DEFAULT 'unvalidated',
        installed_at TEXT
      )
    ''');
    await db.execute('''
      INSERT OR IGNORE INTO models (
        id, display_name, source, compatibility_status
      ) VALUES (
        '${BundledModelManifest.id}', '${BundledModelManifest.displayName}',
        '${BundledModelManifest.source}', 'unvalidated'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_note_attachments (
        chat_id INTEGER NOT NULL,
        note_id INTEGER NOT NULL,
        position INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (chat_id, note_id),
        FOREIGN KEY (chat_id) REFERENCES chats(id) ON DELETE CASCADE,
        FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      DELETE FROM chat_persona
      WHERE rowid NOT IN (
        SELECT MAX(rowid) FROM chat_persona GROUP BY chat_id
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_persona_one_per_chat '
      'ON chat_persona(chat_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_messages_chat_cursor '
      'ON messages(chat_id, timestamp DESC, id DESC)',
    );
  }

  Future<void> _createV6Tables(DatabaseExecutor db) async {
    const modelColumns = <String, String>{
      'repository': 'TEXT',
      'revision': 'TEXT',
      'quantization': 'TEXT',
      'parameter_count': 'INTEGER',
      'license': 'TEXT',
      'remote_metadata_json': 'TEXT',
      'installation_state': "TEXT NOT NULL DEFAULT 'not_installed'",
      'last_used_at': 'TEXT',
      'update_revision': 'TEXT',
    };
    for (final entry in modelColumns.entries) {
      await _addColumnIfMissing(db, 'models', entry.key, entry.value);
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS model_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        model_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        local_path TEXT,
        byte_size INTEGER,
        sha256 TEXT,
        etag TEXT,
        shard_index INTEGER,
        shard_count INTEGER,
        UNIQUE(model_id, file_name),
        FOREIGN KEY (model_id) REFERENCES models(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS download_jobs (
        id TEXT PRIMARY KEY,
        model_id TEXT NOT NULL,
        repository TEXT NOT NULL,
        revision TEXT NOT NULL,
        state TEXT NOT NULL,
        downloaded_bytes INTEGER NOT NULL DEFAULT 0,
        total_bytes INTEGER,
        retry_count INTEGER NOT NULL DEFAULT 0,
        error_code TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (model_id) REFERENCES models(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_download_jobs_state '
      'ON download_jobs(state, updated_at DESC)',
    );
    await db.update(
      'models',
      {
        'repository': BundledModelManifest.repository,
        'revision': BundledModelManifest.revision,
        'quantization': BundledModelManifest.quantization,
        'parameter_count': BundledModelManifest.parameterCount,
      },
      where: 'id = ?',
      whereArgs: [BundledModelManifest.id],
    );
  }

  Future<void> _createV7Tables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hub_search_cache (
        cache_key TEXT PRIMARY KEY,
        payload_json TEXT NOT NULL,
        fetched_at TEXT NOT NULL,
        last_accessed_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_hub_search_cache_lru '
      'ON hub_search_cache(last_accessed_at ASC)',
    );
  }

  Future<int> insertChat(Map<String, dynamic> chat) async {
    final db = await database;
    return await db.insert('chats', chat);
  }

  /// Explicit recovery creates a chat and its selected model atomically.
  Future<int> insertChatWithModel(
    Map<String, dynamic> chat,
    String modelId, {
    void Function()? beforeCommit,
  }) async {
    final db = await database;
    return db.transaction((transaction) async {
      beforeCommit?.call();
      final id = await transaction.insert('chats', chat);
      await transaction.insert('model_settings', {
        ...ModelSettings(modelId: modelId).toJson(),
        'chat_id': id,
      });
      beforeCommit?.call();
      return id;
    });
  }

  Future<List<Chat>> getChats() async {
    final db = await database;
    final results = await db.query('chats', orderBy: 'updated_at DESC');
    return results.map((m) => Chat.fromMap(m)).toList();
  }

  Future<Chat?> getChat(int id) async {
    final db = await database;
    final results = await db.query('chats', where: 'id = ?', whereArgs: [id]);
    return results.isNotEmpty ? Chat.fromMap(results.first) : null;
  }

  Future<int> updateChat(int id, Map<String, dynamic> chat) async {
    final db = await database;
    return await db.update('chats', chat, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteChat(int id) async {
    final db = await database;
    return await db.delete('chats', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertMessage(Map<String, dynamic> message) async {
    final db = await database;
    return await db.insert('messages', message);
  }

  Future<List<Map<String, dynamic>>> getMessages(int chatId) async {
    final db = await database;
    return await db.query(
      'messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'timestamp ASC',
    );
  }

  Future<int> deleteMessage(int id) async {
    final db = await database;
    return await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Message>> getMessagesForChat(int chatId) async {
    final db = await database;
    final results = await db.query(
      'messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
      orderBy: 'timestamp ASC',
    );
    return results.map((m) => Message.fromMap(m)).toList();
  }

  Future<List<Message>> getMessagesForChatPaginated(
    int chatId, {
    int limit = 100,
    int? beforeId,
  }) async {
    final db = await database;
    final results = await db.query(
      'messages',
      where: beforeId == null ? 'chat_id = ?' : 'chat_id = ? AND id < ?',
      whereArgs: beforeId == null ? [chatId] : [chatId, beforeId],
      orderBy: 'id DESC',
      limit: limit,
    );
    return results.reversed.map((m) => Message.fromMap(m)).toList();
  }

  Future<List<Message>> getAllMessagesForExport(int chatId) =>
      getMessagesForChat(chatId);

  Future<List<Map<String, dynamic>>> getModels() async {
    final db = await database;
    return db.query('models', orderBy: 'display_name COLLATE NOCASE');
  }

  Future<Map<String, dynamic>?> getModel(String id) async {
    final db = await database;
    final rows = await db.query('models', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.single;
  }

  Future<Map<String, dynamic>?> getModelByPath(String localPath) async {
    final db = await database;
    final rows = await db.query(
      'models',
      where: 'local_path = ?',
      whereArgs: [localPath],
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> upsertModel(Map<String, dynamic> model) async {
    final db = await database;
    final id = model['id'] as String;
    final existing = await db.query(
      'models',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('models', model);
      return;
    }
    final values = Map<String, dynamic>.from(model)..remove('id');
    await db.update('models', values, where: 'id = ?', whereArgs: [id]);
  }

  /// Commits recovery of an unchanged identity and its optional single artifact
  /// together. A stale recovery may not replace a newer installation.
  Future<void> restoreModelInstallation(
    Map<String, Object?> restored, {
    required String expectedPath,
    required String expectedHash,
    required int? artifactId,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      final id = restored['id'];
      final rows = await transaction.query(
        'models',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.length != 1 ||
          rows.single['local_path'] != expectedPath ||
          rows.single['sha256'] != expectedHash ||
          restored['sha256'] != expectedHash ||
          (rows.single['byte_size'] != null &&
              restored['byte_size'] != rows.single['byte_size'])) {
        throw StateError('Model identity changed during recovery');
      }
      final artifacts = await transaction.query(
        'model_files',
        where: 'model_id = ?',
        whereArgs: [id],
      );
      if (artifactId == null
          ? artifacts.isNotEmpty
          : artifacts.length != 1 ||
                artifacts.single['id'] != artifactId ||
                artifacts.single['sha256'] != expectedHash ||
                artifacts.single['shard_count'] != 1 ||
                (artifacts.single['shard_index'] ?? 0) != 0 ||
                artifacts.single['local_path'] != expectedPath ||
                artifacts.single['byte_size'] != rows.single['byte_size']) {
        throw StateError('Model artifacts changed during recovery');
      }
      final values = Map<String, Object?>.from(restored)..remove('id');
      await transaction.update(
        'models',
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (artifactId != null) {
        await transaction.update(
          'model_files',
          {'local_path': restored['local_path']},
          where: 'id = ? AND model_id = ?',
          whereArgs: [artifactId, id],
        );
      }
    });
  }

  Future<void> clearModelInstallationByPath(String localPath) async {
    final db = await database;
    await db.update(
      'models',
      {
        'local_path': null,
        'sha256': null,
        'byte_size': null,
        'compatibility_status': 'unvalidated',
        'installed_at': null,
        'installation_state': 'not_installed',
      },
      where: 'local_path = ?',
      whereArgs: [localPath],
    );
  }

  Future<void> clearModelInstallation(String modelId) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.update(
        'models',
        {
          'local_path': null,
          'sha256': null,
          'byte_size': null,
          'compatibility_status': 'unvalidated',
          'installed_at': null,
          'installation_state': 'not_installed',
        },
        where: 'id = ?',
        whereArgs: [modelId],
      );
      await transaction.delete(
        'model_files',
        where: 'model_id = ?',
        whereArgs: [modelId],
      );
    });
  }

  Future<List<Map<String, dynamic>>> getModelFiles(String modelId) async {
    final db = await database;
    return db.query(
      'model_files',
      where: 'model_id = ?',
      whereArgs: [modelId],
      orderBy: 'COALESCE(shard_index, 0), file_name',
    );
  }

  Future<void> replaceModelFiles(
    String modelId,
    List<Map<String, Object?>> files,
  ) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'model_files',
        where: 'model_id = ?',
        whereArgs: [modelId],
      );
      for (final file in files) {
        await transaction.insert('model_files', {...file, 'model_id': modelId});
      }
    });
  }

  Future<void> upsertDownloadJob(Map<String, Object?> job) async {
    final db = await database;
    await db.insert(
      'download_jobs',
      job,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getDownloadJobs() async {
    final db = await database;
    return db.query('download_jobs', orderBy: 'updated_at DESC');
  }

  Future<Map<String, dynamic>?> getHubSearchCache(String cacheKey) async {
    final db = await database;
    final rows = await db.query(
      'hub_search_cache',
      where: 'cache_key = ?',
      whereArgs: [cacheKey],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> upsertHubSearchCache(Map<String, Object?> entry) async {
    final db = await database;
    await db.insert(
      'hub_search_cache',
      entry,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> touchHubSearchCache(String cacheKey, DateTime accessedAt) async {
    final db = await database;
    await db.update(
      'hub_search_cache',
      {'last_accessed_at': accessedAt.toUtc().toIso8601String()},
      where: 'cache_key = ?',
      whereArgs: [cacheKey],
    );
  }

  Future<void> pruneHubSearchCache({
    required DateTime oldestAllowed,
    required int maximumEntries,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'hub_search_cache',
        where: 'fetched_at < ?',
        whereArgs: [oldestAllowed.toUtc().toIso8601String()],
      );
      await transaction.rawDelete(
        'DELETE FROM hub_search_cache WHERE cache_key IN ('
        'SELECT cache_key FROM hub_search_cache '
        'ORDER BY last_accessed_at DESC LIMIT -1 OFFSET ?)',
        [maximumEntries],
      );
    });
  }

  Future<List<Note>> getAttachedNotes(int chatId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT n.* FROM notes n
      INNER JOIN chat_note_attachments a ON a.note_id = n.id
      WHERE a.chat_id = ?
      ORDER BY a.position ASC, n.id ASC
    ''',
      [chatId],
    );
    return rows.map(Note.fromMap).toList();
  }

  Future<void> attachNote(int chatId, int noteId) async {
    final db = await database;
    final maxPosition = await db.rawQuery(
      'SELECT COALESCE(MAX(position), -1) + 1 AS next_position '
      'FROM chat_note_attachments WHERE chat_id = ?',
      [chatId],
    );
    await db.insert('chat_note_attachments', {
      'chat_id': chatId,
      'note_id': noteId,
      'position': maxPosition.first['next_position'] as int,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> detachNote(int chatId, int noteId) async {
    final db = await database;
    await db.delete(
      'chat_note_attachments',
      where: 'chat_id = ? AND note_id = ?',
      whereArgs: [chatId, noteId],
    );
  }

  Future<int> insertNote(Map<String, dynamic> note) async {
    final db = await database;
    return await db.insert('notes', note);
  }

  Future<List<Map<String, dynamic>>> getNotes() async {
    final db = await database;
    return await db.query('notes', orderBy: 'updated_at DESC');
  }

  Future<Map<String, dynamic>?> getNote(int id) async {
    final db = await database;
    final results = await db.query('notes', where: 'id = ?', whereArgs: [id]);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateNote(int id, Map<String, dynamic> note) async {
    final db = await database;
    return await db.update('notes', note, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteNote(int id) async {
    final db = await database;
    return await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertPersona(Map<String, dynamic> persona) async {
    final db = await database;
    return await db.insert('personas', persona);
  }

  Future<List<Map<String, dynamic>>> getPersonas() async {
    final db = await database;
    return await db.query('personas');
  }

  Future<Map<String, dynamic>?> getPersona(int id) async {
    final db = await database;
    final results = await db.query(
      'personas',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<Map<String, dynamic>?> getDefaultPersona() async {
    final db = await database;
    final results = await db.query(
      'personas',
      where: 'is_default = ?',
      whereArgs: [1],
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updatePersona(int id, Map<String, dynamic> persona) async {
    final db = await database;
    return await db.update(
      'personas',
      persona,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deletePersona(int id) async {
    final db = await database;
    return await db.delete('personas', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> setChatPersona(int chatId, int personaId) async {
    final db = await database;
    return await db.insert('chat_persona', {
      'chat_id': chatId,
      'persona_id': personaId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int?> getChatPersona(int chatId) async {
    final db = await database;
    final results = await db.query(
      'chat_persona',
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );
    return results.isNotEmpty ? results.first['persona_id'] as int? : null;
  }

  Future<int> removeChatPersona(int chatId) async {
    final db = await database;
    return await db.delete(
      'chat_persona',
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );
  }

  Future<int> removeChatPersonaByPersona(int personaId) async {
    final db = await database;
    return await db.delete(
      'chat_persona',
      where: 'persona_id = ?',
      whereArgs: [personaId],
    );
  }

  Future<int> insertModelSettings(Map<String, dynamic> settings) async {
    final db = await database;
    return await db.insert('model_settings', settings);
  }

  Future<Map<String, dynamic>?> getModelSettings(int chatId) async {
    final db = await database;
    final results = await db.query(
      'model_settings',
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// Changes only model identity; existing sampling and prompt settings survive.
  Future<void> assignModelForChat(int chatId, String modelId) async {
    final db = await database;
    await db.transaction((txn) async {
      final chats = await txn.query(
        'chats',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [chatId],
      );
      if (chats.isEmpty) throw StateError('Chat unavailable');
      final changed = await txn.update(
        'model_settings',
        {'model_id': modelId},
        where: 'chat_id = ?',
        whereArgs: [chatId],
      );
      if (changed == 0) {
        await txn.insert('model_settings', {
          ...ModelSettings(modelId: modelId).toJson(),
          'chat_id': chatId,
        });
      }
    });
  }

  Future<int> updateModelSettings(
    int chatId,
    Map<String, dynamic> settings,
  ) async {
    final db = await database;
    return await db.update(
      'model_settings',
      settings,
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );
  }

  Future<void> close() async {
    _initFuture = null;
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
      _database = null;
    }
  }

  /// Returns whether the database connection is currently open.
  bool get isOpen => _database?.isOpen ?? false;

  /// Runs maintenance only when explicitly scheduled by an idle coordinator.
  Future<void> vacuumIfNeeded() async {
    try {
      final db = await database;
      final pageCount = await db.rawQuery('PRAGMA page_count');
      final freeCount = await db.rawQuery('PRAGMA freelist_count');
      if (pageCount.isNotEmpty && freeCount.isNotEmpty) {
        final total = pageCount.first.values.first as int;
        final free = freeCount.first.values.first as int;
        if (total > 0 && (free / total) > 0.2) {
          await db.execute('VACUUM');
        }
      }
    } catch (error) {
      unawaited(
        AppLogger.instance.warningFailure(
          'Idle database maintenance deferred',
          error,
        ),
      );
    }
  }
}
