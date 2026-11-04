import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vitalis_app/models/custom_task_spec.dart';
import 'package:vitalis_app/models/startup_capabilities.dart';
import 'package:vitalis_app/services/algorithm_package_store.dart';
import 'package:vitalis_app/services/startup_access_guard.dart';
import 'package:vitalis_app/screens/algorithm_library_screen.dart';
import 'file_workspace_screen_test.dart' show MemoryWorkspace;

final class PackageWorkspace extends MemoryWorkspace {
  @override
  Future<T> withFile<T>(String id, Future<T> Function(File) action) =>
      action(File('not-read-by-screen-fake'));
}

final class PackageRepository extends AlgorithmPackageStore {
  PackageRepository(this.fixture)
    : super(
        root: () async => Directory('unused'),
        availableBytes: () async => 1000000,
      );
  final AlgorithmPackage fixture;
  final items = <AlgorithmPackage>[];
  @override
  Future<void> remove(String id) async =>
      items.removeWhere((item) => item.id == id);
  var imports = 0;
  bool fail = false;
  @override
  Future<List<AlgorithmPackage>> list() async => List.of(items);
  @override
  Future<AlgorithmPackage> install(
    File source, {
    required int maxModelBytes,
    required int maxInputElements,
  }) async {
    imports++;
    if (fail) throw const AlgorithmPackageError('Invalid package');
    items.add(fixture);
    return fixture;
  }
}

void main() {
  late PackageRepository repository;
  late PackageWorkspace workspace;
  setUp(() {
    final spec = CustomTaskSpec.parse({
      'schema_version': 1,
      'runtime': 'onnx',
      'name': 'Friendly algorithm',
      'model': {'file': 'model.onnx', 'sha256': 'a' * 64},
      'input': {
        'name': 'x',
        'kind': 'csv',
        'dtype': 'float32',
        'shape': [1, 2],
        'header': false,
      },
      'outputs': ['y'],
    }, maxInputElements: 100);
    repository = PackageRepository(
      AlgorithmPackage('b' * 32, spec, 'Adds two numbers', 'c' * 64),
    );
    workspace = PackageWorkspace();
  });
  Widget app(Future<AlgorithmPackageSelection?> Function() pick) =>
      Provider<StartupAccessGuard?>.value(
        value: StartupAccessGuard(
          () => const StartupCapabilities(
            databaseReady: true,
            migrationReady: true,
            safetyReady: true,
            modelReadiness: StartupModelReadiness.missing,
          ),
        ),
        child: MaterialApp(
          home: AlgorithmLibraryScreen(
            packages: repository,
            workspace: workspace,
            pick: pick,
            limits: () async => (modelBytes: 1000, inputElements: 100),
          ),
        ),
      );
  Future<AlgorithmPackageSelection?> pick() async =>
      (name: 'example.zip', bytes: 1, source: Stream.value([1]));
  testWidgets(
    'one import creates a named algorithm and removes only its temporary archive copy',
    (tester) async {
      await tester.pumpWidget(app(pick));
      await tester.pumpAndSettle();
      expect(find.text('No algorithms imported yet'), findsOneWidget);
      await tester.tap(find.text('Import algorithm package'));
      await tester.pumpAndSettle();
      expect(find.text('Friendly algorithm'), findsOneWidget);
      expect(find.textContaining('Adds two numbers'), findsOneWidget);
      expect(repository.imports, 1);
      expect(workspace.files, isEmpty);
    },
  );
  testWidgets('invalid package leaves existing algorithm and permits retry', (
    tester,
  ) async {
    repository.items.add(repository.fixture);
    repository.fail = true;
    await tester.pumpWidget(app(pick));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import algorithm package'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Invalid package'), findsOneWidget);
    expect(find.text('Friendly algorithm'), findsOneWidget);
    expect(workspace.files, isEmpty);
  });
  testWidgets('late picker completion after disposal never imports', (
    tester,
  ) async {
    final pending = Completer<AlgorithmPackageSelection?>();
    await tester.pumpWidget(app(() => pending.future));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import algorithm package'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(await pick());
    await tester.pumpAndSettle();
    expect(workspace.imports, 0);
    expect(repository.imports, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('removal requires confirmation and keeps input files', (
    tester,
  ) async {
    repository.items.add(repository.fixture);
    await workspace.import(
      name: 'input.csv',
      expectedBytes: 1,
      source: Stream.value([1]),
    );
    await tester.pumpWidget(app(pick));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove Friendly algorithm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(repository.items, hasLength(1));
    await tester.tap(find.byTooltip('Remove Friendly algorithm'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(repository.items, isEmpty);
    expect(workspace.files.single.name, 'input.csv');
  });
}
