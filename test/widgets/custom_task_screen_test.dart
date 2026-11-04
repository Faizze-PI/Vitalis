import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/screens/custom_task_screen.dart';
import 'package:vitalis_app/services/custom_task_service.dart';
import 'package:vitalis_app/services/algorithm_package_store.dart';
import 'package:vitalis_app/models/custom_task_spec.dart';
import 'package:vitalis_app/services/local_file_workspace.dart';
import 'file_workspace_screen_test.dart' show MemoryWorkspace;

final class FakeTaskRunner implements TaskRunner {
  var terminal = Completer<Map<Object?, Object?>>();
  int cancellations = 0;
  @override
  bool running = false;
  @override
  Future<void> cancel() async {
    cancellations++;
  }

  @override
  Future<Map<Object?, Object?>> run({
    required WorkspaceFile task,
    required WorkspaceFile input,
  }) async {
    running = true;
    try {
      return await terminal.future;
    } finally {
      running = false;
    }
  }
}

final class FakePackageRunner extends FakeTaskRunner
    implements PackageTaskRunner {
  AlgorithmPackage? selected;
  @override
  Future<Map<Object?, Object?>> runPackage({
    required AlgorithmPackage package,
    required WorkspaceFile input,
  }) {
    selected = package;
    return run(task: input, input: input);
  }
}

void main() {
  testWidgets(
    'Stop waits for terminal acknowledgement and displays real outputs',
    (tester) async {
      final runner = FakeTaskRunner();
      const files = [
        WorkspaceFile(id: 'a', name: 'task.json', bytes: 1, sha256: 'a'),
        WorkspaceFile(id: 'b', name: 'data.csv', bytes: 1, sha256: 'b'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: CustomTaskScreen(
            workspace: MemoryWorkspace(),
            files: files,
            runner: runner,
          ),
        ),
      );
      await tester.tap(find.text('Task description'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('task.json').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Input file'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('data.csv').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run algorithm'));
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await tester.pump();
      expect(runner.cancellations, 1);
      expect(find.text('Stopping…'), findsOneWidget);
      runner.terminal.completeError(PlatformException(code: 'cancelled'));
      await tester.pumpAndSettle();
      expect(find.text('Task cancelled.'), findsOneWidget);
      runner.terminal = Completer<Map<Object?, Object?>>();
      await tester.tap(find.text('Run algorithm'));
      await tester.pump();
      runner.terminal.complete({
        'backend': 'ONNX CPU',
        'outputs': [
          {
            'name': 'prediction',
            'shape': [1, 1],
            'values': [3.0],
          },
        ],
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('prediction'), findsOneWidget);
      expect(find.textContaining('3.0'), findsOneWidget);
    },
  );
  testWidgets(
    'changing task or input clears output from the previous selection',
    (tester) async {
      final runner = FakeTaskRunner();
      const files = [
        WorkspaceFile(id: 'a', name: 'first.json', bytes: 1, sha256: 'a'),
        WorkspaceFile(id: 'b', name: 'second.json', bytes: 1, sha256: 'b'),
        WorkspaceFile(id: 'c', name: 'one.csv', bytes: 1, sha256: 'c'),
        WorkspaceFile(id: 'd', name: 'two.csv', bytes: 1, sha256: 'd'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: CustomTaskScreen(
            workspace: MemoryWorkspace(),
            files: files,
            runner: runner,
          ),
        ),
      );
      Future<void> choose(String current, String next) async {
        await tester.tap(find.text(current).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text(next).last);
        await tester.pumpAndSettle();
      }

      Future<void> complete() async {
        runner.terminal = Completer<Map<Object?, Object?>>();
        await tester.tap(find.text('Run algorithm'));
        await tester.pump();
        runner.terminal.complete({
          'backend': 'ONNX CPU',
          'outputs': [
            {
              'name': 'old_result',
              'shape': [1],
              'values': [42.0],
            },
          ],
        });
        await tester.pumpAndSettle();
        expect(find.textContaining('old_result'), findsOneWidget);
      }

      await choose('Task description', 'first.json');
      await choose('Input file', 'one.csv');
      await complete();
      await choose('first.json', 'second.json');
      expect(find.textContaining('old_result'), findsNothing);
      expect(find.text('Completed on this device.'), findsNothing);
      await complete();
      await choose('one.csv', 'two.csv');
      expect(find.textContaining('old_result'), findsNothing);
      expect(find.text('Completed on this device.'), findsNothing);
    },
  );
  testWidgets(
    'package flow shows human name and input contract without a JSON selector',
    (tester) async {
      final spec = CustomTaskSpec.parse({
        'schema_version': 1,
        'runtime': 'onnx',
        'name': 'Row sum',
        'model': {'file': 'sum.onnx', 'sha256': 'a' * 64},
        'input': {
          'name': 'features',
          'kind': 'csv',
          'dtype': 'float32',
          'shape': [1, 2],
          'header': true,
        },
        'outputs': ['prediction'],
      }, maxInputElements: 100);
      final package = AlgorithmPackage(
        'b' * 32,
        spec,
        'Adds two columns',
        'c' * 64,
      );
      final runner = FakePackageRunner();
      await tester.pumpWidget(
        MaterialApp(
          home: CustomTaskScreen(
            workspace: MemoryWorkspace(),
            files: const [
              WorkspaceFile(
                id: 'input',
                name: 'data.csv',
                bytes: 1,
                sha256: 'd',
              ),
            ],
            package: package,
            runner: runner,
          ),
        ),
      );
      expect(find.text('Row sum'), findsWidgets);
      expect(find.text('Task description'), findsNothing);
      expect(find.textContaining('2 columns'), findsOneWidget);
      await tester.tap(find.text('Input file'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('data.csv').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run algorithm'));
      await tester.pump();
      expect(runner.selected, package);
      runner.terminal.complete({'backend': 'ONNX CPU', 'outputs': []});
      await tester.pumpAndSettle();
    },
  );
}
