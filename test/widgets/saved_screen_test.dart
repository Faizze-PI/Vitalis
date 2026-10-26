import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vitalis_app/constants/app_strings.dart';
import 'package:vitalis_app/models/note.dart';
import 'package:vitalis_app/models/persona.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/providers/note_provider.dart';
import 'package:vitalis_app/providers/persona_provider.dart';
import 'package:vitalis_app/screens/saved_screen.dart';
import 'package:vitalis_app/screens/modals/persona_selection_modal.dart';
import 'package:vitalis_app/services/startup_access_guard.dart';

void main() {
  for (final writable in [true, false]) {
    for (final section in ['Notes', 'Personas']) {
      testWidgets(
        '$section opens a preview without selecting content (writable: $writable)',
        (tester) async {
          await _pump(tester, writable);
          await tester.tap(find.text(section));
          await tester.pumpAndSettle();
          final title = section == 'Notes' ? 'Fixture note' : 'Fixture persona';
          await tester.tap(find.widgetWithText(ListTile, title));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text(
                section == 'Notes'
                    ? 'Fixture note content'
                    : 'Fixture persona instructions',
              ),
            ),
            findsOneWidget,
          );
          expect(find.text(AppStrings.personaNone), findsNothing);
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          expect(find.widgetWithText(ListTile, title), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('creating a persona from Saved keeps the management page open', (
    tester,
  ) async {
    await _pump(tester, true);
    await tester.tap(find.text('Personas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.createNewPersona));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text(AppStrings.cancel));
    await tester.pumpAndSettle();
    expect(find.byType(PersonaSelectionModal), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pump(WidgetTester tester, bool writable) async {
  final notes = _Notes();
  final personas = _Personas();
  addTearDown(notes.dispose);
  addTearDown(personas.dispose);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<NoteProvider>.value(value: notes),
        ChangeNotifierProvider<PersonaProvider>.value(value: personas),
        Provider<StartupAccessGuard>.value(
          value: StartupAccessGuard(
            () => StartupCapabilities(
              databaseReady: true,
              migrationReady: true,
              safetyReady: true,
              modelReadiness: writable
                  ? StartupModelReadiness.ready
                  : StartupModelReadiness.missing,
            ),
          ),
        ),
      ],
      child: const MaterialApp(home: SavedScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

class _Notes extends ChangeNotifier implements NoteProvider {
  @override
  bool get isLoading => false;
  @override
  List<Note> get notes => [
    Note(id: 1, title: 'Fixture note', content: 'Fixture note content'),
  ];
  @override
  Future<void> loadNotes() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Personas extends ChangeNotifier implements PersonaProvider {
  @override
  bool get isLoading => false;
  @override
  List<Persona> get personas => [
    Persona(
      id: 1,
      name: 'Fixture persona',
      systemPrompt: 'Fixture persona instructions',
    ),
  ];
  @override
  Future<void> loadPersonas() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
