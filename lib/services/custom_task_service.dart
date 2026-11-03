import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import '../models/custom_task_spec.dart';
import 'hardware_sentinel_service.dart';
import 'local_file_workspace.dart';

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
final class CustomTaskService implements TaskRunner {
  CustomTaskService({
    required this.workspace,
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
  ) => _channel.invokeMapMethod<Object?, Object?>(method, args);
  final InputWorkspaceStore workspace;
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
        final spec = await workspace.withFile(task.id, (file) async {
          final json = jsonDecode(
            await _read(file, InputWorkspacePolicy.metadataBytes),
          );
          if (json is! Map<String, dynamic>)
            throw const FormatException('Select a task JSON description.');
          return CustomTaskSpec.parse(json, maxInputElements: elements);
        });
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
          (_) => workspace.withFile(input.id, (file) async {
            final args = <String, Object?>{
              'requestId': id,
              'modelId': model.id,
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
          }),
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
