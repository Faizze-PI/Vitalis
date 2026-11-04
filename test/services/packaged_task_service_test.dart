import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/algorithm_package_store.dart';
import 'package:vitalis_app/services/custom_task_service.dart';
import 'package:vitalis_app/services/local_file_workspace.dart';

void main() {
  late Directory root;
  late AlgorithmPackageStore packages;
  late LocalFileWorkspace workspace;
  late AlgorithmPackage package;
  late WorkspaceFile input;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('package-runner-');
    packages = AlgorithmPackageStore(
      root: () async => Directory('${root.path}/packages'),
      availableBytes: () async => 10000000,
    );
    workspace = LocalFileWorkspace(
      root: () async => Directory('${root.path}/inputs'),
      availableBytes: () async => 10000000,
    );
    final model = [1, 2, 3];
    final task = {
      'schema_version': 1,
      'runtime': 'onnx',
      'name': 'Sum',
      'model': {
        'file': 'model.onnx',
        'sha256': sha256.convert(model).toString(),
      },
      'input': {
        'name': 'features',
        'kind': 'csv',
        'dtype': 'float32',
        'shape': [1, 2],
        'header': false,
      },
      'outputs': ['prediction'],
    };
    final zip = File('${root.path}/algorithm.zip');
    await zip.writeAsBytes(
      ZipEncoder().encode(
        Archive()
          ..addFile(ArchiveFile.string('task.json', jsonEncode(task)))
          ..addFile(ArchiveFile('model.onnx', 3, model)),
      ),
    );
    package = await packages.install(
      zip,
      maxModelBytes: 100,
      maxInputElements: 100,
    );
    input = await workspace.import(
      name: 'data.csv',
      expectedBytes: 3,
      source: Stream.value(utf8.encode('1,2')),
    );
  });
  tearDown(() async => root.delete(recursive: true));
  test(
    'package model is selected without a loose model or JSON workspace copy',
    () async {
      Map<String, Object?>? submitted;
      final service = CustomTaskService(
        workspace: workspace,
        packages: packages,
        checkSafety: () {},
        exclusive: (action) => action(),
        invoke: (method, args) async {
          if (method == 'limits')
            return {'maxInputElements': 100, 'maxTextBytes': 1000};
          submitted = args;
          return {'requestId': args['requestId'], 'outputs': []};
        },
      );
      await service.runPackage(package: package, input: input);
      expect(submitted!['modelPackageId'], package.id);
      expect(submitted!.containsKey('modelId'), isFalse);
      expect(submitted!['values'], [1.0, 2.0]);
      expect(await workspace.list(), hasLength(1));
    },
  );
  test(
    'package lease survives cancellation until native terminal result',
    () async {
      final entered = Completer<void>(),
          terminal = Completer<Map<Object?, Object?>>();
      String? request;
      final service = CustomTaskService(
        workspace: workspace,
        packages: packages,
        checkSafety: () {},
        exclusive: (action) => action(),
        invoke: (method, args) async {
          if (method == 'limits')
            return {'maxInputElements': 100, 'maxTextBytes': 1000};
          if (method == 'cancel') return null;
          request = args['requestId'] as String;
          entered.complete();
          return terminal.future;
        },
      );
      final run = service.runPackage(package: package, input: input);
      final rejected = expectLater(
        run,
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      await entered.future;
      await service.cancel();
      expect(service.running, isTrue);
      await expectLater(
        packages.remove(package.id),
        throwsA(isA<AlgorithmPackageError>()),
      );
      terminal.complete({'requestId': request, 'outputs': []});
      await rejected;
      expect(service.running, isFalse);
      await packages.remove(package.id);
    },
  );
  test(
    'current device input budget is rechecked for a previously installed package',
    () async {
      var runs = 0;
      final service = CustomTaskService(
        workspace: workspace,
        packages: packages,
        checkSafety: () {},
        exclusive: (action) => action(),
        invoke: (method, args) async {
          if (method == 'limits')
            return {'maxInputElements': 1, 'maxTextBytes': 1000};
          runs++;
          return null;
        },
      );
      await expectLater(
        service.runPackage(package: package, input: input),
        throwsA(isA<FormatException>()),
      );
      expect(runs, 0);
    },
  );
}
