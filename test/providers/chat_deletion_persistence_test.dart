import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/chat.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/note.dart';
import 'package:vitalis_app/providers/chat_provider.dart';
import 'package:vitalis_app/providers/generation_provider.dart';

void main() {
  test('out-of-order saves retain each response render identity', () async {
    final database = _ReorderedDatabase();
    final provider = ChatProvider(database: database);
    addTearDown(provider.dispose);
    addTearDown(() async {
      for (final gate in database.gates) {
        if (!gate.isCompleted) gate.complete();
      }
      await provider.drainPendingPersistence();
    });
    await provider.selectChat(17);
    final generation = _Generation();
    provider.setGenerationProvider(generation);
    final first = Object();
    final second = Object();
    generation.responseFrameIdentity = first;
    generation.onGenerationComplete!('First disposable response');
    await database.entered[0].future;
    generation.responseFrameIdentity = second;
    generation.onGenerationComplete!('Second disposable response');
    await database.entered[1].future;
    final published = Completer<void>();
    provider.addListener(() {
      if (provider.messages.any((message) => message.id == 2) &&
          !published.isCompleted) {
        published.complete();
      }
    });
    database.gates[1].complete();
    await published.future;
    database.gates[0].complete();
    await provider.drainPendingPersistence();
    expect(
      provider.responseFrameIdentityFor(
        provider.messages.firstWhere((m) => m.id == 1),
      ),
      same(first),
    );
    expect(
      provider.responseFrameIdentityFor(
        provider.messages.firstWhere((m) => m.id == 2),
      ),
      same(second),
    );
  });
  test(
    'saved response keeps its original render identity across delayed persistence',
    () async {
      final database = _Database();
      final provider = ChatProvider(database: database);
      addTearDown(provider.dispose);
      await provider.selectChat(17);
      final original = Object();
      final generation = _Generation()..responseFrameIdentity = original;
      provider.setGenerationProvider(generation);
      generation.onGenerationComplete!('Disposable response');
      await database.messageEntered.future;
      generation.responseFrameIdentity = Object();
      database.messageRelease.complete();
      await provider.drainPendingPersistence();
      final saved = provider.messages.single;
      expect(provider.responseFrameIdentityFor(saved), same(original));
      expect(
        provider.responseFrameIdentityFor(saved.copyWith(id: 999)),
        isNull,
      );
      expect(
        provider.responseFrameIdentityFor(saved.copyWith(chatId: 18)),
        isNull,
      );
      await provider.selectChat(18);
      expect(provider.responseFrameIdentityFor(saved), isNull);
      expect(generation.abandonedFrameObservations, 1);
    },
  );
  test('a pending deletion rejects newly submitted settings writes', () async {
    final database = _Database()..deleteRelease = Completer<void>();
    final provider = ChatProvider(database: database);
    addTearDown(provider.dispose);
    await provider.selectChat(17);
    final deleting = provider.deleteChat(17);
    await database.deleteEntered.future;
    final writing = provider.updateSettings(provider.settings);
    final observed = writing.then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );
    database.writeRelease.complete();
    database.deleteRelease!.complete();
    final outcome = await observed;
    await deleting;
    expect(outcome, isA<StateError>());
    expect(database.writeEntered.isCompleted, isFalse);
  });

  test(
    'an admitted response finishes saving before its chat is deleted',
    () async {
      final database = _Database();
      final provider = ChatProvider(database: database);
      addTearDown(provider.dispose);
      await provider.selectChat(17);
      final generation = _Generation();
      provider.setGenerationProvider(generation);
      generation.onGenerationComplete!('Disposable response');
      await database.messageEntered.future;
      final deleting = provider.deleteChat(17);
      await Future<void>.delayed(Duration.zero);
      final deletedBeforeResponse = database.events.contains('delete');
      database.messageRelease.complete();
      await deleting;
      expect(deletedBeforeResponse, isFalse);
      expect(database.events, ['message', 'updated', 'delete']);
      expect(provider.currentChat?.id, 18);
      expect(provider.messages, isEmpty);
    },
  );

  test('deletion waits for already admitted settings persistence', () async {
    final database = _Database();
    final provider = ChatProvider(database: database);
    addTearDown(provider.dispose);
    await provider.selectChat(17);
    final saving = provider.updateSettings(
      provider.settings.copyWith(systemPrompt: 'Disposable draft'),
    );
    await database.writeEntered.future;
    final deleting = provider.deleteChat(17);
    await Future<void>.delayed(Duration.zero);
    final deletedBeforeSave = database.events.contains('delete');
    database.writeRelease.complete();
    await Future.wait([saving, deleting]);
    expect(deletedBeforeSave, isFalse);
    expect(database.events, ['settings', 'delete']);
  });
}

final class _ReorderedDatabase extends _Database {
  final entered = [Completer<void>(), Completer<void>()];
  final gates = [Completer<void>(), Completer<void>()];
  int calls = 0;
  @override
  Future<int> insertMessage(Map<String, dynamic> message) async {
    final index = calls++;
    entered[index].complete();
    await gates[index].future;
    return index + 1;
  }
}

final class _Database implements DatabaseHelper {
  final writeEntered = Completer<void>();
  final writeRelease = Completer<void>();
  final events = <String>[];
  final messageEntered = Completer<void>();
  final messageRelease = Completer<void>();
  final deleteEntered = Completer<void>();
  Completer<void>? deleteRelease;

  @override
  Future<int> insertMessage(Map<String, dynamic> message) async {
    messageEntered.complete();
    await messageRelease.future;
    events.add('message');
    return 1;
  }

  @override
  Future<int> updateChat(int id, Map<String, dynamic> chat) async {
    events.add('updated');
    return 1;
  }

  @override
  Future<Chat?> getChat(int id) async => Chat(
    id: id,
    title: 'Disposable chat',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );

  @override
  Future<List<Chat>> getChats() async => [(await getChat(18))!];

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
      ModelSettings().toJson();

  @override
  Future<int> updateModelSettings(int id, Map<String, dynamic> settings) async {
    writeEntered.complete();
    await writeRelease.future;
    events.add('settings');
    return 1;
  }

  @override
  Future<int> deleteChat(int id) async {
    deleteEntered.complete();
    await deleteRelease?.future;
    events.add('delete');
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected storage call');
}

final class _Generation implements GenerationProvider {
  int abandonedFrameObservations = 0;
  @override
  void abandonResponseFrameObservation() => abandonedFrameObservations++;
  @override
  Object? responseFrameIdentity;
  @override
  void Function(String)? onGenerationComplete;
  @override
  void Function(String)? onError;
  @override
  bool get isSending => false;
  @override
  Future<void> stopSending() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
