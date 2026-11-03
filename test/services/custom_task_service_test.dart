import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/local_file_workspace.dart';
import 'package:vitalis_app/services/custom_task_service.dart';

void main() {
  late Directory root;
  late LocalFileWorkspace store;
  late WorkspaceFile model, task, input;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vitalis-task-');
    store = LocalFileWorkspace(
      root: () async => root,
      availableBytes: () async => 10000000,
    );
    Future<WorkspaceFile> add(String name, List<int> bytes) => store.import(
      name: name,
      expectedBytes: bytes.length,
      source: Stream.value(bytes),
    );
    model = await add('linear.onnx', [1, 2, 3]);
    task = await add(
      'task.json',
      utf8.encode(
        jsonEncode({
          'schema_version': 1,
          'runtime': 'onnx',
          'name': 'Sum',
          'model': {'file': 'linear.onnx', 'sha256': model.sha256},
          'input': {
            'name': 'features',
            'kind': 'csv',
            'dtype': 'float32',
            'shape': [1, 2],
            'header': true,
          },
          'outputs': ['prediction'],
        }),
      ),
    );
    input = await add('data.csv', utf8.encode('a,b\n1,2\n'));
  });
  tearDown(() async => root.delete(recursive: true));
  test(
    'binds model by hash and holds model/input leases until terminal result',
    () async {
      final terminal = Completer<Map<Object?, Object?>>();
      final submitted = Completer<void>();
      String? requestId;
      final service = CustomTaskService(
        workspace: store,
        checkSafety: () {},
        exclusive: (action) => action(),
        invoke: (method, args) async {
          if (method == 'limits')
            return {'maxInputElements': 100, 'maxTextBytes': 10000};
          expect(args['modelId'], model.id);
          expect(args['values'], [1, 2]);
          requestId = args['requestId']! as String;
          submitted.complete();
          return terminal.future;
        },
      );
      final run = service.run(task: task, input: input);
      await submitted.future;
      await expectLater(
        store.remove(model.id),
        throwsA(isA<WorkspaceImportException>()),
      );
      terminal.complete({'requestId': requestId, 'outputs': []});
      await run;
      await store.remove(model.id);
    },
  );
  test('cancel before preparation ends never submits native Run', () async {
    final prepared = Completer<void>();
    var runs = 0;
    final service = CustomTaskService(
      workspace: store,
      checkSafety: () {},
      exclusive: (action) => action(),
      prepare: () => prepared.future,
      invoke: (method, args) async {
        if (method == 'run') runs++;
        return {'maxInputElements': 100, 'maxTextBytes': 10000};
      },
    );
    final run = service.run(task: task, input: input);
    final expectation = expectLater(
      run,
      throwsA(
        isA<PlatformException>().having((e) => e.code, 'code', 'cancelled'),
      ),
    );
    await service.cancel();
    prepared.complete();
    await expectation;
    expect(runs, 0);
  });
  test(
    'shared cancellation retains leases and rejects a late successful result',
    () async {
      final submitted = Completer<void>();
      final terminal = Completer<Map<Object?, Object?>>();
      var cancellations = 0;
      String? id;
      final service = CustomTaskService(
        workspace: store,
        checkSafety: () {},
        exclusive: (action) => action(),
        invoke: (method, args) async {
          if (method == 'limits')
            return {'maxInputElements': 100, 'maxTextBytes': 10000};
          if (method == 'cancel') {
            cancellations++;
            return null;
          }
          id = args['requestId']! as String;
          submitted.complete();
          return terminal.future;
        },
      );
      final run = service.run(task: task, input: input);
      final rejected = expectLater(
        run,
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'cancelled'),
        ),
      );
      await submitted.future;
      await Future.wait([service.cancel(), service.cancel()]);
      expect(cancellations, 1);
      expect(service.running, isTrue);
      await expectLater(
        store.remove(input.id),
        throwsA(isA<WorkspaceImportException>()),
      );
      terminal.complete({'requestId': id, 'outputs': []});
      await rejected;
      expect(service.running, isFalse);
    },
  );

  test('missing exact model does not choose another import', () async {
    await store.remove(model.id);
    final service = CustomTaskService(
      workspace: store,
      checkSafety: () {},
      exclusive: (action) => action(),
      invoke: (method, args) async => {
        'maxInputElements': 100,
        'maxTextBytes': 10000,
      },
    );
    await expectLater(
      service.run(task: task, input: input),
      throwsA(isA<FormatException>()),
    );
  });
}
