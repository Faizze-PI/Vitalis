import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/models/note.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:vitalis_app/constants/app_constants.dart';
import 'package:vitalis_app/models/hub_model.dart';
import 'package:vitalis_app/services/persistent_hub_search_cache.dart';
import 'package:vitalis_app/providers/note_provider.dart';
import 'package:vitalis_app/providers/persona_provider.dart';
import 'package:vitalis_app/models/persona.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/providers/chat_provider.dart';
import 'package:vitalis_app/providers/generation_provider.dart';

void main() {
  late Directory testDatabaseDirectory;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    testDatabaseDirectory = Directory.systemTemp.createTempSync(
      'vitalis_database_test_',
    );
    await databaseFactory.setDatabasesPath(testDatabaseDirectory.path);
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await testDatabaseDirectory.exists()) {
      await testDatabaseDirectory.delete(recursive: true);
    }
  });

  setUp(() async {
    await DatabaseHelper.instance.close();
    final dbPath = await databaseFactory.getDatabasesPath();
    final file = File(p.join(dbPath, 'vitalis.db'));
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 50));
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  });

  group('DatabaseHelper', () {
    test(
      'failed or missing persona update cannot publish a committed change',
      () async {
        final db = DatabaseHelper.instance;
        final chat = ChatProvider(database: db);
        var commits = 0;
        final personas = PersonaProvider(
          database: db,
          onCommittedChange: (id, persona) {
            commits++;
            chat.applyPersonaChange(id, persona);
          },
        );
        addTearDown(personas.dispose);
        addTearDown(chat.close);
        await chat.createChat(title: 'Disposable failed edit');
        final original = (await personas.createPersona('Original', 'Old'))!;
        await chat.setPersona(original);
        final sqlite = await db.database;
        await sqlite.execute('''
        CREATE TEMP TRIGGER reject_disposable_persona_update
        BEFORE UPDATE ON personas
        BEGIN SELECT RAISE(ABORT, 'Disposable update failure'); END
      ''');
        await personas.updatePersona(
          original.copyWith(systemPrompt: 'Rejected'),
        );
        expect(commits, 0);
        expect(chat.currentPersona?.systemPrompt, 'Old');
        expect((await db.getPersona(original.id!))!['system_prompt'], 'Old');
        await sqlite.execute('DROP TRIGGER reject_disposable_persona_update');
        await personas.updatePersona(
          original.copyWith(id: original.id! + 1, systemPrompt: 'Missing'),
        );
        expect(commits, 0);
        expect(chat.currentPersona?.systemPrompt, 'Old');
        await personas.updatePersona(
          original.copyWith(systemPrompt: 'Accepted'),
        );
        expect(commits, 1);
        expect(chat.currentPersona?.systemPrompt, 'Accepted');
      },
    );
    for (final deleting in [false, true]) {
      test(
        'committed persona ${deleting ? 'deletion' : 'edit'} reaches chat',
        () async {
          final db = DatabaseHelper.instance;
          final chat = ChatProvider(database: db);
          final personas = PersonaProvider(
            database: db,
            onCommittedChange: chat.applyPersonaChange,
          );
          addTearDown(personas.dispose);
          addTearDown(chat.close);
          final selected = (await chat.createChat(
            title: 'Disposable persona sync',
          ))!;
          final original = (await personas.createPersona(
            'Original',
            'Old instructions',
          ))!;
          await chat.setPersona(original);
          if (deleting) {
            expect(await personas.deletePersona(original.id!), isTrue);
          } else {
            await personas.updatePersona(
              original.copyWith(
                name: 'Edited',
                systemPrompt: 'New instructions',
              ),
            );
          }
          final generation = _PersonaGeneration();
          chat.setGenerationProvider(generation);
          await chat.sendMessage('Disposable prompt');
          expect(generation.called, isTrue);
          expect(
            generation.received?.systemPrompt,
            deleting ? isNull : 'New instructions',
          );
          expect(
            chat.currentPersona?.systemPrompt,
            deleting ? isNull : 'New instructions',
          );
          expect(
            await db.getChatPersona(selected.id!),
            deleting ? isNull : original.id,
          );
        },
      );
    }
    test('failed persona deletion preserves its chat assignment', () async {
      final db = DatabaseHelper.instance;
      final chatId = await db.insertChat({
        'title': 'Disposable deletion',
        'created_at': DateTime(2026).toIso8601String(),
        'updated_at': DateTime(2026).toIso8601String(),
      });
      final personas = PersonaProvider(database: db);
      addTearDown(personas.dispose);
      final persona = (await personas.createPersona('Original', 'Test'))!;
      await db.setChatPersona(chatId, persona.id!);
      final sqlite = await db.database;
      await sqlite.execute('''
        CREATE TEMP TRIGGER reject_disposable_persona_delete
        BEFORE DELETE ON personas
        BEGIN SELECT RAISE(ABORT, 'Disposable storage failure'); END
      ''');
      expect(await personas.deletePersona(persona.id!), isFalse);
      expect(await db.getPersona(persona.id!), isNotNull);
      expect(await db.getChatPersona(chatId), persona.id);
      expect(personas.personas.any((p) => p.id == persona.id), isTrue);
      await sqlite.execute('DROP TRIGGER reject_disposable_persona_delete');
      expect(await personas.deletePersona(persona.id!), isTrue);
      expect(await db.getPersona(persona.id!), isNull);
      expect(await db.getChatPersona(chatId), isNull);
      expect(await personas.deletePersona(persona.id!), isFalse);
    });
    test('failed persona replacement preserves the previous mapping', () async {
      final db = DatabaseHelper.instance;
      final chatId = await db.insertChat({
        'title': 'Disposable persona replacement',
        'created_at': DateTime(2026).toIso8601String(),
        'updated_at': DateTime(2026).toIso8601String(),
      });
      final personaId = await db.insertPersona(
        Persona(name: 'Original', systemPrompt: 'Test').toMap(),
      );
      await db.setChatPersona(chatId, personaId);
      await expectLater(
        db.setChatPersona(chatId, personaId + 1),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.getChatPersona(chatId), personaId);
    });
    test(
      'note and persona providers persist edits and reload before deletion',
      () async {
        final notes = NoteProvider(database: DatabaseHelper.instance);
        final personas = PersonaProvider(database: DatabaseHelper.instance);
        addTearDown(notes.dispose);
        addTearDown(personas.dispose);
        final note = await notes.createNote('Disposable', 'Initial');
        final persona = await personas.createPersona('Disposable', 'Initial');
        expect(note, isNotNull);
        expect(persona, isNotNull);
        await notes.updateNote(
          Note(id: note!.id, title: 'Edited', content: 'Saved'),
        );
        await personas.updatePersona(
          Persona(id: persona!.id, name: 'Edited', systemPrompt: 'Saved'),
        );
        await notes.loadNotes();
        await personas.loadPersonas();
        expect(
          notes.notes.singleWhere((item) => item.id == note.id).content,
          'Saved',
        );
        expect(
          personas.personas
              .singleWhere((item) => item.id == persona.id)
              .systemPrompt,
          'Saved',
        );
        expect(notes.isLoading, isFalse);
        expect(personas.isLoading, isFalse);
        await notes.deleteNote(note.id!);
        await personas.deletePersona(persona.id!);
        expect(notes.notes.where((item) => item.id == note.id), isEmpty);
        expect(
          personas.personas.where((item) => item.id == persona.id),
          isEmpty,
        );
      },
    );
    test(
      'model-only assignment preserves settings and rejects missing chats',
      () async {
        final db = DatabaseHelper.instance;
        final stamp = DateTime(2026).toIso8601String();
        final chat = await db.insertChat({
          'title': 'Disposable',
          'created_at': stamp,
          'updated_at': stamp,
        });
        await db.assignModelForChat(chat, 'fixture-one');
        await db.updateModelSettings(chat, {
          'system_prompt': 'Disposable custom instructions',
          'temperature': 0.23,
        });
        final before = await db.getModelSettings(chat);
        await db.assignModelForChat(chat, 'fixture-two');
        final after = await db.getModelSettings(chat);
        expect(after, {...before!, 'model_id': 'fixture-two'});
        await expectLater(
          db.assignModelForChat(chat + 1, 'fixture-three'),
          throwsStateError,
        );
        expect(await db.getModelSettings(chat + 1), isNull);
      },
    );
    test('insert and retrieve chats', () async {
      final db = DatabaseHelper.instance;
      final now = DateTime.now().toIso8601String();
      final id = await db.insertChat({
        'title': 'Test Chat',
        'created_at': now,
        'updated_at': now,
      });
      expect(id, greaterThan(0));
    });

    test('insert and retrieve messages', () async {
      final db = DatabaseHelper.instance;
      final now = DateTime.now().toIso8601String();
      final chatId = await db.insertChat({
        'title': 'Chat',
        'created_at': now,
        'updated_at': now,
      });

      final message = Message(
        chatId: chatId,
        role: MessageRole.user,
        content: 'Hello',
      );
      final msgId = await db.insertMessage(message.toMap());
      expect(msgId, greaterThan(0));

      final messages = await db.getMessagesForChat(chatId);
      expect(messages.length, 1);
      expect(messages.first.content, 'Hello');
      expect(messages.first.role, MessageRole.user);
    });

    test('insert and retrieve notes', () async {
      final db = DatabaseHelper.instance;
      final note = Note(title: 'Test Note', content: 'Test content');
      final id = await db.insertNote(note.toMap());
      expect(id, greaterThan(0));

      final notes = await db.getNotes();
      expect(notes.length, 1);
      expect(notes.first['title'], 'Test Note');
    });

    test('supports complete CRUD and per-chat settings lifecycle', () async {
      final db = DatabaseHelper.instance;
      final now = DateTime.utc(2026).toIso8601String();
      final chatId = await db.insertChat({
        'title': 'Original',
        'created_at': now,
        'updated_at': now,
      });
      expect((await db.getChat(chatId))!.title, 'Original');
      expect(await db.updateChat(chatId, {'title': 'Renamed'}), 1);
      expect((await db.getChats()).single.title, 'Renamed');

      final messageId = await db.insertMessage(
        Message(chatId: chatId, role: MessageRole.user, content: 'one').toMap(),
      );
      expect((await db.getMessages(chatId)).single['content'], 'one');
      expect(await db.deleteMessage(messageId), 1);
      expect(await db.getMessages(chatId), isEmpty);

      final noteId = await db.insertNote(
        Note(title: 'A', content: 'first').toMap(),
      );
      expect((await db.getNote(noteId))!['content'], 'first');
      expect(await db.updateNote(noteId, {'content': 'changed'}), 1);
      expect((await db.getNotes()).single['content'], 'changed');
      expect(await db.deleteNote(noteId), 1);

      final personaId = await db.insertPersona({
        'name': 'Focused',
        'system_prompt': 'Be concise',
      });
      expect((await db.getPersona(personaId))!['name'], 'Focused');
      expect(await db.updatePersona(personaId, {'name': 'Updated'}), 1);
      expect(await db.setChatPersona(chatId, personaId), greaterThan(0));
      expect(await db.getChatPersona(chatId), personaId);
      expect(await db.removeChatPersonaByPersona(personaId), 1);
      expect(await db.removeChatPersona(chatId), 0);
      expect(await db.deletePersona(personaId), 1);

      await db.insertModelSettings({'chat_id': chatId});
      expect((await db.getModelSettings(chatId))!['thinking_mode'], 'off');
      expect(await db.updateModelSettings(chatId, {'thinking_mode': 'on'}), 1);
      expect((await db.getModelSettings(chatId))!['thinking_mode'], 'on');

      await db.upsertModel({
        'id': 'local-model',
        'display_name': 'Local',
        'local_path': '/controlled/local.gguf',
        'source': 'imported',
        'compatibility_status': 'compatible',
      });
      expect(
        (await db.getModelByPath('/controlled/local.gguf'))!['id'],
        'local-model',
      );
      await db.clearModelInstallationByPath('/controlled/local.gguf');
      expect(
        (await db.getModel('local-model'))!['installation_state'],
        'not_installed',
      );

      expect(await db.deleteChat(chatId), 1);
      expect(await db.getChat(chatId), isNull);
    });

    test('default persona is created', () async {
      final db = DatabaseHelper.instance;
      final defaultPersona = await db.getDefaultPersona();
      expect(defaultPersona, isNotNull);
      expect(defaultPersona!['name'], 'Default Assistant');
      expect(defaultPersona['is_default'], 1);
    });

    test('delete chat removes messages via cascade', () async {
      final db = DatabaseHelper.instance;
      final now = DateTime.now().toIso8601String();
      final chatId = await db.insertChat({
        'title': 'To Delete',
        'created_at': now,
        'updated_at': now,
      });

      await db.insertMessage(
        Message(
          chatId: chatId,
          role: MessageRole.user,
          content: 'Message',
        ).toMap(),
      );

      await db.deleteChat(chatId);

      final chats = await db.getChats();
      expect(chats.where((c) => c.id == chatId).length, 0);

      final messages = await db.getMessagesForChat(chatId);
      expect(messages.length, 0);
    });

    test(
      'cursor pagination returns newest page then genuinely older pages',
      () async {
        final db = DatabaseHelper.instance;
        final now = DateTime.now().toIso8601String();
        final chatId = await db.insertChat({
          'title': 'Long Chat',
          'created_at': now,
          'updated_at': now,
        });
        for (var index = 0; index < 1005; index++) {
          await db.insertMessage(
            Message(
              chatId: chatId,
              role: MessageRole.user,
              content: 'message-$index',
              timestamp: DateTime(2026, 1, 1).add(Duration(seconds: index)),
            ).toMap(),
          );
        }

        final newest = await db.getMessagesForChatPaginated(chatId, limit: 100);
        expect(newest.first.content, 'message-905');
        expect(newest.last.content, 'message-1004');
        final older = await db.getMessagesForChatPaginated(
          chatId,
          limit: 100,
          beforeId: newest.first.id,
        );
        expect(older.first.content, 'message-805');
        expect(older.last.content, 'message-904');
        expect(await db.getAllMessagesForExport(chatId), hasLength(1005));
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );

    test('multiple note attachments persist in explicit order', () async {
      final db = DatabaseHelper.instance;
      final now = DateTime.now().toIso8601String();
      final chatId = await db.insertChat({
        'title': 'Notes',
        'created_at': now,
        'updated_at': now,
      });
      final first = await db.insertNote(
        Note(title: 'First', content: 'A').toMap(),
      );
      final second = await db.insertNote(
        Note(title: 'Second', content: 'B').toMap(),
      );
      await db.attachNote(chatId, second);
      await db.attachNote(chatId, first);
      expect((await db.getAttachedNotes(chatId)).map((note) => note.title), [
        'Second',
        'First',
      ]);
      await db.detachNote(chatId, second);
      expect((await db.getAttachedNotes(chatId)).single.title, 'First');
    });

    test('upgrades a version-3 fixture without losing user data', () async {
      final now = DateTime.now().toIso8601String();
      await DatabaseHelper.instance.close();
      final dbPath = await databaseFactory.getDatabasesPath();
      final path = p.join(dbPath, AppConstants.databaseName);
      final fixture = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE chats (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE messages (id INTEGER PRIMARY KEY AUTOINCREMENT, chat_id INTEGER NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL, timestamp TEXT NOT NULL, is_error INTEGER NOT NULL DEFAULT 0)',
            );
            await db.execute(
              'CREATE TABLE notes (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, content TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE personas (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, system_prompt TEXT NOT NULL, is_default INTEGER NOT NULL DEFAULT 0)',
            );
            await db.execute(
              'CREATE TABLE chat_persona (chat_id INTEGER NOT NULL, persona_id INTEGER NOT NULL, PRIMARY KEY (chat_id, persona_id))',
            );
            await db.execute(
              "CREATE TABLE model_settings (id INTEGER PRIMARY KEY AUTOINCREMENT, chat_id INTEGER NOT NULL UNIQUE, temperature REAL NOT NULL DEFAULT 0.7, top_k INTEGER NOT NULL DEFAULT 40, top_p REAL NOT NULL DEFAULT 0.9, max_tokens INTEGER NOT NULL DEFAULT 2048, system_prompt TEXT NOT NULL DEFAULT 'You are a helpful assistant.')",
            );
            await db.insert('chats', {
              'title': 'Preserved',
              'created_at': now,
              'updated_at': now,
            });
            await db.insert('messages', {
              'chat_id': 1,
              'role': 'user',
              'content': 'Keep me',
              'timestamp': now,
              'is_error': 0,
            });
            await db.insert('notes', {
              'title': 'Keep note',
              'content': 'Data',
              'created_at': now,
              'updated_at': now,
            });
            await db.insert('personas', {
              'name': 'Keep persona',
              'system_prompt': 'Stay',
              'is_default': 1,
            });
            await db.insert('model_settings', {'chat_id': 1});
          },
        ),
      );
      await fixture.close();

      final upgraded = DatabaseHelper.instance;
      expect((await upgraded.getChats()).single.title, 'Preserved');
      expect((await upgraded.getMessagesForChat(1)).single.content, 'Keep me');
      expect((await upgraded.getNotes()).single['title'], 'Keep note');
      expect((await upgraded.getPersonas()).single['name'], 'Keep persona');
      expect((await upgraded.getModels()).single['id'], 'qwen3.5-0.8b-q4-k-m');
      final modelColumns = await (await upgraded.database).rawQuery(
        'PRAGMA table_info(models)',
      );
      final modelColumnNames = modelColumns
          .map((column) => column['name'])
          .toSet();
      expect(
        modelColumnNames,
        containsAll([
          'block_count',
          'supports_thinking',
          'repository',
          'revision',
          'parameter_count',
          'installation_state',
        ]),
      );
      final tables = await (await upgraded.database).rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      expect(
        tables.map((table) => table['name']),
        containsAll(['model_files', 'download_jobs', 'hub_search_cache']),
      );
      expect((await upgraded.getModelSettings(1))!['thinking_mode'], 'off');
    });

    for (final fixtureVersion in [4, 5, 6]) {
      test(
        'upgrades a version-$fixtureVersion fixture to current schema',
        () async {
          await DatabaseHelper.instance.close();
          final dbPath = await databaseFactory.getDatabasesPath();
          final path = p.join(dbPath, AppConstants.databaseName);
          final fixture = await databaseFactory.openDatabase(
            path,
            options: OpenDatabaseOptions(
              version: fixtureVersion,
              onCreate: (db, _) async {
                await db.execute(
                  'CREATE TABLE preserved_data (value TEXT NOT NULL)',
                );
                await db.insert('preserved_data', {'value': 'keep'});
                await db.execute('''
                CREATE TABLE models (
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
                  ${fixtureVersion >= 5 ? 'block_count INTEGER,' : ''}
                  ${fixtureVersion >= 5 ? 'supports_thinking INTEGER NOT NULL DEFAULT 0,' : ''}
                  compatibility_status TEXT NOT NULL DEFAULT 'unvalidated',
                  installed_at TEXT
                )
              ''');
              },
            ),
          );
          await fixture.close();

          final upgraded = await DatabaseHelper.instance.database;
          final preserved = await upgraded.query('preserved_data');
          expect(preserved.single['value'], 'keep');
          final tables = await upgraded.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'table'",
          );
          expect(
            tables.map((table) => table['name']),
            containsAll(['model_files', 'download_jobs', 'hub_search_cache']),
          );
        },
      );
    }

    test('updating a model preserves its shard records', () async {
      final db = DatabaseHelper.instance;
      await db.upsertModel({
        'id': 'test-model',
        'display_name': 'Test',
        'source': 'huggingface',
        'compatibility_status': 'pending_validation',
        'installation_state': 'downloading',
      });
      await db.replaceModelFiles('test-model', [
        {
          'file_name': 'test-00001-of-00002.gguf',
          'byte_size': 10,
          'shard_index': 1,
          'shard_count': 2,
        },
        {
          'file_name': 'test-00002-of-00002.gguf',
          'byte_size': 20,
          'shard_index': 2,
          'shard_count': 2,
        },
      ]);
      final current = (await db.getModel('test-model'))!;
      await db.upsertModel({...current, 'installation_state': 'validating'});
      expect(await db.getModelFiles('test-model'), hasLength(2));
    });

    test('version-7 Hub search cache is persistent and prunable', () async {
      final db = DatabaseHelper.instance;
      final now = DateTime.utc(2026, 9, 2);
      await db.upsertHubSearchCache({
        'cache_key': 'query',
        'payload_json': '{"models":[],"nextUrl":null}',
        'fetched_at': now.toIso8601String(),
        'last_accessed_at': now.toIso8601String(),
      });
      expect((await db.getHubSearchCache('query'))!['cache_key'], 'query');
      await db.pruneHubSearchCache(
        oldestAllowed: now.add(const Duration(days: 1)),
        maximumEntries: 100,
      );
      expect(await db.getHubSearchCache('query'), isNull);
    });

    test('Hub cache distinguishes fresh stale and expired results', () async {
      var now = DateTime.utc(2026, 9, 2);
      final cache = DatabaseHubSearchCache(clock: () => now);
      final page = HubSearchPage(
        models: [
          HubModelSummary(
            id: 'publisher/model',
            revision: 'a' * 40,
            downloads: 1,
            gated: false,
            tags: const ['gguf'],
          ),
        ],
      );
      await cache.write('freshness', page);
      expect((await cache.read('freshness'))!.isFresh, isTrue);

      now = now.add(const Duration(hours: 7));
      final stale = await cache.read('freshness');
      expect(stale, isNotNull);
      expect(stale!.isFresh, isFalse);
      expect(stale.page.models.single.id, 'publisher/model');

      now = now.add(const Duration(days: 31));
      expect(await cache.read('freshness'), isNull);
    });

    test('Hub cache keeps at most one hundred LRU entries', () async {
      final db = DatabaseHelper.instance;
      final base = DateTime.utc(2026, 9, 2);
      for (var index = 0; index < 101; index++) {
        final timestamp = base.add(Duration(seconds: index));
        await db.upsertHubSearchCache({
          'cache_key': 'entry-$index',
          'payload_json': '{"models":[],"nextUrl":null}',
          'fetched_at': timestamp.toIso8601String(),
          'last_accessed_at': timestamp.toIso8601String(),
        });
      }
      await db.pruneHubSearchCache(
        oldestAllowed: base.subtract(const Duration(days: 1)),
        maximumEntries: 100,
      );
      final count = await (await db.database).rawQuery(
        'SELECT COUNT(*) AS count FROM hub_search_cache',
      );
      expect(count.single['count'], 100);
      expect(await db.getHubSearchCache('entry-0'), isNull);
      expect(await db.getHubSearchCache('entry-100'), isNotNull);
    });

    test(
      'uninstall state preserves model identity and clears only its files',
      () async {
        final db = DatabaseHelper.instance;
        await db.upsertModel({
          'id': 'test-model',
          'display_name': 'Test',
          'local_path': '/controlled/test.gguf',
          'source': 'huggingface',
          'sha256': 'abc',
          'byte_size': 10,
          'compatibility_status': 'compatible',
          'installation_state': 'installed',
        });
        await db.replaceModelFiles('test-model', [
          {
            'file_name': 'test.gguf',
            'local_path': '/controlled/test.gguf',
            'byte_size': 10,
            'sha256': 'abc',
          },
        ]);

        await db.clearModelInstallation('test-model');

        final retained = (await db.getModel('test-model'))!;
        expect(retained['installation_state'], 'not_installed');
        expect(retained['local_path'], isNull);
        expect(retained['sha256'], isNull);
        expect(await db.getModelFiles('test-model'), isEmpty);
      },
    );
  });
}

final class _PersonaGeneration implements GenerationProvider {
  Persona? received;
  bool called = false;
  @override
  bool get isSending => false;
  @override
  Future<void> startGeneration({
    required List<Message> messages,
    required ModelSettings settings,
    Persona? persona,
    List<Note> attachedNotes = const [],
  }) async {
    called = true;
    received = persona;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
