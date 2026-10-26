import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vitalis_app/constants/app_strings.dart';
import 'package:vitalis_app/models/persona.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/providers/chat_provider.dart';
import 'package:vitalis_app/providers/persona_provider.dart';
import 'package:vitalis_app/screens/modals/persona_selection_modal.dart';
import 'package:vitalis_app/services/startup_access_guard.dart';

void main() {
  for (final succeeds in [false, true]) {
    testWidgets('persona deletion reports acknowledged result=$succeeds', (
      tester,
    ) async {
      final chat = _Chat();
      final personas = _Personas()..deletionResult = succeeds;
      await _open(tester, chat, savedPersonas: personas);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(personas.deletions, 0);
      await tester.tap(find.widgetWithText(TextButton, AppStrings.delete));
      await tester.pumpAndSettle();
      expect(personas.deletions, 1);
      expect(find.byType(PersonaSelectionModal), findsOneWidget);
      expect(
        find.text('The change could not be saved. Please retry.'),
        succeeds ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  for (final removing in [false, true]) {
    final action = removing ? AppStrings.personaNone : 'Disposable persona';
    for (final succeeds in [false, true]) {
      testWidgets('$action save result=$succeeds controls modal closure', (
        tester,
      ) async {
        final chat = _Chat();
        await _open(tester, chat);
        await tester.tap(find.widgetWithText(ListTile, action));
        await tester.pump();
        expect(find.byType(PersonaSelectionModal), findsOneWidget);
        chat.result.complete(succeeds);
        await tester.pumpAndSettle();
        expect(
          find.byType(PersonaSelectionModal),
          succeeds ? findsNothing : findsOneWidget,
        );
        if (!succeeds) {
          expect(
            find.text('The change could not be saved. Please retry.'),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$action rejects duplicate submission while saving', (
      tester,
    ) async {
      final chat = _Chat();
      await _open(tester, chat);
      final submit = tester
          .widget<ListTile>(find.widgetWithText(ListTile, action))
          .onTap!;
      submit();
      await tester.pump();
      submit();
      final submitted = chat.writes;
      chat.result.complete(true);
      await tester.pumpAndSettle();
      expect(submitted, 1);
      expect(find.byType(PersonaSelectionModal), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$action completion after dismissal cannot pop another page', (
      tester,
    ) async {
      final chat = _Chat();
      await _open(tester, chat);
      await tester.tap(find.widgetWithText(ListTile, action));
      await tester.pump();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();
      unawaited(
        navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Other page')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      chat.result.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Other page'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _open(
  WidgetTester tester,
  _Chat chat, {
  _Personas? savedPersonas,
}) async {
  final personas = savedPersonas ?? _Personas();
  // This fake owns no persistence; async close is covered by provider tests.
  addTearDown(chat.dispose);
  addTearDown(personas.dispose);
  final guard = StartupAccessGuard(
    () => const StartupCapabilities(
      databaseReady: true,
      migrationReady: true,
      safetyReady: true,
      modelReadiness: StartupModelReadiness.ready,
    ),
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<StartupAccessGuard?>.value(value: guard),
        ChangeNotifierProvider<ChatProvider>.value(value: chat),
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
}

class _Chat extends ChatProvider {
  final result = Completer<bool>();
  int writes = 0;
  @override
  Future<bool> setPersona(Persona persona) {
    writes++;
    return result.future;
  }

  @override
  Future<bool> removePersona() {
    writes++;
    return result.future;
  }
}

class _Personas extends PersonaProvider {
  bool deletionResult = true;
  int deletions = 0;

  @override
  Future<bool> deletePersona(int id) async {
    deletions++;
    return deletionResult;
  }

  @override
  List<Persona> get personas => [
    Persona(id: 7, name: 'Disposable persona', systemPrompt: 'Test'),
  ];
  @override
  Future<void> loadPersonas() async {}
}
