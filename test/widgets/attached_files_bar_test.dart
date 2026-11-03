import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/widgets/attached_files_bar.dart';
import 'package:vitalis_app/models/workspace_file.dart';

void main() {
  testWidgets(
    'labels unsupported files and disables removal during generation',
    (tester) async {
      var removals = 0;
      const files = [
        WorkspaceFile(id: 'a', name: 'fact.txt', bytes: 4, sha256: 'a'),
        WorkspaceFile(id: 'b', name: 'scan.png', bytes: 4, sha256: 'b'),
      ];
      Widget app(bool enabled) => MaterialApp(
        home: Scaffold(
          body: AttachedFilesBar(
            files: files,
            enabled: enabled,
            onRemove: (_) async => removals++,
          ),
        ),
      );
      await tester.pumpWidget(app(false));
      expect(find.text('File: fact.txt'), findsOneWidget);
      expect(find.text('Needs decoder: scan.png'), findsOneWidget);
      expect(
        tester.widget<InputChip>(find.byType(InputChip).first).onDeleted,
        isNull,
      );
      await tester.pumpWidget(app(true));
      tester.widget<InputChip>(find.byType(InputChip).first).onDeleted!();
      await tester.pump();
      expect(removals, 1);
    },
  );
}
