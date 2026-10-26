part of 'settings_recovery_test.dart';

void _registerPreferenceRecoveryCases() {
  testWidgets('pending privacy save rejects repeated stale actions', (
    tester,
  ) async {
    final saved = Completer<void>();
    var attempts = 0;
    final logger = AppLogger.forTesting(
      directoryResolver: () async => throw StateError('Unexpected log access'),
      privacyLoader: () async => true,
      privacySaver: (_) {
        attempts++;
        return saved.future;
      },
      clock: () => DateTime(2026),
    );
    await _pump(tester, ready: true, logging: logger);
    final finder = find.widgetWithText(SwitchListTile, AppStrings.privacyMode);
    final action = tester.widget<SwitchListTile>(finder).onChanged!;
    action(false);
    action(false);
    await tester.pump();
    expect(attempts, 1);
    expect(tester.widget<SwitchListTile>(finder).onChanged, isNull);
    expect(logger.isPrivacyMode, isTrue);
    saved.complete();
    await tester.pumpAndSettle();
    expect(logger.isPrivacyMode, isFalse);
    expect(tester.widget<SwitchListTile>(finder).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('privacy persistence can retry after a redacted failure', (
    tester,
  ) async {
    var attempts = 0;
    final logger = AppLogger.forTesting(
      directoryResolver: () async => throw StateError('Unexpected log access'),
      privacyLoader: () async => true,
      privacySaver: (_) async {
        if (++attempts == 1) throw StateError('/private/token=secret');
      },
      clock: () => DateTime(2026),
    );
    await _pump(tester, ready: true, logging: logger);
    final finder = find.widgetWithText(SwitchListTile, AppStrings.privacyMode);
    tester.widget<SwitchListTile>(finder).onChanged!(false);
    await tester.pumpAndSettle();
    expect(logger.isPrivacyMode, isTrue);
    tester.widget<SwitchListTile>(finder).onChanged!(false);
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(logger.isPrivacyMode, isFalse);
    expect(find.textContaining('token=secret'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('privacy failure after navigation has no late UI publication', (
    tester,
  ) async {
    final saved = Completer<void>();
    var attempts = 0;
    final logger = AppLogger.forTesting(
      directoryResolver: () async => throw StateError('Unexpected log access'),
      privacyLoader: () async => true,
      privacySaver: (_) {
        attempts++;
        return saved.future;
      },
      clock: () => DateTime(2026),
    );
    await _pump(tester, ready: true, logging: logger);
    final action = tester
        .widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, AppStrings.privacyMode),
        )
        .onChanged!;
    action(false);
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    action(false);
    saved.completeError(StateError('/private/token=secret'));
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(logger.isPrivacyMode, isTrue);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed privacy persistence retains protection and reports failure',
    (tester) async {
      final logger = AppLogger.forTesting(
        directoryResolver: () async =>
            throw StateError('No log storage expected'),
        privacyLoader: () async => true,
        privacySaver: (_) async =>
            throw StateError('/private/preferences token=secret'),
        clock: () => DateTime(2026),
      );
      await _pump(tester, ready: true, logging: logger);
      final toggle = tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, AppStrings.privacyMode),
          )
          .onChanged!;
      toggle(false);
      await tester.pumpAndSettle();
      expect(logger.isPrivacyMode, isTrue);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, AppStrings.privacyMode),
            )
            .value,
        isTrue,
      );
      expect(
        find.text('The change could not be saved. Please retry.'),
        findsOneWidget,
      );
      expect(find.textContaining('token=secret'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'read-only Settings disables persistent preferences and log deletion',
    (tester) async {
      await _pump(tester, ready: false);
      for (final label in [AppStrings.darkMode, AppStrings.privacyMode]) {
        expect(
          tester
              .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, label),
              )
              .onChanged,
          isNull,
        );
      }
      expect(
        tester
            .widget<ListTile>(
              find.widgetWithText(ListTile, AppStrings.clearLogs),
            )
            .onTap,
        isNull,
      );
    },
  );

  testWidgets('failed Settings theme action produces redacted feedback', (
    tester,
  ) async {
    final appearance = _ThemeAction()
      ..failure = StateError('/private/preferences token=secret');
    await _pump(tester, ready: true, appearance: appearance);
    final action = tester
        .widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, AppStrings.darkMode),
        )
        .onChanged!;
    action(true);
    await tester.pumpAndSettle();
    expect(appearance.calls, 1);
    expect(find.textContaining('token=secret'), findsNothing);
    expect(
      find.text('The change could not be saved. Please retry.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale theme action rechecks readiness before persistence', (
    tester,
  ) async {
    var ready = true;
    final appearance = _ThemeAction();
    await _pump(
      tester,
      ready: true,
      appearance: appearance,
      access: StartupAccessGuard(() => _dialogCapabilities(ready)),
    );
    final action = tester
        .widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, AppStrings.darkMode),
        )
        .onChanged!;
    ready = false;
    action(true);
    await tester.pumpAndSettle();
    expect(appearance.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retired Settings cannot submit a theme change', (tester) async {
    final appearance = _ThemeAction();
    await _pump(tester, ready: true, appearance: appearance);
    final action = tester
        .widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, AppStrings.darkMode),
        )
        .onChanged!;
    await tester.pumpWidget(const SizedBox());
    action(true);
    await tester.pumpAndSettle();
    expect(appearance.calls, 0);
    expect(tester.takeException(), isNull);
  });
}

final class _ThemeAction extends ThemeProvider {
  int calls = 0;
  Object? failure;

  @override
  Future<void> toggle() async {
    calls++;
    if (failure case final Object error) throw error;
  }
}
