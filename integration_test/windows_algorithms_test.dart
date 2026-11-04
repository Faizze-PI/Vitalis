import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vitalis_app/services/algorithm_package_store.dart';
import 'package:vitalis_app/services/custom_task_service.dart';
import 'package:vitalis_app/services/local_file_workspace.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Windows native channel executes packaged CSV and RGB image tasks',
    (tester) async {
      expect(Platform.isWindows, isTrue);
      const path = String.fromEnvironment('VITALIS_TASK_FIXTURES');
      expect(
        path,
        isNotEmpty,
        reason: 'A generated reference fixture directory is required.',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Algorithm integration test')),
        ),
      );
      final packages = AlgorithmPackageStore.application();
      final workspace = LocalFileWorkspace.application();
      final runner = CustomTaskService(
        workspace: workspace,
        packages: packages,
        checkSafety: () {},
        exclusive: (action) => action(),
      );
      final limits = await CustomTaskService.deviceLimits();
      for (final name in ['csv_sum', 'image_mean_rgb']) {
        final task = File('$path/$name.task.json');
        final bytes = await File('$path/$name.onnx').readAsBytes();
        final source = await Directory.systemTemp.createTemp(
          'vitalis-native-fixture-',
        );
        AlgorithmPackage? installed;
        WorkspaceFile? input;
        try {
          final zip = File('${source.path}/fixture.zip');
          await zip.writeAsBytes(
            ZipEncoder().encode(
              Archive()
                ..addFile(
                  ArchiveFile.string('task.json', await task.readAsString()),
                )
                ..addFile(ArchiveFile('$name.onnx', bytes.length, bytes)),
            ),
          );
          installed = await packages.install(
            zip,
            maxModelBytes: limits.modelBytes,
            maxInputElements: limits.inputElements,
          );
          final file = File(
            '$path/${name == 'csv_sum' ? 'input.csv' : 'input.png'}',
          );
          input = await workspace.import(
            name: file.uri.pathSegments.last,
            expectedBytes: await file.length(),
            source: file.openRead(),
          );
          final result = await runner.runPackage(
            package: installed,
            input: input,
          );
          final rows = result['outputs'] as List;
          final values = (rows.single as Map)['values'] as List;
          expect(values, name == 'csv_sum' ? [3.0, 2.0, 0.0] : [.5, .25, .25]);
          expect(result['backend'], 'ONNX CPU');
        } finally {
          if (input != null) await workspace.remove(input.id);
          if (installed != null) await packages.remove(installed.id);
          await source.delete(recursive: true);
        }
      }
    },
  );
}
