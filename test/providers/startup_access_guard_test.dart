import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/database/database_helper.dart';
import 'package:vitalis_app/models/note.dart';
import 'package:vitalis_app/models/persona.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/providers/note_provider.dart';
import 'package:vitalis_app/providers/chat_provider.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/providers/persona_provider.dart';
import 'package:vitalis_app/services/startup_access_guard.dart';

const readOnly = StartupCapabilities(
  databaseReady: true,
  migrationReady: true,
  safetyReady: true,
  modelReadiness: StartupModelReadiness.missing,
);
const ready = StartupCapabilities(
  databaseReady: true,
  migrationReady: true,
  safetyReady: true,
  modelReadiness: StartupModelReadiness.ready,
);

void main() {
  test(
    'model switching rejects unavailable prerequisites and disposed owners',
    () async {
      final database = _ReadDatabase();
      final chat = ChatProvider(
        database: database,
        startupAccess: StartupAccessGuard(
          () => const StartupCapabilities(
            databaseReady: false,
            migrationReady: false,
            safetyReady: false,
            modelReadiness: StartupModelReadiness.unknown,
          ),
        ),
      );
      await expectLater(
        chat.switchModel('Disposable'),
        throwsA(isA<StartupAccessDenied>()),
      );
      chat.dispose();
      await expectLater(chat.switchModel('Disposable'), throwsStateError);
      expect(database.unexpectedCalls, 0);
    },
  );
  test(
    'read-only chat rejects mutations before any persistence or generation',
    () async {
      final database = _ReadDatabase();
      final chat = ChatProvider(
        database: database,
        startupAccess: StartupAccessGuard(() => readOnly),
      );
      addTearDown(chat.dispose);
      final operations = <Future<dynamic> Function()>[
        () => chat.createChat(),
        () => chat.deleteChat(1),
        () => chat.sendMessage('Disposable'),
        () => chat.retryLastMessage(),
        () => chat.regenerate(),
        () => chat.attachNote(null),
        () => chat.clearAttachedNote(),
        () => chat.updateChatTitle(1, 'Disposable'),
        () => chat.updateSettings(ModelSettings()),
        () =>
            chat.setPersona(Persona(name: 'Disposable', systemPrompt: 'Test')),
        () => chat.removePersona(),
      ];
      for (final operation in operations) {
        await expectLater(operation(), throwsA(isA<StartupAccessDenied>()));
      }
      expect(
        () => chat.updateSettingsLocally(ModelSettings()),
        throwsA(isA<StartupAccessDenied>()),
      );
      await chat.stopSending();
      expect(database.unexpectedCalls, 0);
    },
  );
  test('guard reads current permission rather than remembered readiness', () {
    var snapshot = ready;
    final guard = StartupAccessGuard(() => snapshot);
    guard.require(StartupAccessOperation.inference);
    snapshot = readOnly;
    expect(
      () => guard.require(StartupAccessOperation.inference),
      throwsA(isA<StartupAccessDenied>()),
    );
    guard.require(StartupAccessOperation.browse);
    guard.require(StartupAccessOperation.recoverModels);
    expect(
      () => guard.require(StartupAccessOperation.mutateContent),
      throwsA(isA<StartupAccessDenied>()),
    );
  });

  test('read-only note/persona browsing reaches reads but no writes', () async {
    final database = _ReadDatabase();
    final guard = StartupAccessGuard(() => readOnly);
    final notes = NoteProvider(database: database, startupAccess: guard);
    final personas = PersonaProvider(database: database, startupAccess: guard);
    addTearDown(notes.dispose);
    addTearDown(personas.dispose);
    await notes.loadNotes();
    await personas.loadPersonas();
    expect(database.reads, 2);
    final operations = <Future<void> Function()>[
      () async {
        await notes.createNote('fixture', 'content');
      },
      () => notes.updateNote(Note(id: 1, title: 'fixture', content: 'content')),
      () => notes.deleteNote(1),
      () async {
        await personas.createPersona('fixture', 'instructions');
      },
      () => personas.updatePersona(
        Persona(id: 1, name: 'fixture', systemPrompt: 'instructions'),
      ),
      () => personas.deletePersona(1),
    ];
    for (final operation in operations) {
      await expectLater(operation(), throwsA(isA<StartupAccessDenied>()));
    }
    expect(database.unexpectedCalls, 0);
    expect(notes.notes, isEmpty);
    expect(personas.personas, isEmpty);
  });

  test(
    'disposed providers reject new work without touching persistence',
    () async {
      final database = _ReadDatabase();
      final notes = NoteProvider(database: database);
      final personas = PersonaProvider(database: database);
      notes.dispose();
      personas.dispose();
      await expectLater(notes.loadNotes(), throwsStateError);
      await expectLater(
        notes.createNote('fixture', 'content'),
        throwsStateError,
      );
      await expectLater(personas.loadPersonas(), throwsStateError);
      await expectLater(
        personas.createPersona('fixture', 'instructions'),
        throwsStateError,
      );
      expect(database.reads, 0);
      expect(database.unexpectedCalls, 0);
    },
  );
}

final class _ReadDatabase implements DatabaseHelper {
  int reads = 0;
  int unexpectedCalls = 0;
  @override
  Future<List<Map<String, dynamic>>> getNotes() async {
    reads++;
    return [];
  }

  @override
  Future<List<Map<String, dynamic>>> getPersonas() async {
    reads++;
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    unexpectedCalls++;
    throw StateError('Unexpected database operation');
  }
}
