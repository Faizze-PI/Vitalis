import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/screens/custom_task_screen.dart';
import 'package:vitalis_app/services/custom_task_service.dart';
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
}
