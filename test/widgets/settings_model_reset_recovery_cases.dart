part of 'settings_recovery_test.dart';

Future<VoidCallback> _modelResetAction(WidgetTester tester) async {
  final button = find.widgetWithText(
    ElevatedButton,
    AppStrings.resetModelButton,
  );
  await tester.scrollUntilVisible(button, 200);
  return tester.widget<ElevatedButton>(button).onPressed!;
}

void _registerModelResetCases() {
  for (final scenario in ['bundled', 'unrelated', 'busy']) {
    testWidgets('reset readiness is identity-scoped: $scenario', (
      tester,
    ) async {
      final readiness = SelectedModelReadiness(
        (_) async => StartupModelReadiness.ready,
      );
      addTearDown(readiness.dispose);
      final id = scenario == 'unrelated'
          ? 'disposable-other'
          : BundledModelManifest.id;
      await readiness.select(id);
      final transfers = _ResetTransfers();
      if (scenario == 'busy') transfers.failure = InferenceRuntimeBusy();
      await _pump(
        tester,
        ready: true,
        transfers: transfers,
        readiness: readiness,
      );
      (await _modelResetAction(tester))();
      await tester.pumpAndSettle();
      expect(
        find.textContaining(BundledModelManifest.displayName),
        findsWidgets,
      );
      await tester.tap(find.text(AppStrings.confirm));
      await tester.pumpAndSettle();
      expect(readiness.modelId, id);
      expect(
        readiness.readiness,
        scenario == 'bundled'
            ? StartupModelReadiness.unknown
            : StartupModelReadiness.ready,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'completed reset invalidates readiness after Settings navigation',
    (tester) async {
      final readiness = SelectedModelReadiness(
        (_) async => StartupModelReadiness.ready,
      );
      addTearDown(readiness.dispose);
      await readiness.select(BundledModelManifest.id);
      final transfers = _ResetTransfers()..pending = Completer<void>();
      await _pump(
        tester,
        ready: true,
        transfers: transfers,
        readiness: readiness,
      );
      (await _modelResetAction(tester))();
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.confirm));
      await tester.pumpAndSettle();
      expect(transfers.resets, 1);
      await tester.pumpWidget(const SizedBox());
      transfers.pending!.complete();
      await tester.pumpAndSettle();
      expect(readiness.readiness, StartupModelReadiness.unknown);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('model reset rejects repeated confirmation actions', (
    tester,
  ) async {
    final transfers = _ResetTransfers();
    await _pump(tester, ready: true, transfers: transfers);
    final action = await _modelResetAction(tester);
    action();
    action();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
    await tester.tap(find.text(AppStrings.cancel));
    await tester.pumpAndSettle();
    expect(transfers.resets, 0);
  });

  testWidgets('model reset rechecks readiness after confirmation', (
    tester,
  ) async {
    var ready = true;
    final transfers = _ResetTransfers();
    await _pump(
      tester,
      ready: true,
      transfers: transfers,
      access: StartupAccessGuard(() => _dialogCapabilities(ready)),
    );
    (await _modelResetAction(tester))();
    await tester.pumpAndSettle();
    ready = false;
    await tester.tap(find.text(AppStrings.confirm));
    await tester.pumpAndSettle();
    expect(transfers.resets, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('model reset errors remain observable and redacted', (
    tester,
  ) async {
    final transfers = _ResetTransfers()
      ..failure = StateError('/private/model token=secret');
    await _pump(tester, ready: true, transfers: transfers);
    (await _modelResetAction(tester))();
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.confirm));
    await tester.pumpAndSettle();
    expect(transfers.resets, 1);
    expect(find.textContaining('token=secret'), findsNothing);
    expect(
      find.text('The change could not be saved. Please retry.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('retired Settings cannot open reset confirmation', (
    tester,
  ) async {
    final transfers = _ResetTransfers();
    await _pump(tester, ready: true, transfers: transfers);
    final action = await _modelResetAction(tester);
    await tester.pumpWidget(const SizedBox());
    action();
    await tester.pumpAndSettle();
    expect(transfers.resets, 0);
    expect(tester.takeException(), isNull);
  });
}

final class _ResetTransfers extends ModelDownloadService {
  _ResetTransfers()
    : super(downloader: ModelDownloader(sentinel: _UnusedSafety()));
  int resets = 0;
  Object? failure;
  Completer<void>? pending;
  @override
  Future<void> resetDownloadState() async {
    resets++;
    await pending?.future;
    if (failure case final Object error) throw error;
  }
}
