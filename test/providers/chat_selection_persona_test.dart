import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'package:vitalis_app/models/model_descriptor.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/chat.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/models/note.dart';
import 'package:vitalis_app/models/persona.dart';
import 'package:vitalis_app/providers/chat_provider.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/services/startup_access_guard.dart';
import 'package:vitalis_app/services/selected_model_readiness.dart';
import 'package:vitalis_app/providers/generation_provider.dart';

void main() {
  for (final deleting in [false, true]) {
    test(
      'committed persona change supersedes a stale selection read delete=$deleting',
      () async {
        final database = _RacingPersonaDatabase();
        final provider = ChatProvider(database: database);
        addTearDown(provider.close);
        final selecting = provider.selectChat(1);
        await database.entered.future;
        database.value = deleting
            ? null
            : Persona(id: 7, name: 'Updated', systemPrompt: 'New');
        provider.applyPersonaChange(7, database.value);
        database.release.complete();
        await selecting;
        expect(database.reads, 2);
        expect(
          provider.currentPersona?.systemPrompt,
          deleting ? isNull : 'New',
        );
      },
    );
  }

  test('disposed chat rejects late committed persona publication', () async {
    final provider = ChatProvider(database: _SelectionDatabase());
    await provider.selectChat(1);
    final original = provider.currentPersona;
    var notifications = 0;
    provider.addListener(() => notifications++);
    await provider.close();
    provider.applyPersonaChange(7, null);
    expect(provider.currentPersona, same(original));
    expect(notifications, 0);
  });
  test('reopening a chat waits for its pending persona commit', () async {
    final database = _PersonaWriteDatabase()..writeGate = Completer<void>();
    final provider = ChatProvider(database: database);
    addTearDown(provider.close);
    await provider.selectChat(1);
    final writing = provider.setPersona(
      Persona(id: 9, name: 'Replacement', systemPrompt: 'Test'),
    );
    await database.writeEntered.future;
    await provider.selectChat(2);
    var reopened = false;
    final reopening = provider.selectChat(1).then((_) => reopened = true);
    await Future<void>.delayed(Duration.zero);
    final openedBeforeCommit = reopened;
    database.writeGate!.complete();
    expect(await writing, isTrue);
    await reopening;
    expect(openedBeforeCommit, isFalse);
    expect(provider.currentPersona?.id, 9);
  });

  test('chat deletion waits for its admitted persona save', () async {
    final database = _PersonaWriteDatabase()..writeGate = Completer<void>();
    final provider = ChatProvider(database: database);
    addTearDown(provider.close);
    await provider.selectChat(1);
    final writing = provider.setPersona(
      Persona(id: 9, name: 'Replacement', systemPrompt: 'Test'),
    );
    await database.writeEntered.future;
    await provider.selectChat(2);
    final deleting = provider.deleteChat(1);
    await Future<void>.delayed(Duration.zero);
    final deletedBeforeCommit = database.deleted;
    database.writeGate!.complete();
    expect(await writing, isTrue);
    await deleting;
    expect(deletedBeforeCommit, isFalse);
    expect(database.personaAtDeletion, 9);
    expect(provider.currentChat?.id, 2);
  });

  test('failed persona save permits an explicit successful retry', () async {
    final database = _PersonaWriteDatabase()..failReplacement = true;
    final provider = ChatProvider(database: database);
    addTearDown(provider.close);
    await provider.selectChat(1);
    final replacement = Persona(id: 9, name: 'Retry', systemPrompt: 'Test');
    expect(await provider.setPersona(replacement), isFalse);
    expect(provider.hasError, isTrue);
    database.failReplacement = false;
    expect(await provider.setPersona(replacement), isTrue);
    expect(provider.hasError, isFalse);
    expect(provider.currentPersona?.id, 9);
    expect(database.personaId, 9);
  });
  test('persona writes commit in admitted order', () async {
    final database = _PersonaWriteDatabase()..writeGate = Completer<void>();
    final provider = ChatProvider(database: database);
    addTearDown(provider.close);
    await provider.selectChat(1);
    final first = provider.setPersona(
      Persona(id: 9, name: 'First', systemPrompt: 'Test'),
    );
    await database.writeEntered.future;
    final second = provider.setPersona(
      Persona(id: 10, name: 'Second', systemPrompt: 'Test'),
    );
    await Future<void>.delayed(Duration.zero);
    final admittedBeforeAcknowledgement = List<int>.of(database.writes);
    database.writeGate!.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(admittedBeforeAcknowledgement, [9]);
    expect(database.writes, [9, 10]);
    expect(database.personaId, 10);
    expect(provider.currentPersona?.id, 10);
  });

  test('old-chat persona completion cannot change the new view', () async {
    final database = _PersonaWriteDatabase()..writeGate = Completer<void>();
    final provider = ChatProvider(database: database);
    addTearDown(provider.close);
    await provider.selectChat(1);
    final writing = provider.setPersona(
      Persona(id: 9, name: 'Replacement', systemPrompt: 'Test'),
    );
    await database.writeEntered.future;
    await provider.selectChat(2);
    database.writeGate!.complete();
    expect(await writing, isTrue);
    expect(database.personaId, 9);
    expect(provider.currentChat?.id, 2);
    expect(provider.currentPersona, isNull);
  });

  test('provider close drains persona save without late publication', () async {
    final database = _PersonaWriteDatabase()..writeGate = Completer<void>();
    final provider = ChatProvider(database: database);
    await provider.selectChat(1);
    var notifications = 0;
    provider.addListener(() => notifications++);
    final writing = provider.setPersona(
      Persona(id: 9, name: 'Replacement', systemPrompt: 'Test'),
    );
    await database.writeEntered.future;
    var closed = false;
    final closing = provider.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    final closedBeforeAcknowledgement = closed;
    database.writeGate!.complete();
    expect(await writing, isTrue);
    await closing;
    expect(closedBeforeAcknowledgement, isFalse);
    expect(database.personaId, 9);
    expect(notifications, 0);
    await expectLater(provider.removePersona(), throwsStateError);
  });

  test('failed persona replacement preserves committed selection', () async {
    final database = _PersonaWriteDatabase()..failReplacement = true;
    final provider = ChatProvider(database: database);
    addTearDown(provider.close);
    await provider.selectChat(1);
    await provider.setPersona(
      Persona(id: 9, name: 'Replacement', systemPrompt: 'Test'),
    );
    expect(
      database.personaId,
      7,
      reason: 'Failed replacement must retain mapping',
    );
    expect(provider.currentPersona?.id, 7);
    expect(provider.hasError, isTrue);
  });

  test('failed persona removal retains committed visible selection', () async {
    final database = _PersonaWriteDatabase()..failRemoval = true;
    final provider = ChatProvider(database: database);
    addTearDown(provider.close);
    await provider.selectChat(1);
    await provider.removePersona();
    expect(database.personaId, 7);
    expect(provider.currentPersona?.id, 7);
    expect(provider.hasError, isTrue);
  });

  test(
    'pending persona write does not publish uncommitted selection',
    () async {
      final database = _PersonaWriteDatabase()..writeGate = Completer<void>();
      final provider = ChatProvider(database: database);
      addTearDown(provider.close);
      await provider.selectChat(1);
      final writing = provider.setPersona(
        Persona(id: 9, name: 'Replacement', systemPrompt: 'Test'),
      );
      await database.writeEntered.future;
      final visibleBeforeCommit = provider.currentPersona?.id;
      final savedBeforeCommit = database.personaId;
      database.writeGate!.complete();
      await writing;
      expect(visibleBeforeCommit, 7);
      expect(savedBeforeCommit, 7);
      expect(provider.currentPersona?.id, 9);
      expect(database.personaId, 9);
    },
  );
  test(
    'new chat save returns its own identity without replacing a newer selection',
    () async {
      final database = _DelayedCreateDatabase();
      final provider = ChatProvider(database: database);
      addTearDown(provider.dispose);
      await provider.selectChat(1);
      final creating = provider.createChat(title: 'Disposable created');
      await database.entered.future;
      await provider.selectChat(2);
      database.finish.complete();
      final created = await creating;
      expect(created?.id, 4);
      expect(created?.title, 'Disposable created');
      expect(provider.currentChat?.id, 2);
      expect(database.createdChats, 1);
    },
  );
  test('failed Stop prevents new chat insertion', () async {
    final database = _SelectionDatabase();
    final provider = ChatProvider(database: database);
    final generation = _WaitingGeneration();
    addTearDown(provider.dispose);
    await provider.selectChat(1);
    provider.setGenerationProvider(generation);
    final creating = provider.createChat();
    generation.stopped.completeError(StateError('fixture Stop failure'));
    expect(await creating, isNull);
    expect(database.createdChats, 0);
    expect(provider.currentChat?.id, 1);
    expect(provider.hasError, isTrue);
  });
  test(
    'new chat waits for Stop and starts without the previous persona',
    () async {
      final database = _SelectionDatabase();
      final provider = ChatProvider(database: database);
      final generation = _WaitingGeneration();
      addTearDown(provider.dispose);
      await provider.selectChat(1);
      provider.setGenerationProvider(generation);
      final creating = provider.createChat(title: 'Disposable new');
      await Future<void>.delayed(Duration.zero);
      final calls = generation.stopCalls;
      final writes = database.createdChats;
      generation.stopped.complete();
      await creating;
      expect(calls, 1);
      expect(writes, 0);
      expect(provider.currentPersona, isNull);
    },
  );
  for (final failure in [true, false]) {
    test(
      'pending Stop ${failure ? 'failure' : 'disposal'} preserves selected chat',
      () async {
        final provider = ChatProvider(database: _SelectionDatabase());
        final generation = _WaitingGeneration();
        addTearDown(provider.dispose);
        await provider.selectChat(1);
        provider.setGenerationProvider(generation);
        final selecting = provider.selectChat(2);
        await Future<void>.delayed(Duration.zero);
        expect(generation.stopCalls, 1);
        if (failure) {
          generation.stopped.completeError(
            StateError('fixture unacknowledged Stop'),
          );
        } else {
          provider.dispose();
          generation.stopped.complete();
        }
        await selecting;
        expect(provider.currentChat?.id, 1);
        if (failure) {
          expect(provider.hasError, isTrue);
          expect(provider.isLoading, isFalse);
        }
      },
    );
  }
  test(
    'chat selection waits for owned generation Stop acknowledgement',
    () async {
      final provider = ChatProvider(database: _SelectionDatabase());
      final generation = _WaitingGeneration();
      addTearDown(provider.dispose);
      await provider.selectChat(1);
      provider.setGenerationProvider(generation);
      final selecting = provider.selectChat(2);
      await Future<void>.delayed(Duration.zero);
      final observedCalls = generation.stopCalls;
      final observedChat = provider.currentChat?.id;
      generation.stopped.complete();
      await selecting;
      expect(observedCalls, 1);
      expect(observedChat, 1);
      expect(provider.currentChat?.id, 2);
    },
  );
  test('late chat read cannot replace a newer selected chat', () async {
    final database = _DelayedChatDatabase();
    final provider = ChatProvider(database: database);
    addTearDown(provider.dispose);
    final first = provider.selectChat(1);
    await database.entered.future;
    await provider.selectChat(2);
    database.release.complete();
    await first;
    expect(provider.currentChat?.id, 2);
    expect(provider.currentPersona, isNull);
  });
  test(
    'chat selection assesses its explicit model without native loading',
    () async {
      final ids = <String>[];
      final readiness = SelectedModelReadiness((id) async {
        ids.add(id);
        return StartupModelReadiness.missing;
      });
      final provider = ChatProvider(
        database: _SelectionDatabase(),
        modelReadiness: readiness,
      );
      addTearDown(provider.dispose);
      addTearDown(readiness.dispose);
      await provider.selectChat(1);
      await Future<void>.delayed(Duration.zero);
      expect(ids, [provider.settings.modelId]);
      expect(readiness.readiness, StartupModelReadiness.missing);
      await provider.selectChat(2);
      await Future<void>.delayed(Duration.zero);
      expect(ids, hasLength(2));
      expect(readiness.modelId, provider.settings.modelId);
    },
  );
  test(
    'saved chat opens while its large model assessment is pending',
    () async {
      final pending = Completer<StartupModelReadiness>();
      final readiness = SelectedModelReadiness((_) => pending.future);
      final provider = ChatProvider(
        database: _SelectionDatabase(),
        modelReadiness: readiness,
      );
      addTearDown(provider.dispose);
      addTearDown(readiness.dispose);

      await provider.selectChat(1);
      expect(provider.currentChat?.id, 1);
      expect(provider.isLoading, isFalse);
      expect(readiness.readiness, StartupModelReadiness.checking);
      pending.complete(StartupModelReadiness.missing);
      await Future<void>.delayed(Duration.zero);
      expect(readiness.readiness, StartupModelReadiness.missing);
    },
  );
  test(
    'competing model switch is rejected without disturbing its owner',
    () async {
      final registry = _DelayedRegistry();
      final database = _SelectionDatabase();
      final provider = ChatProvider(
        database: database,
        modelRegistry: registry,
      );
      addTearDown(provider.dispose);
      await provider.selectChat(1);
      final first = provider.switchModel('Disposable');
      final second = provider.switchModel('Disposable');
      final rejected = expectLater(second, throwsStateError);
      registry.validated.complete(
        const ModelDescriptor(
          id: 'Disposable',
          displayName: 'Fixture',
          source: 'local',
          compatibilityStatus: 'compatible',
        ),
      );
      await first;
      await rejected;
      expect(database.assignments, [(1, 'Disposable')]);
    },
  );
  for (final outcome in ['changed-selection', 'disposed', 'write-failure']) {
    test('model assignment $outcome never publishes stale settings', () async {
      final registry = _DelayedRegistry();
      final database = _DelayedAssignmentDatabase();
      final provider = ChatProvider(
        database: database,
        modelRegistry: registry,
      );
      addTearDown(provider.dispose);
      await provider.selectChat(1);
      registry.validated.complete(
        const ModelDescriptor(
          id: 'Disposable',
          displayName: 'Fixture',
          source: 'local',
          compatibilityStatus: 'compatible',
        ),
      );
      final switching = provider.switchModel('Disposable');
      final rejected = expectLater(switching, throwsStateError);
      await database.entered.future;
      if (outcome == 'changed-selection') await provider.selectChat(2);
      final previous = provider.settings.toJson();
      if (outcome == 'disposed') provider.dispose();
      if (outcome == 'write-failure') {
        database.finish.completeError(StateError('fixture write failure'));
      } else {
        database.finish.complete();
      }
      await rejected;
      expect(provider.settings.toJson(), previous);
      expect(
        database.assignments,
        outcome == 'write-failure' ? isEmpty : [(1, 'Disposable')],
      );
    });
  }
  test('read-only recovery assigns only the explicit verified model', () async {
    final registry = _DelayedRegistry();
    final database = _SelectionDatabase();
    final provider = ChatProvider(
      database: database,
      modelRegistry: registry,
      startupAccess: StartupAccessGuard(
        () => const StartupCapabilities(
          databaseReady: true,
          migrationReady: true,
          safetyReady: true,
          modelReadiness: StartupModelReadiness.missing,
        ),
      ),
    );
    addTearDown(provider.dispose);
    await provider.selectChat(1);
    final before = provider.settings.toJson();
    registry.validated.complete(
      const ModelDescriptor(
        id: 'Disposable',
        displayName: 'Fixture',
        source: 'local',
        compatibilityStatus: 'compatible',
      ),
    );
    await provider.switchModel('Disposable');
    expect(database.assignments, [(1, 'Disposable')]);
    expect(provider.settings.toJson(), {...before, 'model_id': 'Disposable'});
  });
  test(
    'model selection cannot target a chat selected during validation',
    () async {
      final registry = _DelayedRegistry();
      final provider = ChatProvider(
        database: _SelectionDatabase(),
        modelRegistry: registry,
      );
      addTearDown(provider.dispose);
      await provider.selectChat(1);
      final switching = provider.switchModel('Disposable');
      final rejected = expectLater(switching, throwsStateError);
      await provider.selectChat(2);
      final originalModel = provider.settings.modelId;
      registry.validated.complete(
        const ModelDescriptor(
          id: 'Disposable',
          displayName: 'Fixture',
          source: 'local',
          compatibilityStatus: 'compatible',
        ),
      );
      await rejected;
      expect(provider.currentChat?.id, 2);
      expect(provider.settings.modelId, originalModel);
    },
  );
  test(
    'browsing another chat clears an unassigned or missing persona',
    () async {
      final database = _SelectionDatabase();
      final provider = ChatProvider(database: database);
      addTearDown(provider.dispose);
      await provider.selectChat(1);
      expect(provider.currentPersona?.id, 7);
      await provider.selectChat(2);
      expect(provider.currentPersona, isNull);
      await provider.selectChat(1);
      await provider.selectChat(3);
      expect(provider.currentPersona, isNull);
    },
  );
}

class _RacingPersonaDatabase extends _SelectionDatabase {
  Persona? value = Persona(id: 7, name: 'Original', systemPrompt: 'Old');
  final entered = Completer<void>();
  final release = Completer<void>();
  int reads = 0;

  @override
  Future<Map<String, dynamic>?> getPersona(int id) async {
    final snapshot = value?.toMap();
    reads++;
    if (reads == 1) {
      entered.complete();
      await release.future;
    }
    return snapshot;
  }
}

class _PersonaWriteDatabase extends _SelectionDatabase {
  bool deleted = false;
  int? personaAtDeletion;

  @override
  Future<Map<String, dynamic>?> getPersona(int id) async => {
    'id': id,
    'name': 'Disposable',
    'system_prompt': 'Test',
    'is_default': 0,
  };

  @override
  Future<List<Chat>> getChats() async => [];

  @override
  Future<int> deleteChat(int id) async {
    personaAtDeletion = personaId;
    deleted = true;
    return 1;
  }

  int? personaId = 7;
  bool failReplacement = false;
  bool failRemoval = false;
  Completer<void>? writeGate;
  final writeEntered = Completer<void>();
  final writes = <int>[];

  @override
  Future<int?> getChatPersona(int chatId) async =>
      chatId == 1 ? personaId : null;

  @override
  Future<int> setChatPersona(int chatId, int personaId) async {
    writes.add(personaId);
    if (!writeEntered.isCompleted) writeEntered.complete();
    await writeGate?.future;
    if (failReplacement) throw StateError('Disposable replacement failure');
    this.personaId = personaId;
    return 1;
  }

  @override
  Future<int> removeChatPersona(int chatId) async {
    if (failRemoval) throw StateError('Disposable removal failure');
    personaId = null;
    return 1;
  }
}

class _DelayedRegistry implements ModelRegistryService {
  final validated = Completer<ModelDescriptor>();
  @override
  Future<ModelDescriptor> requireInstalled(String id) => validated.future;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected registry operation');
}

class _SelectionDatabase implements DatabaseHelper {
  int createdChats = 0;
  @override
  Future<int> insertChatWithModel(
    Map<String, dynamic> chat,
    String modelId, {
    void Function()? beforeCommit,
  }) async {
    beforeCommit?.call();
    createdChats++;
    return 4;
  }

  final assignments = <(int, String)>[];
  @override
  Future<void> assignModelForChat(int chatId, String modelId) async =>
      assignments.add((chatId, modelId));
  @override
  Future<Chat?> getChat(int id) async => Chat(
    id: id,
    title: 'Disposable',
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
  Future<int?> getChatPersona(int chatId) async => chatId == 2
      ? null
      : chatId == 1
      ? 7
      : 8;
  @override
  Future<Map<String, dynamic>?> getPersona(int id) async => id == 7
      ? {
          'id': 7,
          'name': 'Disposable',
          'system_prompt': 'Test',
          'is_default': 0,
        }
      : null;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected database operation');
}

class _DelayedAssignmentDatabase extends _SelectionDatabase {
  final entered = Completer<void>();
  final finish = Completer<void>();
  @override
  Future<void> assignModelForChat(int chatId, String modelId) async {
    entered.complete();
    await finish.future;
    await super.assignModelForChat(chatId, modelId);
  }
}

class _DelayedChatDatabase extends _SelectionDatabase {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<Chat?> getChat(int id) async {
    if (id == 1) {
      entered.complete();
      await release.future;
    }
    return super.getChat(id);
  }
}

class _WaitingGeneration implements GenerationProvider {
  final stopped = Completer<void>();
  int stopCalls = 0;
  @override
  bool get isSending => !stopped.isCompleted;
  @override
  Future<void> stopSending() async {
    stopCalls++;
    await stopped.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _DelayedCreateDatabase extends _SelectionDatabase {
  final entered = Completer<void>();
  final finish = Completer<void>();
  @override
  Future<int> insertChatWithModel(
    Map<String, dynamic> chat,
    String modelId, {
    void Function()? beforeCommit,
  }) async {
    entered.complete();
    await finish.future;
    return super.insertChatWithModel(chat, modelId, beforeCommit: beforeCommit);
  }
}
