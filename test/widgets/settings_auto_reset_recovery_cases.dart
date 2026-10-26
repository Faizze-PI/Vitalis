part of 'settings_recovery_test.dart';

void _registerAutoResetCases() {
  testWidgets('pending Auto reset preserves newer same-chat settings', (
    tester,
  ) async {
    final runtime = _ResetWarmup()..pending = Completer<void>();
    final fixture = await _pump(
      tester,
      ready: true,
      advanced: true,
      runtime: runtime,
    );
    final action = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Reset to Auto'))
        .onPressed!;
    action();
    await tester.pump();
    fixture.chat.value = fixture.chat.value.copyWith(
      systemPrompt: 'Disposable edit made during reset',
      temperature: 0.3,
    );
    runtime.pending!.complete();
    await tester.pumpAndSettle();
    expect(
      fixture.chat.settings.systemPrompt,
      'Disposable edit made during reset',
    );
    expect(fixture.chat.settings.temperature, 0.3);
    expect(fixture.chat.settings.tuningMode, TuningMode.automatic);
    expect(fixture.chat.updates, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending Auto reset rejects repeated stale actions', (
    tester,
  ) async {
    final runtime = _ResetWarmup()..pending = Completer<void>();
    final fixture = await _pump(
      tester,
      ready: true,
      advanced: true,
      runtime: runtime,
    );
    final action = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Reset to Auto'))
        .onPressed!;
    action();
    action();
    await tester.pump();
    final resetsBeforeAcknowledgement = runtime.resets;
    runtime.pending!.complete();
    await tester.pumpAndSettle();
    expect(resetsBeforeAcknowledgement, 1);
    expect(fixture.chat.updates, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposed Auto reset cannot start a settings write', (
    tester,
  ) async {
    final runtime = _ResetWarmup()..pending = Completer<void>();
    final fixture = await _pump(
      tester,
      ready: true,
      advanced: true,
      runtime: runtime,
    );
    final action = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Reset to Auto'))
        .onPressed!;
    action();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    runtime.pending!.complete();
    await tester.pumpAndSettle();
    expect(fixture.chat.updates, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed Auto reset retains settings and redacts diagnostics', (
    tester,
  ) async {
    final runtime = _ResetWarmup()
      ..failure = StateError('/private/model-path token=secret');
    final fixture = await _pump(
      tester,
      ready: true,
      advanced: true,
      runtime: runtime,
    );
    final saved = fixture.chat.settings;
    final action = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Reset to Auto'))
        .onPressed!;
    action();
    await tester.pumpAndSettle();
    expect(fixture.chat.settings, same(saved));
    expect(fixture.chat.updates, 0);
    expect(find.textContaining('token=secret'), findsNothing);
    expect(
      find.text('The change could not be saved. Please retry.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

final class _ResetWarmup extends _Warmup {
  Completer<void>? pending;
  Object? failure;
  int resets = 0;

  @override
  Future<void> resetAutoProfile(ModelSettings settings) async {
    resets++;
    await pending?.future;
    if (failure case final Object error) throw error;
  }
}
