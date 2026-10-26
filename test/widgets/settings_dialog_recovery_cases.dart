part of 'settings_recovery_test.dart';

StartupCapabilities _dialogCapabilities(bool ready) => StartupCapabilities(
  databaseReady: true,
  migrationReady: true,
  safetyReady: true,
  modelReadiness: ready
      ? StartupModelReadiness.ready
      : StartupModelReadiness.missing,
);

void _registerDialogRecoveryCases() {
  testWidgets('pending system-prompt Save rejects a repeated stale action', (
    tester,
  ) async {
    final fixture = await _pump(tester, ready: true);
    final pending = Completer<void>();
    fixture.chat.pendingSave = pending;
    await tester.tap(find.text('System prompt'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Disposable pending draft');
    final save = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
        .onPressed!;
    save();
    save();
    await tester.pump();
    expect(fixture.chat.saveAttempts, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    pending.complete();
    await tester.pumpAndSettle();
    expect(fixture.chat.updates, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposed prompt editor rejects late save failure feedback', (
    tester,
  ) async {
    final fixture = await _pump(tester, ready: true);
    final pending = Completer<void>();
    fixture.chat.pendingSave = pending;
    await tester.tap(find.text('System prompt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.completeError(StateError('/private/disposable failure'));
    await tester.pumpAndSettle();
    expect(fixture.chat.updates, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty prompt stays editable without starting persistence', (
    tester,
  ) async {
    final fixture = await _pump(tester, ready: true);
    await tester.tap(find.text('System prompt'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('System prompt cannot be empty.'), findsOneWidget);
    expect(fixture.chat.saveAttempts, 0);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('changed chat selection cannot receive an old prompt draft', (
    tester,
  ) async {
    final fixture = await _pump(tester, ready: true);
    await tester.tap(find.text('System prompt'));
    await tester.pumpAndSettle();
    fixture.chat.selectedChat = Chat(
      id: 2,
      title: 'Disposable new chat',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await tester.enterText(find.byType(TextField), 'Old chat draft');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(fixture.chat.saveAttempts, 0);
    expect(
      find.text('The change could not be saved. Your draft is retained.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('system-prompt draft survives live readiness revocation', (
    tester,
  ) async {
    var ready = true;
    final changes = _DialogSignal();
    addTearDown(changes.dispose);
    final fixture = await _pump(
      tester,
      ready: true,
      access: StartupAccessGuard(
        () => _dialogCapabilities(ready),
        changes: changes,
      ),
    );
    await tester.tap(find.text('System prompt'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Disposable retained draft');
    ready = false;
    changes.emit();
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Disposable retained draft',
    );
    ready = true;
    changes.emit();
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(fixture.chat.settings.systemPrompt, 'Disposable retained draft');
    expect(fixture.chat.updates, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'stale system-prompt Save rechecks access without losing the draft',
    (tester) async {
      var ready = true;
      final fixture = await _pump(
        tester,
        ready: true,
        access: StartupAccessGuard(() => _dialogCapabilities(ready)),
      );
      await tester.tap(find.text('System prompt'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Disposable stale draft');
      final save = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
          .onPressed!;
      ready = false;
      save();
      await tester.pumpAndSettle();
      expect(fixture.chat.updates, 0);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        find.text('Editing is unavailable while the app is recovering.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed system-prompt save retains draft and allows retry', (
    tester,
  ) async {
    final fixture = await _pump(tester, ready: true);
    fixture.chat.saveFailure = StateError(
      '/private/personal-data token=secret',
    );
    await tester.tap(find.text('System prompt'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Disposable retry draft');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('personal-data'), findsNothing);
    expect(find.textContaining('token=secret'), findsNothing);
    expect(
      find.text('The change could not be saved. Your draft is retained.'),
      findsOneWidget,
    );
    fixture.chat.saveFailure = null;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(fixture.chat.settings.systemPrompt, 'Disposable retry draft');
    expect(fixture.chat.updates, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposed Settings cannot activate a pending import', (
    tester,
  ) async {
    final fixture = await _pump(tester, ready: false, appSettings: true);
    final pending = Completer<ModelDescriptor?>();
    fixture.registry.pending = pending;
    await tester.tap(find.text('Import local GGUF model'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(_model);
    await tester.pumpAndSettle();
    expect(fixture.registry.activations, 0);
    expect(fixture.chat.updates, 0);
    expect(tester.takeException(), isNull);
  });
}

final class _DialogSignal extends ChangeNotifier {
  void emit() => notifyListeners();
}
