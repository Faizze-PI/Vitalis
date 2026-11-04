import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/screens/csv_analysis_screen.dart';
import 'package:vitalis_app/services/csv_analysis_service.dart';
import 'package:vitalis_app/services/local_file_workspace.dart';

final class ScreenCalculator extends CsvAnalysisService {
  ScreenCalculator(InputWorkspaceStore workspace) : super(workspace: workspace);
  Completer<CsvColumnSummary>? pending;
  @override
  Future<CsvColumnSummary> analyze(
    WorkspaceFile file, {
    required int column,
    required bool header,
  }) async {
    if (pending != null) return pending!.future;
    return CsvColumnSummary.calculate(
      'first,second\n1,2\n-1,3\n0,0',
      column: column,
      header: header,
    );
  }
}

void main() {
  late LocalFileWorkspace store;
  const file = WorkspaceFile(
    id: 'fixture',
    name: 'input.csv',
    bytes: 30,
    sha256: 'fixture',
  );
  setUp(() {
    store = LocalFileWorkspace(
      root: () => throw StateError('Screen fake must not access files'),
      availableBytes: () async => 10000000,
    );
  });
  testWidgets('explicit column produces summary and retryable error', (
    tester,
  ) async {
    final service = ScreenCalculator(store);
    await tester.pumpWidget(
      MaterialApp(
        home: CsvAnalysisScreen(
          workspace: store,
          files: const [file],
          service: service,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text('Calculate column'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sum: 5.0'), findsOneWidget);
    expect(find.textContaining('Rows: 3'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '9');
    await tester.tap(find.text('Calculate column'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Choose an existing column'), findsOneWidget);
    expect(find.textContaining('Sum: 5.0'), findsNothing);
    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text('Calculate column'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sum: 5.0'), findsOneWidget);
  });
  testWidgets('empty state does not offer execution', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CsvAnalysisScreen(workspace: store, files: const []),
      ),
    );
    expect(find.textContaining('Import a CSV'), findsOneWidget);
    expect(find.text('Calculate column'), findsNothing);
  });
  testWidgets(
    'busy disables controls and disposal rejects late notifications',
    (tester) async {
      final service = ScreenCalculator(store)
        ..pending = Completer<CsvColumnSummary>();
      await tester.pumpWidget(
        MaterialApp(
          home: CsvAnalysisScreen(
            workspace: store,
            files: const [file],
            service: service,
          ),
        ),
      );
      await tester.tap(find.text('Calculate column'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      service.pending!.complete(
        CsvColumnSummary.calculate('1', column: 0, header: false),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
