import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/providers/chat_provider.dart';
import 'package:vitalis_app/providers/generation_provider.dart';
import 'package:vitalis_app/providers/note_provider.dart';
import 'package:vitalis_app/providers/persona_provider.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/services/chat_state_controller.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';
import 'package:vitalis_app/services/model_warmup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  for (final dispose in [true, false]) {
    test(
      'pending completion preserves its chat without stale publication (dispose: $dispose)',
      () async {
        final database = _DelayedCompletionDatabase();
        final sentinel = _SafeSentinel();
        final warmup = ModelWarmupService(sentinel: sentinel);
        final generation = GenerationProvider(
          controller: ChatStateController(sentinel: sentinel),
          warmup: warmup,
        );
        final provider = ChatProvider(database: database)
          ..setGenerationProvider(generation);
        addTearDown(() async {
          await provider.close();
          generation.dispose();
          await warmup.close();
        });
        final first = await provider.createChat(title: 'First fixture');
        generation.onGenerationComplete!('fixture reply');
        await database.entered.future;
        if (dispose) {
          final closing = provider.close();
          expect(provider.close(), same(closing));
          var settled = false;
          unawaited(closing.then<void>((_) => settled = true));
          await Future<void>.delayed(Duration.zero);
          expect(
            settled,
            isFalse,
            reason: 'Close must retain pending database ownership',
          );
          expect(
            () => generation.clearError(),
            returnsNormally,
            reason:
                'Chat provider borrows generation, not its disposal authority',
          );
        } else {
          await provider.createChat(title: 'Second fixture');
        }
        database.release.complete();
        await database.updated.future;
        // The fake database futures are completed; drain their continuations,
        // not a wall-clock assumption about SQLite speed.
        await Future<void>.delayed(Duration.zero);
        await provider.drainPendingPersistence();
        if (dispose) await provider.close();
        expect(database.savedChatId, first!.id);
        if (!dispose) expect(provider.messages, isEmpty);
      },
    );
  }
  late Directory testDatabaseDirectory;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    testDatabaseDirectory = Directory.systemTemp.createTempSync(
      'vitalis_provider_test_',
    );
    await databaseFactory.setDatabasesPath(testDatabaseDirectory.path);
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    if (await testDatabaseDirectory.exists()) {
      await testDatabaseDirectory.delete(recursive: true);
    }
  });

  group('ChatProvider', () {
    test('initial state is empty', () {
      final provider = ChatProvider();
      expect(provider.chats, isEmpty);
      expect(provider.messages, isEmpty);
      expect(provider.currentChat, isNull);
      expect(provider.isLoading, false);
    });

    test('createChat adds a new chat', () async {
      final provider = ChatProvider();
      final chat = await provider.createChat(title: 'Test');
      expect(chat, isNotNull);
      expect(chat!.title, 'Test');
    });

    test('sendMessage with no current chat does nothing', () async {
      final provider = ChatProvider();
      await provider.sendMessage('Hello');
      expect(provider.messages, isEmpty);
    });

    test('default settings have correct values', () {
      final settings = ModelSettings();
      expect(settings.temperature, 0.7);
      expect(settings.topK, 40);
      expect(settings.topP, 0.9);
      expect(settings.maxTokens, 2048);
    });

    test('loads selects renames and deletes persisted chats', () async {
      final provider = ChatProvider();
      final first = await provider.createChat(title: 'First');
      await provider.createChat(title: 'Second');
      await DatabaseHelper.instance.insertMessage(
        Message(
          chatId: first!.id!,
          role: MessageRole.user,
          content: 'persisted',
        ).toMap(),
      );

      await provider.loadChats();
      expect(
        provider.chats.map((chat) => chat.title),
        containsAll(['First', 'Second']),
      );

      await provider.selectChat(first.id!);
      expect(provider.currentChat?.id, first.id);
      expect(provider.messages.single.content, 'persisted');

      await provider.updateChatTitle(first.id!, 'Renamed');
      expect(provider.currentChat?.title, 'Renamed');

      await provider.deleteChat(first.id!);
      expect(provider.chats.any((chat) => chat.id == first.id), isFalse);
      expect(provider.currentChat, isNotNull);
    });

    test('persists settings persona and multiple note attachments', () async {
      final provider = ChatProvider();
      final chat = await provider.createChat(title: 'Context');
      final noteProvider = NoteProvider();
      final personaProvider = PersonaProvider();
      final noteA = await noteProvider.createNote('A', 'Alpha');
      final noteB = await noteProvider.createNote('B', 'Beta');
      final persona = await personaProvider.createPersona(
        'Careful',
        'Be precise',
      );

      await provider.attachNote(noteA);
      await provider.attachNote(noteA);
      await provider.attachNote(noteB);
      await provider.setPersona(persona!);
      await provider.updateSettings(
        provider.settings.copyWith(systemPrompt: 'Local prompt'),
      );

      expect(provider.attachedNotes, hasLength(2));
      expect(provider.attachedNote?.title, 'A');
      expect(provider.currentPersona?.name, 'Careful');
      expect(provider.settings.systemPrompt, 'Local prompt');

      await provider.clearAttachedNote(noteA);
      expect(provider.attachedNotes.single.title, 'B');
      await provider.clearAttachedNote();
      await provider.removePersona();
      expect(provider.attachedNotes, isEmpty);
      expect(provider.currentPersona, isNull);

      final restored = ChatProvider();
      await restored.selectChat(chat!.id!);
      expect(restored.settings.systemPrompt, 'Local prompt');
      expect(restored.attachedNotes, isEmpty);
      expect(restored.currentPersona, isNull);
    });

    test('validates message title and system prompt storage bounds', () async {
      final provider = ChatProvider();
      final chat = await provider.createChat(title: 'Limits');

      await provider.sendMessage('   ');
      await provider.updateChatTitle(chat!.id!, List.filled(257, 'x').join());
      expect(provider.hasError, isTrue);
      expect(provider.errorMessage, contains('256'));

      provider.clearError();
      final savedSettings = provider.settings;
      await expectLater(
        provider.updateSettings(
          provider.settings.copyWith(
            systemPrompt: List.filled(1024 * 1024 + 1, 'x').join(),
          ),
        ),
        throwsArgumentError,
      );
      expect(provider.settings, same(savedSettings));
      expect(provider.hasError, isTrue);
      expect(provider.errorMessage, contains('1 MiB'));
    });

    test('sends retries regenerates and pages older messages', () async {
      final provider = ChatProvider();
      final chat = await provider.createChat(title: 'Messages');
      await provider.sendMessage('first');
      expect(provider.messages.single.content, 'first');

      await provider.retryLastMessage();
      expect(
        provider.messages.where((message) => message.role == MessageRole.user),
        hasLength(2),
      );

      final assistantId = await DatabaseHelper.instance.insertMessage(
        Message(
          chatId: chat!.id!,
          role: MessageRole.assistant,
          content: 'answer',
        ).toMap(),
      );
      await provider.selectChat(chat.id!);
      expect(provider.messages.last.id, assistantId);
      await provider.regenerate();
      expect(provider.messages.last.role, MessageRole.user);

      for (var index = 0; index < 105; index++) {
        await DatabaseHelper.instance.insertMessage(
          Message(
            chatId: chat.id!,
            role: MessageRole.user,
            content: 'page-$index',
          ).toMap(),
        );
      }
      await provider.selectChat(chat.id!);
      expect(provider.hasOlderMessages, isTrue);
      final newestCount = provider.messages.length;
      await provider.loadOlderMessages();
      expect(provider.messages.length, greaterThan(newestCount));
    });

    test('local updates and no-chat attachment guards are stable', () async {
      final provider = ChatProvider();
      final note = NoteProvider();
      final created = await note.createNote('Detached', 'content');

      await provider.attachNote(created);
      await provider.clearAttachedNote(created);
      await provider.removePersona();
      await provider.loadOlderMessages();
      await provider.stopSending();
      await provider.prepareModelRemoval('missing');
      provider.updateSettingsLocally(provider.settings.copyWith(maxTokens: 99));

      expect(provider.settings.maxTokens, 99);
      expect(provider.contextUsage, 0);
      expect(provider.generatingContent, isNull);
      expect(provider.isCurrentModel(provider.settings.modelId), isTrue);
    });

    test(
      'generation callbacks persist completion and surface errors',
      () async {
        final sentinel = _SafeSentinel();
        final generation = GenerationProvider(
          controller: ChatStateController(sentinel: sentinel),
          warmup: ModelWarmupService(sentinel: sentinel),
        );
        final provider = ChatProvider()
          ..setGenerationProvider(generation)
          ..setGenerationProvider(generation);
        addTearDown(provider.dispose);
        generation.onGenerationComplete?.call('ignored without a chat');
        await Future<void>.delayed(Duration.zero);
        final chat = await provider.createChat(title: 'Callbacks');

        generation.onGenerationComplete?.call('completed locally');
        await provider.drainPendingPersistence();
        expect(provider.messages.single.content, 'completed locally');
        expect(provider.messages.single.chatId, chat!.id);

        generation.onError?.call('runtime failed');
        expect(provider.hasError, isTrue);
        expect(provider.errorMessage, 'runtime failed');
      },
    );
  });

  group('NoteProvider', () {
    test('initial state is empty', () {
      final provider = NoteProvider();
      expect(provider.notes, isEmpty);
      expect(provider.isLoading, false);
    });

    test('createNote adds a note', () async {
      final provider = NoteProvider();
      final note = await provider.createNote('Title', 'Content');
      expect(note, isNotNull);
      expect(note!.title, 'Title');
      expect(note.content, 'Content');
    });
  });

  group('PersonaProvider', () {
    test('initial state is empty', () {
      final provider = PersonaProvider();
      expect(provider.personas, isEmpty);
      expect(provider.isLoading, false);
    });

    test('createPersona adds a persona', () async {
      final provider = PersonaProvider();
      final persona = await provider.createPersona('Test', 'You are a test.');
      expect(persona, isNotNull);
      expect(persona!.name, 'Test');
    });
  });
}

class _DelayedCompletionDatabase implements DatabaseHelper {
  final entered = Completer<void>();
  final release = Completer<void>();
  final updated = Completer<void>();
  int _nextChat = 0;
  int? savedChatId;
  @override
  Future<int> insertChatWithModel(
    Map<String, dynamic> values,
    String modelId, {
    void Function()? beforeCommit,
  }) async {
    beforeCommit?.call();
    return ++_nextChat;
  }

  @override
  Future<int> insertMessage(Map<String, dynamic> values) async {
    entered.complete();
    await release.future;
    savedChatId = values['chat_id'] as int;
    return 1;
  }

  @override
  Future<int> updateChat(int id, Map<String, dynamic> values) async {
    updated.complete();
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _SafeSentinel implements HardwareSentinelService {
  @override
  int get currentLevel => 100;
  @override
  bool get isCharging => true;
  @override
  bool get isInSaveMode => false;
  @override
  bool get isDisposed => false;
  @override
  ConnectivityResult get connectivityType => ConnectivityResult.wifi;
  @override
  int get memoryPressureLevel => 0;
  @override
  Stream<bool> get onHealthChanged =>
      Stream<bool>.multi((_) {}, isBroadcast: true);
  @override
  bool isSafeForHeavyOperation() => true;
  @override
  bool isSafeForDownload() => true;
  @override
  String? unsafeReasonHeavy() => null;
  @override
  String? unsafeReasonDownload() => null;
  @override
  void checkHeavyOperation() {}
  @override
  void checkDownload() {}
  @override
  Future<void> init() async {}
  @override
  void dispose() {}
}
