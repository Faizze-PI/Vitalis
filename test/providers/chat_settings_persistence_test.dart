import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/chat.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/note.dart';
import 'package:vitalis_app/providers/chat_provider.dart';
import 'package:vitalis_app/constants/app_constants.dart';

void main() {
  test(
    'overlapping admitted settings writes persist in submission order',
    () async {
      final database = _Database()..gate = Completer<void>();
      final provider = ChatProvider(database: database);
      addTearDown(provider.dispose);
      await provider.selectChat(1);
      final first = provider.updateSettings(
        provider.settings.copyWith(systemPrompt: 'First draft'),
      );
      await database.entered.future;
      final second = provider.updateSettings(
        provider.settings.copyWith(systemPrompt: 'Second draft'),
      );
      await Future<void>.delayed(Duration.zero);
      final attemptsBeforeAcknowledgement = database.writeAttempts;
      database.gate!.complete();
      await Future.wait([first, second]);
      expect(attemptsBeforeAcknowledgement, 1);
      expect(database.savedPrompts, ['First draft', 'Second draft']);
      expect(provider.settings.systemPrompt, 'Second draft');
    },
  );

  test(
    'oversized system prompt is rejected before storage or publication',
    () async {
      final database = _Database();
      final provider = ChatProvider(database: database);
      addTearDown(provider.dispose);
      await provider.selectChat(1);
      await expectLater(
        provider.updateSettings(
          provider.settings.copyWith(
            systemPrompt: 'z' * (AppConstants.maxStoredTextBytes + 1),
          ),
        ),
        throwsArgumentError,
      );
      expect(database.writeAttempts, 0);
      expect(provider.settings.systemPrompt, 'Saved prompt 1');
    },
  );
  test(
    'failed settings write is reported and preserves committed settings',
    () async {
      final database = _Database()
        ..failure = StateError('/private/database token=secret');
      final provider = ChatProvider(database: database);
      addTearDown(provider.dispose);
      await provider.selectChat(1);
      await expectLater(
        provider.updateSettings(
          provider.settings.copyWith(systemPrompt: 'New draft'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(provider.settings.systemPrompt, 'Saved prompt 1');
      expect(provider.hasError, isTrue);
      expect(provider.errorMessage, isNot(contains('/private')));
      expect(provider.settingsPersistenceFailures, 1);
    },
  );

  test(
    'settings publish only after persistence acknowledges success',
    () async {
      final database = _Database()..gate = Completer<void>();
      final provider = ChatProvider(database: database);
      addTearDown(provider.dispose);
      await provider.selectChat(1);
      final updating = provider.updateSettings(
        provider.settings.copyWith(systemPrompt: 'New draft'),
      );
      await database.entered.future;
      final before = provider.settings.systemPrompt;
      database.gate!.complete();
      await updating;
      expect(before, 'Saved prompt 1');
      expect(provider.settings.systemPrompt, 'New draft');
    },
  );

  test('provider close drains an admitted settings write', () async {
    final database = _Database()..gate = Completer<void>();
    final provider = ChatProvider(database: database);
    await provider.selectChat(1);
    final updating = provider.updateSettings(
      provider.settings.copyWith(temperature: 0.5),
    );
    await database.entered.future;
    var closed = false;
    final closing = provider.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    final closedBeforeWrite = closed;
    database.gate!.complete();
    await updating;
    await closing;
    expect(closedBeforeWrite, isFalse);
    expect(database.savedChats, [1]);
  });

  test(
    'a completed old-chat settings write cannot replace a new selection',
    () async {
      final database = _Database()..gate = Completer<void>();
      final provider = ChatProvider(database: database);
      addTearDown(provider.dispose);
      await provider.selectChat(1);
      final updating = provider.updateSettings(
        provider.settings.copyWith(systemPrompt: 'Old chat draft'),
      );
      await database.entered.future;
      await provider.selectChat(2);
      database.gate!.complete();
      await updating;
      expect(database.savedChats, [1]);
      expect(provider.currentChat?.id, 2);
      expect(provider.settings.systemPrompt, 'Saved prompt 2');
    },
  );

  test('failed preview persistence restores the committed settings', () async {
    final database = _Database()
      ..failure = StateError('Fixture storage failure');
    final provider = ChatProvider(database: database);
    addTearDown(provider.dispose);
    await provider.selectChat(1);
    final preview = provider.settings.copyWith(temperature: 0.2);
    provider.updateSettingsLocally(preview);
    await expectLater(
      provider.updateSettings(preview),
      throwsA(isA<StateError>()),
    );
    expect(provider.settings.temperature, 0.7);
  });

  test(
    'zero updated rows cannot be reported as a successful settings save',
    () async {
      final database = _Database()..rowsUpdated = 0;
      final provider = ChatProvider(database: database);
      addTearDown(provider.dispose);
      await provider.selectChat(1);
      await expectLater(
        provider.updateSettings(
          provider.settings.copyWith(systemPrompt: 'Unsaved'),
        ),
        throwsA(isA<StateError>()),
      );
      expect(provider.settings.systemPrompt, 'Saved prompt 1');
    },
  );
}

final class _Database implements DatabaseHelper {
  Object? failure;
  int rowsUpdated = 1;
  Completer<void>? gate;
  final entered = Completer<void>();
  final savedChats = <int>[];
  final savedPrompts = <String>[];
  int writeAttempts = 0;

  @override
  Future<Chat?> getChat(int id) async => Chat(
    id: id,
    title: 'Disposable chat $id',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  @override
  Future<List<Message>> getMessagesForChatPaginated(
    int chatId, {
    int limit = 50,
    int? beforeId,
  }) async => [];
  @override
  Future<List<Note>> getAttachedNotes(int chatId) async => [];
  @override
  Future<int?> getChatPersona(int chatId) async => null;
  @override
  Future<Map<String, dynamic>?> getModelSettings(int chatId) async =>
      ModelSettings(
        temperature: 0.7,
        systemPrompt: 'Saved prompt $chatId',
      ).toJson();
  @override
  Future<int> updateModelSettings(
    int chatId,
    Map<String, dynamic> settings,
  ) async {
    writeAttempts++;
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    if (failure case final Object error) throw error;
    savedChats.add(chatId);
    savedPrompts.add(settings['system_prompt'] as String);
    return rowsUpdated;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected storage call');
}
