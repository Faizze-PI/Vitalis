import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import '../models/custom_task_spec.dart';
import 'hardware_sentinel_service.dart';
import 'local_file_workspace.dart';
import 'algorithm_package_store.dart';

typedef TaskInvoke =
    Future<Map<Object?, Object?>?> Function(
      String method,
      Map<String, Object?> args,
    );
typedef TaskExclusive =
    Future<Map<Object?, Object?>> Function(
      Future<Map<Object?, Object?>> Function() action,
    );

abstract interface class TaskRunner {
  bool get running;
  Future<Map<Object?, Object?>> run({
    required WorkspaceFile task,
    required WorkspaceFile input,
  });
  Future<void> cancel();
}

/// One local task, retaining file/runtime leases through native termination.
abstract interface class PackageTaskRunner implements TaskRunner {
  Future<Map<Object?, Object?>> runPackage({
    required AlgorithmPackage package,
    required WorkspaceFile input,
  });
}

final class CustomTaskService implements PackageTaskRunner {
  CustomTaskService({
    required this.workspace,
    this.packages,
    TaskInvoke? invoke,
    TaskExclusive? exclusive,
    this.prepare,
    void Function()? checkSafety,
    Stream<bool>? health,
  }) : _invoke = invoke ?? _platformInvoke,
       _exclusive = exclusive ?? LlamaCppChatRepository.withUnloadedRuntime,
       _checkSafety =
           checkSafety ?? HardwareSentinelService.instance.checkHeavyOperation,
       _health =
           health ??
           (checkSafety == null
               ? HardwareSentinelService.instance.onHealthChanged
               : null);
  static const _channel = MethodChannel('vitalis/custom_tasks'); // HC-078
  static Future<Map<Object?, Object?>?> _platformInvoke(
    String method,
    Map<String, Object?> args,
  ) async {
    final nativeArgs = <String, Object?>{...args};
    if (Platform.isWindows && method == 'run') {
      nativeArgs['appSupportPath'] =
          (await getApplicationSupportDirectory()).path;
    }
    return _channel.invokeMapMethod<Object?, Object?>(method, nativeArgs);
  }

  static Future<({int modelBytes, int inputElements})> deviceLimits() async {
    final values = await _platformInvoke('limits', {});
    final model = values?['maxModelBytes'], input = values?['maxInputElements'];
    if (model is! int || input is! int || model <= 0 || input <= 0)
      throw const FormatException('Device algorithm limits are unavailable.');
    return (modelBytes: model, inputElements: input);
  }

  final InputWorkspaceStore workspace;
  final AlgorithmPackageStore? packages;
  final TaskInvoke _invoke;
  final TaskExclusive _exclusive;
  final Future<void> Function()? prepare;
  final void Function() _checkSafety;
  final Stream<bool>? _health;
  String? _requestId;
  bool _cancelled = false, _submitted = false;
  String? cancellationFailure;
  Future<void>? _cancelFuture;
  bool get running => _requestId != null;
  void _check() {
    if (_cancelled)
      throw PlatformException(code: 'cancelled', message: 'Task cancelled.');
    _checkSafety();
  }

  Future<void> cancel() {
    _cancelled = true;
    final id = _requestId;
    if (id == null || !_submitted) return Future.value();
    return _cancelFuture ??= _invoke('cancel', {
      'requestId': id,
    }).then<void>((_) {});
  }

  Future<Map<Object?, Object?>> run({
    required WorkspaceFile task,
    required WorkspaceFile input,
  }) => _run(task: task, input: input);

  Future<Map<Object?, Object?>> runPackage({
    required AlgorithmPackage package,
    required WorkspaceFile input,
  }) => _run(package: package, input: input);

  Future<Map<Object?, Object?>> _run({
    WorkspaceFile? task,
    AlgorithmPackage? package,
    required WorkspaceFile input,
  }) async {
    if (running) throw PlatformException(code: 'runtimeBusy');
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join(); // HC-078
    _requestId = id;
    _cancelled = false;
    _submitted = false;
    _cancelFuture = null;
    cancellationFailure = null;
    final health = _health?.listen((safe) {
      if (!safe)
        unawaited(
          cancel().catchError((Object _) {
            cancellationFailure = 'cancellationUnconfirmed';
          }),
        );
    });
    try {
      _check();
      if (prepare != null) await prepare!();
      _check();
      return await _exclusive(() async {
        _check();
        final limits = await _invoke('limits', {});
        final elements = limits?['maxInputElements'],
            textBytes = limits?['maxTextBytes'];
        if (elements is! int ||
            elements <= 0 ||
            textBytes is! int ||
            textBytes <= 0)
          throw const FormatException('Device input budget unavailable.');
        late final CustomTaskSpec spec;
        if (package != null) {
          if (packages == null)
            throw const FormatException(
              'Algorithm package storage is unavailable.',
            );
          final installed = (await packages!.list()).where(
            (p) =>
                p.id == package.id && p.packageSha256 == package.packageSha256,
          );
          if (installed.length != 1)
            throw const FormatException(
              'Algorithm package is unavailable. Reopen the library.',
            );
          spec = installed.single.spec;
          if (spec.elementCount > elements)
            throw const FormatException(
              'Algorithm input exceeds the current device task budget.',
            );
        } else {
          spec = await workspace.withFile(task!.id, (file) async {
            final json = jsonDecode(
              await _read(file, InputWorkspacePolicy.metadataBytes),
            );
            if (json is! Map<String, dynamic>)
              throw const FormatException('Select a task JSON description.');
            return CustomTaskSpec.parse(json, maxInputElements: elements);
          });
        }
        Future<Map<Object?, Object?>> executeInput(
          Map<String, Object?> modelFields,
        ) => workspace.withFile(input.id, (file) async {
          final args = <String, Object?>{
            'requestId': id,
            ...modelFields,
            'modelSha256': spec.modelSha256,
            'inputId': input.id,
            'inputName': spec.inputName,
            'shape': spec.shape,
            'outputs': spec.outputNames,
            'kind': spec.kind,
            'image': spec.image,
          };
          if (spec.kind == 'csv')
            args['values'] = spec.csvValues(await _read(file, textBytes));
          _check();
          _submitted = true;
          final result = await _invoke('run', args);
          _check();
          if (result == null || result['requestId'] != id)
            throw PlatformException(code: 'invalidTaskResult');
          return result;
        });
        if (package != null) {
          return packages!.withModel(
            package.id,
            (_) => executeInput({'modelPackageId': package.id}),
          );
        }
        final models = (await workspace.list()).where(
          (file) => file.sha256 == spec.modelSha256,
        );
        if (models.isEmpty)
          throw const FormatException(
            'Import the exact ONNX model declared by this task first.',
          );
        final model = models.first;
        return workspace.withFile(
          model.id,
          (_) => executeInput({'modelId': model.id}),
        );
      });
    } finally {
      await health?.cancel();
      _requestId = null;
      _submitted = false;
    }
  }

  static Future<String> _read(File file, int limit) async {
    final bytes = <int>[];
    await for (final chunk in file.openRead()) {
      if (chunk.length > limit - bytes.length)
        throw const FormatException(
          'Input exceeds this task processing budget.',
        );
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }
}
