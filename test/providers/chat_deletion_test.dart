import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/chat.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/models/note.dart';
import 'package:vitalis_app/providers/chat_provider.dart';
import 'package:vitalis_app/providers/generation_provider.dart';

void main() {
  test(
    'zero deleted rows preserves the selected chat and reports failure',
    () async {
      final database = _FailingDatabase()
        ..gate = (Completer<int>()..complete(0));
      final provider = ChatProvider(database: database);
      addTearDown(provider.dispose);
      await provider.selectChat(17);
      await expectLater(provider.deleteChat(17), throwsA(isA<StateError>()));
      expect(provider.currentChat?.id, 17);
      expect(database.refreshAttempts, 0);
    },
  );

  test('failed refresh reports that deletion already committed', () async {
    final database = _FailingDatabase()
      ..gate = (Completer<int>()..complete(1))
      ..refreshFailure = StateError('/private-secret/history');
    final provider = ChatProvider(database: database);
    addTearDown(provider.dispose);
    await provider.selectChat(17);
    await expectLater(
      provider.deleteChat(17),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'committed deletion',
          contains('deleted'),
        ),
      ),
    );
    expect(database.attempts, 1);
    expect(provider.currentChat, isNull);
    expect(provider.errorMessage, isNot(contains('private-secret')));
  });

  test('acknowledged deletion selects the remaining saved chat', () async {
    final database = _FailingDatabase()..gate = (Completer<int>()..complete(1));
    final provider = ChatProvider(database: database);
    addTearDown(provider.dispose);
    await provider.selectChat(17);
    final generation = _WaitingGeneration(sending: true);
    provider.setGenerationProvider(generation);
    final deleting = provider.deleteChat(17);
    await generation.entered.future;
    expect(database.attempts, 0);
    generation.stopped.complete();
    await deleting;
    expect(database.attempts, 1);
    expect(database.refreshAttempts, 1);
    expect(provider.currentChat?.id, 18);
    expect(provider.deletionFailures, 0);
  });

  test('preparation must acknowledge Stop before deletion storage', () async {
    final database = _FailingDatabase();
    final provider = ChatProvider(database: database);
    addTearDown(provider.dispose);
    await provider.selectChat(17);
    final generation = _WaitingGeneration(sending: false);
    provider.setGenerationProvider(generation);
    final deleting = provider.deleteChat(17);
    final failure = expectLater(deleting, throwsA(isA<StateError>()));
    await Future<void>.delayed(Duration.zero);
    final attemptsBeforeStop = database.attempts;
    final stopCalls = generation.stopCalls;
    generation.stopped.completeError(StateError('Cancellation unconfirmed'));
    // Observe the stand-alone fixture signal if the buggy provider never stops.
    if (stopCalls == 0) {
      await generation.stopped.future.catchError((Object _) {});
    }
    await failure;
    expect(attemptsBeforeStop, 0);
    expect(stopCalls, 1);
    expect(database.attempts, 0);
  });

  test('disposal during Stop prevents new deletion storage', () async {
    final database = _FailingDatabase();
    final provider = ChatProvider(database: database);
    await provider.selectChat(17);
    final generation = _WaitingGeneration(sending: true);
    provider.setGenerationProvider(generation);
    final deleting = provider.deleteChat(17);
    final failure = expectLater(deleting, throwsA(isA<StateError>()));
    await generation.entered.future;
    final closing = provider.close();
    generation.stopped.complete();
    await Future.wait([failure, closing]);
    expect(database.attempts, 0);
  });

  test(
    'duplicate deletion shares the admitted writer through shutdown',
    () async {
      final database = _FailingDatabase()..gate = Completer<int>();
      final provider = ChatProvider(database: database);
      final first = provider.deleteChat(17);
      await database.entered.future;
      final second = provider.deleteChat(17);
      final closing = provider.close();
      database.gate!.complete(1);
      await Future.wait([first, second, closing]);
      expect(database.attempts, 1);
      expect(database.refreshAttempts, 0);
    },
  );

  test('late deletion failure remains observable after disposal', () async {
    final database = _FailingDatabase()..gate = Completer<int>();
    final provider = ChatProvider(database: database);
    final deleting = provider.deleteChat(17);
    final failure = expectLater(deleting, throwsA(isA<StateError>()));
    await database.entered.future;
    final closing = provider.close();
    database.gate!.completeError(StateError('/private-secret/database'));
    await Future.wait([failure, closing]);
    expect(provider.deletionFailures, 1);
    expect(database.refreshAttempts, 0);
  });

  test('storage failure preserves the selected chat', () async {
    final database = _FailingDatabase();
    final provider = ChatProvider(database: database);
    addTearDown(provider.dispose);
    await provider.selectChat(17);
    final selected = provider.currentChat;
    await expectLater(provider.deleteChat(17), throwsA(isA<StateError>()));
    expect(provider.currentChat, same(selected));
    expect(provider.currentChat?.id, 17);
  });

  test('disposed provider rejects deletion before storage', () async {
    final database = _FailingDatabase();
    final provider = ChatProvider(database: database)..dispose();
    await expectLater(provider.deleteChat(17), throwsA(isA<StateError>()));
    expect(database.attempts, 0);
  });

  test(
    'close drains an admitted deletion without post-disposal refresh',
    () async {
      final database = _FailingDatabase()..gate = Completer<int>();
      final provider = ChatProvider(database: database);
      final deleting = provider.deleteChat(17);
      // Observe failures immediately so the reproduction cannot leak an error.
      final observed = deleting.then<Object?>(
        (_) => null,
        onError: (Object e) => e,
      );
      await database.entered.future;
      var closed = false;
      final closing = provider.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      final closedBeforeWriter = closed;
      database.gate!.complete(1);
      final outcome = await observed;
      await closing;
      expect(closedBeforeWriter, isFalse);
      expect(outcome, isNull);
      expect(database.refreshAttempts, 0);
    },
  );

  test('storage deletion failure propagates a redacted error', () async {
    final database = _FailingDatabase();
    final provider = ChatProvider(database: database);
    addTearDown(provider.dispose);
    await expectLater(
      provider.deleteChat(17),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'redacted message',
          isNot(contains('private-secret')),
        ),
      ),
    );
    expect(database.attempts, 1);
    expect(provider.hasError, isTrue);
    expect(provider.errorMessage, isNot(contains('private-secret')));
  });
}

final class _WaitingGeneration implements GenerationProvider {
  _WaitingGeneration({required this.sending});
  final bool sending;
  final stopped = Completer<void>();
  final entered = Completer<void>();

  int stopCalls = 0;

  @override
  bool get isSending => sending;

  @override
  Future<void> stopSending() async {
    stopCalls++;
    if (!entered.isCompleted) entered.complete();
    await stopped.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final class _FailingDatabase implements DatabaseHelper {
  int attempts = 0;
  int refreshAttempts = 0;
  Completer<int>? gate;
  Object? refreshFailure;
  final entered = Completer<void>();

  @override
  Future<List<Chat>> getChats() async {
    refreshAttempts++;
    if (refreshFailure case final Object error) throw error;
    return [
      Chat(
        id: 18,
        title: 'Remaining disposable chat',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    ];
  }

  @override
  Future<Chat?> getChat(int id) async => Chat(
    id: id,
    title: 'Disposable chat',
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
  Future<Map<String, dynamic>?> getModelSettings(int chatId) async => null;

  @override
  Future<int?> getChatPersona(int chatId) async => null;

  @override
  Future<int> deleteChat(int id) async {
    attempts++;
    if (!entered.isCompleted) entered.complete();
    if (gate != null) return gate!.future;
    throw StateError('/private-secret/database');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    refreshAttempts++;
    throw StateError('Unexpected storage call');
  }
}
