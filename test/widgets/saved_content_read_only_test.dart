import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vitalis_app/constants/app_strings.dart';
import 'package:vitalis_app/models/note.dart';
import 'package:vitalis_app/models/persona.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/providers/note_provider.dart';
import 'package:vitalis_app/providers/persona_provider.dart';
import 'package:vitalis_app/screens/modals/note_edit_modal.dart';
import 'package:vitalis_app/screens/modals/notes_list_selection_modal.dart';
import 'package:vitalis_app/screens/modals/persona_selection_modal.dart';
import 'package:vitalis_app/services/startup_access_guard.dart';
import 'package:vitalis_app/widgets/startup_mutation_access.dart';

StartupCapabilities capabilities(bool ready) => StartupCapabilities(
  databaseReady: true,
  migrationReady: true,
  safetyReady: true,
  modelReadiness: ready
      ? StartupModelReadiness.ready
      : StartupModelReadiness.missing,
);

void main() {
  for (final personas in [false, true]) {
    testWidgets(
      'read-only ${personas ? 'personas' : 'notes'} can be previewed without mutation',
      (tester) async {
        final notes = _Notes();
        final savedPersonas = _Personas();
        addTearDown(notes.dispose);
        addTearDown(savedPersonas.dispose);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<StartupAccessGuard?>.value(
                value: StartupAccessGuard(() => capabilities(false)),
              ),
              ChangeNotifierProvider<NoteProvider>.value(value: notes),
              ChangeNotifierProvider<PersonaProvider>.value(
                value: savedPersonas,
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: personas
                    ? const PersonaSelectionModal()
                    : const NotesListSelectionModal(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final create = personas
            ? AppStrings.createNewPersona
            : AppStrings.createNewNote;
        expect(
          tester.widget<ListTile>(find.widgetWithText(ListTile, create)).onTap,
          isNull,
        );
        for (final button in tester.widgetList<IconButton>(
          find.byType(IconButton),
        )) {
          expect(button.onPressed, isNull);
        }
        await tester.tap(
          find.text(personas ? 'Disposable persona' : 'Disposable note'),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<SelectableText>(find.byType(SelectableText)).data,
          personas
              ? 'Full disposable persona instructions.'
              : 'Full disposable note text.',
        );
        expect(notes.writes + savedPersonas.writes, 0);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('open note editor retains its draft while readiness changes', (
    tester,
  ) async {
    var ready = true;
    final signal = _Signal();
    addTearDown(signal.dispose);
    Map<String, String>? saved;
    var finished = false;
    await tester.pumpWidget(
      Provider<StartupAccessGuard?>.value(
        value: StartupAccessGuard(() => capabilities(ready), changes: signal),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  saved = await showDialog<Map<String, String>>(
                    context: context,
                    builder: (_) => NoteEditModal(note: _Notes.seed),
                  );
                  finished = true;
                },
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Disposable draft');
    ready = false;
    signal.emit();
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, AppStrings.save))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Disposable draft',
    );
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .every((field) => field.readOnly),
      isTrue,
    );
    expect(finished, isFalse);
    ready = true;
    signal.emit();
    await tester.pump();
    await tester.tap(find.text(AppStrings.save));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    expect(saved?['title'], 'Disposable draft');
    await tester.pumpWidget(const SizedBox());
    expect(signal.hasObservers, isFalse);
  });

  testWidgets('a stale Save callback rechecks current permissions', (
    tester,
  ) async {
    var ready = true;
    await tester.pumpWidget(
      Provider<StartupAccessGuard?>.value(
        value: StartupAccessGuard(() => capabilities(ready)),
        child: MaterialApp(
          home: Scaffold(body: NoteEditModal(note: _Notes.seed)),
        ),
      ),
    );
    final save = tester
        .widget<TextButton>(find.widgetWithText(TextButton, AppStrings.save))
        .onPressed!;
    ready = false;
    save();
    await tester.pump();
    expect(find.byType(NoteEditModal), findsOneWidget);
    expect(
      find.text('Editing is unavailable while the app is recovering.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final missing in [false, true]) {
    testWidgets(
      'permission evidence ${missing ? 'missing' : 'unreadable'} disables editing',
      (tester) async {
        final editor = MaterialApp(
          home: Scaffold(body: NoteEditModal(note: _Notes.seed)),
        );
        await tester.pumpWidget(
          missing
              ? editor
              : Provider<StartupAccessGuard?>.value(
                  value: StartupAccessGuard(
                    () => throw StateError('disposable unavailable snapshot'),
                  ),
                  child: editor,
                ),
        );
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, AppStrings.save),
              )
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('saved-note collection remains scrollable in read-only mode', (
    tester,
  ) async {
    final notes = _Notes(count: 20);
    addTearDown(notes.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StartupAccessGuard?>.value(
            value: StartupAccessGuard(() => capabilities(false)),
          ),
          ChangeNotifierProvider<NoteProvider>.value(value: notes),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NotesListSelectionModal()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsWidgets);
  });

  testWidgets('saved-persona collection remains scrollable in read-only mode', (
    tester,
  ) async {
    final personas = _Personas(count: 20);
    addTearDown(personas.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<StartupAccessGuard?>.value(
            value: StartupAccessGuard(() => capabilities(false)),
          ),
          ChangeNotifierProvider<PersonaProvider>.value(value: personas),
        ],
        child: const MaterialApp(home: Scaffold(body: PersonaSelectionModal())),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsWidgets);
  });

  testWidgets(
    'persona submission rejects duplicate actions while persistence is pending',
    (tester) async {
      final personas = _Personas()..creation = Completer<Persona?>();
      addTearDown(personas.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<StartupAccessGuard?>.value(
              value: StartupAccessGuard(() => capabilities(true)),
            ),
            ChangeNotifierProvider<PersonaProvider>.value(value: personas),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const PersonaSelectionModal(),
                  ),
                  child: const Text('Open personas'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open personas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.createNewPersona));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        'Disposable new persona',
      );
      await tester.enterText(
        find.byType(TextField).last,
        'Disposable instructions.',
      );
      final submit = tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, AppStrings.create),
          )
          .onPressed!;
      submit();
      await tester.pump();
      submit();
      expect(personas.writes, 1);
      expect(
        tester.widget<TextButton>(find.byType(TextButton).last).onPressed,
        isNull,
      );
      personas.creation!.complete(
        Persona(
          id: 2,
          name: 'Disposable new persona',
          systemPrompt: 'Disposable instructions.',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(personas.writes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final denied in [false, true]) {
    testWidgets(
      'saved-content failure presents a redacted ${denied ? 'permission' : 'storage'} message',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => StartupMutationAccess.reportFailure(
                    context,
                    denied
                        ? StartupAccessDenied(
                            StartupAccessOperation.mutateContent,
                          )
                        : StateError('disposable-private-path'),
                  ),
                  child: const Text('Injected failure'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Injected failure'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            denied
                ? 'Editing is unavailable while the app is recovering.'
                : 'The change could not be saved. Please retry.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('disposable-private-path'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('retired saved-content context does not receive failure UI', (
    tester,
  ) async {
    late BuildContext retired;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              retired = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    StartupMutationAccess.reportFailure(
      retired,
      StateError('disposable retired failure'),
    );
    expect(tester.takeException(), isNull);
  });
}

class _Signal extends ChangeNotifier {
  bool get hasObservers => hasListeners;
  void emit() => notifyListeners();
}

class _Notes extends NoteProvider {
  _Notes({this.count = 1});
  final int count;
  int writes = 0;
  static final seed = Note(
    id: 1,
    title: 'Disposable note',
    content: 'Full disposable note text.',
  );
  @override
  List<Note> get notes => List.generate(
    count,
    (index) => index == 0
        ? seed
        : Note(
            id: index + 1,
            title: 'Disposable $index',
            content: 'Bounded fixture.',
          ),
  );
  @override
  Future<void> loadNotes() async {}
  @override
  Future<Note?> createNote(String title, String content) async {
    writes++;
    return null;
  }

  @override
  Future<void> updateNote(Note note) async {
    writes++;
  }

  @override
  Future<void> deleteNote(int id) async {
    writes++;
  }
}

class _Personas extends PersonaProvider {
  _Personas({this.count = 1});
  final int count;
  Completer<Persona?>? creation;
  int writes = 0;
  @override
  List<Persona> get personas => List.generate(
    count,
    (index) => Persona(
      id: index + 1,
      name: index == 0 ? 'Disposable persona' : 'Disposable persona $index',
      systemPrompt: 'Full disposable persona instructions.',
    ),
  );
  @override
  Future<Persona?> createPersona(String name, String systemPrompt) {
    writes++;
    return creation?.future ?? Future.value(null);
  }

  @override
  Future<void> loadPersonas() async {}
  @override
  Future<bool> deletePersona(int id) async {
    writes++;
    return true;
  }
}
