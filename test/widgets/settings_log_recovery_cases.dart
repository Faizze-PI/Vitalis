part of 'settings_recovery_test.dart';

void _registerLogRecoveryCases() {
  testWidgets('repeated log-clear actions open one confirmation', (
    tester,
  ) async {
    var directoryReads = 0;
    final logger = AppLogger.forTesting(
      directoryResolver: () async {
        directoryReads++;
        throw StateError('No filesystem access expected');
      },
      privacyLoader: () async => true,
      privacySaver: (_) async {},
      clock: () => DateTime(2026),
    );
    await _pump(tester, appSettings: true, ready: true, logging: logger);
    final action = tester
        .widget<ListTile>(find.widgetWithText(ListTile, AppStrings.clearLogs))
        .onTap!;
    action();
    action();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
    await tester.tap(find.text(AppStrings.cancel));
    await tester.pumpAndSettle();
    expect(directoryReads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed log cleanup never reports success', (tester) async {
    final logger = AppLogger.forTesting(
      directoryResolver: () async =>
          throw StateError('/private/logs token=secret'),
      privacyLoader: () async => true,
      privacySaver: (_) async {},
      clock: () => DateTime(2026),
    );
    await _pump(tester, appSettings: true, ready: true, logging: logger);
    await tester.tap(find.widgetWithText(ListTile, AppStrings.clearLogs));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.confirm));
    await tester.pumpAndSettle();
    expect(find.text('${AppStrings.clearLogs} — done'), findsNothing);
    expect(
      find.text('Some logs could not be removed. Please retry.'),
      findsOneWidget,
    );
    expect(find.textContaining('token=secret'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
