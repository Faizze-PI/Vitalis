import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/services/startup_access_guard.dart';
import 'package:vitalis_app/services/local_file_workspace.dart';
import 'package:vitalis_app/screens/file_workspace_screen.dart';

Widget app(
  InputWorkspaceStore store,
  Future<WorkspaceSelection?> Function() pick,
) {
  final guard = StartupAccessGuard(
    () => const StartupCapabilities(
      databaseReady: true,
      migrationReady: true,
      safetyReady: true,
      modelReadiness: StartupModelReadiness.missing,
    ),
  );
  return Provider<StartupAccessGuard?>.value(
    value: guard,
    child: MaterialApp(
      home: FileWorkspaceScreen(workspace: store, pick: pick),
    ),
  );
}

void main() {
  testWidgets('imports a picker file and restores it after reopening', (
    tester,
  ) async {
    final store = MemoryWorkspace();
    Future<WorkspaceSelection?> pick() async => (
      name: 'sample.csv',
      bytes: 4,
      source: Stream<List<int>>.value([49, 44, 50, 10]),
    );
    await tester.pumpWidget(app(store, pick));
    await tester.pumpAndSettle();
    expect(find.text('No imported files yet'), findsOneWidget);
    await tester.tap(find.text('Import file'));
    await tester.pumpAndSettle();
    expect(find.text('sample.csv'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(store, pick));
    await tester.pumpAndSettle();
    expect(find.text('sample.csv'), findsOneWidget);
  });
  testWidgets('picker cancellation leaves files unchanged', (tester) async {
    final store = MemoryWorkspace();
    await tester.pumpWidget(app(store, () async => null));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import file'));
    await tester.pumpAndSettle();
    expect(store.imports, 0);
    expect(find.text('No imported files yet'), findsOneWidget);
  });
  testWidgets('disposal rejects a late picker result', (tester) async {
    final store = MemoryWorkspace();
    final selected = Completer<WorkspaceSelection?>();
    await tester.pumpWidget(app(store, () => selected.future));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import file'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    selected.complete((
      name: 'late.csv',
      bytes: 1,
      source: Stream<List<int>>.value([1]),
    ));
    await tester.pumpAndSettle();
    expect(store.imports, 0);
    expect(tester.takeException(), isNull);
  });
}

class MemoryWorkspace implements InputWorkspaceStore {
  final files = <WorkspaceFile>[];
  int imports = 0;
  @override
  Future<List<WorkspaceFile>> list() async => List.of(files);
  @override
  Future<WorkspaceFile> import({
    required String name,
    required int expectedBytes,
    required Stream<List<int>> source,
  }) async {
    await source.drain<void>();
    imports++;
    final file = WorkspaceFile(
      id: 'a' * 32,
      name: name,
      bytes: expectedBytes,
      sha256: 'b' * 64,
    );
    files.add(file);
    return file;
  }

  @override
  Future<void> remove(String id) async {
    files.removeWhere((file) => file.id == id);
  }

  @override
  Future<T> withFile<T>(String id, Future<T> Function(File) action) =>
      Future.error(StateError('No preview requested'));
}
