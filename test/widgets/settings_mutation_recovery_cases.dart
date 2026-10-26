part of 'settings_recovery_test.dart';

void _registerSettingsMutationCases() {
  testWidgets(
    'slider preview and commit preserve the selected settings owner',
    (tester) async {
      final fixture = await _pump(tester, ready: true, advanced: true);
      final slider = tester.widgetList<Slider>(find.byType(Slider)).first;
      slider.onChanged!(2048);
      await tester.pump();
      expect(fixture.chat.previews, 1);
      expect(fixture.chat.settings.contextSizeOverride, 2048);
      slider.onChangeEnd!(2048);
      await tester.pumpAndSettle();
      expect(fixture.chat.updates, 1);
      expect(fixture.chat.settings.modelId, 'original-chat-model');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settings callbacks after disposal cannot start writes', (
    tester,
  ) async {
    final fixture = await _pump(tester, ready: true, advanced: true);
    final slider = tester.widgetList<Slider>(find.byType(Slider)).first;
    await tester.pumpWidget(const SizedBox());
    slider.onChanged!(2048);
    slider.onChangeEnd!(2048);
    await tester.pumpAndSettle();
    expect(fixture.chat.previews, 0);
    expect(fixture.chat.updates, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings save failure after navigation has no late UI error', (
    tester,
  ) async {
    final fixture = await _pump(tester, ready: true);
    final pending = Completer<void>();
    fixture.chat.pendingSave = pending;
    await tester.tap(find.text('Thinking mode'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.completeError(StateError('/private/preferences token=secret'));
    await tester.pumpAndSettle();
    expect(fixture.chat.updates, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('thinking-mode save failure produces redacted feedback', (
    tester,
  ) async {
    final fixture = await _pump(tester, ready: true);
    fixture.chat.saveFailure = StateError('/private/preferences token=secret');
    await tester.tap(find.text('Thinking mode'));
    await tester.pumpAndSettle();
    expect(fixture.chat.updates, 0);
    expect(
      find.text('The change could not be saved. Please retry.'),
      findsOneWidget,
    );
    expect(find.textContaining('token=secret'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale slider preview handles readiness loss', (tester) async {
    var ready = true;
    final fixture = await _pump(
      tester,
      ready: true,
      advanced: true,
      access: StartupAccessGuard(() => _dialogCapabilities(ready)),
    );
    final change = tester
        .widgetList<Slider>(find.byType(Slider))
        .first
        .onChanged!;
    ready = false;
    expect(() => change(2048), returnsNormally);
    await tester.pumpAndSettle();
    expect(fixture.chat.updates, 0);
    expect(
      find.text('Editing is unavailable while the app is recovering.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('old slider persistence cannot modify a newly selected chat', (
    tester,
  ) async {
    final fixture = await _pump(tester, ready: true, advanced: true);
    final finish = tester
        .widgetList<Slider>(find.byType(Slider))
        .first
        .onChangeEnd!;
    fixture.chat.selectedChat = Chat(
      id: 2,
      title: 'Disposable replacement',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    finish(2048);
    await tester.pumpAndSettle();
    expect(fixture.chat.updates, 0);
    expect(fixture.chat.settings.temperature, 0.7);
    expect(tester.takeException(), isNull);
  });
}
