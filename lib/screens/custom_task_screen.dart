import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import '../providers/generation_provider.dart';
import '../services/model_warmup_service.dart';
import '../services/startup_access_guard.dart';
import '../services/custom_task_service.dart';
import '../services/local_file_workspace.dart';

class CustomTaskScreen extends StatefulWidget {
  const CustomTaskScreen({
    super.key,
    required this.workspace,
    required this.files,
    this.runner,
  });
  final InputWorkspaceStore workspace;
  final List<WorkspaceFile> files;
  final TaskRunner? runner;
  @override
  State<CustomTaskScreen> createState() => _CustomTaskScreenState();
}

class _CustomTaskScreenState extends State<CustomTaskScreen>
    with WidgetsBindingObserver {
  WorkspaceFile? _task, _input;
  bool _busy = false, _stopping = false;
  String? _status;
  Map<Object?, Object?>? _result;
  late final TaskRunner _runner =
      widget.runner ??
      CustomTaskService(
        workspace: widget.workspace,
        prepare: () async {
          final guard = context.read<StartupAccessGuard?>();
          if (guard == null) throw StateError('Startup unavailable');
          guard.require(StartupAccessOperation.recoverModels);
          if (!guard.snapshot().safetyReady)
            throw StateError('Safety initialization unavailable');
          if (context.read<GenerationProvider>().isSending)
            throw InferenceRuntimeBusy();
          await context.read<ModelWarmupService>().releaseForCustomTask();
        },
      );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _busy) unawaited(_stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_busy)
      unawaited(
        _runner.cancel().catchError((Object _) {
          /* Run retains ownership until its terminal event. */
        }),
      );
    super.dispose();
  }

  Future<void> _run() async {
    if (_busy || _task == null || _input == null) return;
    setState(() {
      _busy = true;
      _stopping = false;
      _status = 'Preparing and running locally…';
      _result = null;
    });
    try {
      final output = await _runner.run(task: _task!, input: _input!);
      if (mounted)
        setState(() {
          if (!_stopping) _result = output;
          _status = _stopping ? 'Task cancelled.' : 'Completed on this device.';
        });
    } catch (error) {
      if (mounted)
        setState(
          () => _status = switch (error) {
            FormatException e => e.message,
            PlatformException e when e.code == 'cancelled' => 'Task cancelled.',
            PlatformException e =>
              'Task failed (${e.code}). Check the model and task description.',
            InferenceRuntimeBusy() =>
              'Chat runtime is busy. Stop active work and retry.',
            _ =>
              'Task could not run (${error.runtimeType}). Existing files were not changed.',
          },
        );
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
          _stopping = false;
        });
    }
  }

  Future<void> _stop() async {
    if (!_busy || _stopping) return;
    if (mounted) setState(() => _stopping = true);
    try {
      await _runner.cancel();
    } catch (_) {
      if (mounted)
        setState(
          () => _status =
              'Stop acknowledgement pending. Waiting for native work to end.',
        );
    }
  }

  Widget _select(
    String label,
    WorkspaceFile? value,
    ValueChanged<WorkspaceFile?> changed,
    Iterable<WorkspaceFile> options,
  ) => DropdownButtonFormField<WorkspaceFile>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    isExpanded: true,
    items: [
      for (final file in options)
        DropdownMenuItem(
          value: file,
          child: Text(file.name, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: _busy ? null : (item) => setState(() => changed(item)),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Run custom algorithm')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Import the task JSON, its exact ONNX model, and a CSV or image in Files first. Runs locally on CPU. Use trusted compatible exports.',
          ),
          const SizedBox(height: 16),
          _select(
            'Task description',
            _task,
            (v) => _task = v,
            widget.files.where((f) => f.name.toLowerCase().endsWith('.json')),
          ),
          const SizedBox(height: 16),
          _select('Input file', _input, (v) => _input = v, widget.files),
          const SizedBox(height: 16),
          const Text(
            'Image tasks: opaque PNG/JPEG, RGB, stored pixel orientation (no automatic EXIF rotation). Resize and normalization come from the task JSON. Outputs are raw tensors, not automatically probabilities or diagnoses.',
          ),
          FilledButton(
            onPressed: _busy || _task == null || _input == null ? null : _run,
            child: const Text('Run algorithm'),
          ),
          if (_busy) ...[
            const LinearProgressIndicator(
              semanticsLabel: 'Running local algorithm',
            ),
            OutlinedButton(
              onPressed: _stopping ? null : _stop,
              child: Text(_stopping ? 'Stopping…' : 'Stop'),
            ),
          ],
          if (_status != null)
            Semantics(liveRegion: true, child: Text(_status!)),
          if (_result != null) ...[
            Text('${_result!['backend']} • Raw outputs'),
            for (final output in (_result!['outputs'] as List? ?? const []))
              SelectableText(
                '${output['name']}  shape ${output['shape']}\n${(output['values'] as List).take(64).toList()}${(output['values'] as List).length > 64 ? '\nPreview: first 64 values.' : ''}',
              ), // HC-078
          ],
        ],
      ),
    ),
  );
}
