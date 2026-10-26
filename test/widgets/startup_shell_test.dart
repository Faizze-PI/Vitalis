import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/startup_coordinator.dart';
import 'package:vitalis_app/widgets/startup_shell.dart';

void main() {
  testWidgets(
    'renders a visible boot frame while database opening is pending',
    (tester) async {
      final pending = Completer<void>();
      final coordinator = StartupCoordinator(
        openDatabase: () => pending.future,
        loadLogger: () async {},
        migrateLegacyPreferences: () async {},
        initializeSafety: () async {},
        databaseTimeout: const Duration(days: 1),
      );
      addTearDown(coordinator.dispose);

      await tester.pumpWidget(
        StartupShell(
          coordinator: coordinator,
          readyBuilder: (_) => const MaterialApp(home: Text('Ready app')),
        ),
      );
      await tester.pump();

      expect(find.text('Preparing Vitalis'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Ready app'), findsNothing);
      pending.complete();
      await tester.pump();
    },
  );

  testWidgets('shows retry UI after non-destructive database failure', (
    tester,
  ) async {
    final coordinator = StartupCoordinator(
      openDatabase: () => Future<void>.error(StateError('unavailable')),
      loadLogger: () async {},
      migrateLegacyPreferences: () async {},
      initializeSafety: () async {},
    );
    addTearDown(coordinator.dispose);

    await tester.pumpWidget(
      StartupShell(
        coordinator: coordinator,
        readyBuilder: (_) => const MaterialApp(home: Text('Ready app')),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Vitalis needs attention'), findsOneWidget);
    expect(find.text('Retry startup'), findsOneWidget);
    expect(find.textContaining('No automatic reset'), findsOneWidget);
  });
}
