import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../services/algorithm_package_store.dart';
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
    this.package,
    this.packages,
  });
  final InputWorkspaceStore workspace;
  final List<WorkspaceFile> files;
  final TaskRunner? runner;
  final AlgorithmPackage? package;
  final AlgorithmPackageStore? packages;
  @override
  State<CustomTaskScreen> createState() => _CustomTaskScreenState();
}

class _CustomTaskScreenState extends State<CustomTaskScreen>
    with WidgetsBindingObserver {
  WorkspaceFile? _task, _input;
  bool _busy = false, _stopping = false, _importing = false;
  late final _files = List<WorkspaceFile>.of(widget.files);
  String? _status;
  Map<Object?, Object?>? _result;
  late final TaskRunner _runner =
      widget.runner ??
      CustomTaskService(
        workspace: widget.workspace,
        packages: widget.packages ?? AlgorithmPackageStore.application(),
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
    if (_busy ||
        _importing ||
        (_task == null && widget.package == null) ||
        _input == null)
      return;
    setState(() {
      _busy = true;
      _stopping = false;
      _status = 'Preparing and running locally…';
      _result = null;
    });
    try {
      final output = widget.package == null
          ? await _runner.run(task: _task!, input: _input!)
          : await (_runner as PackageTaskRunner).runPackage(
              package: widget.package!,
              input: _input!,
            );
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

  Future<void> _chooseInput() async {
    if (_busy || _importing) return;
    setState(() => _importing = true);
    try {
      final guard = context.read<StartupAccessGuard?>();
      if (guard == null) throw StateError('Startup unavailable');
      guard.require(StartupAccessOperation.recoverModels);
      final selected = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: widget.package?.spec.kind == 'csv'
            ? ['csv']
            : ['png', 'jpg', 'jpeg'],
        withReadStream: true,
      );
      if (selected == null || !mounted) return;
      final picked = selected.files.single;
      final source =
          picked.readStream ??
          (picked.path == null ? null : File(picked.path!).openRead());
      if (source == null)
        throw const FormatException('The selected input could not be read.');
      guard.require(StartupAccessOperation.recoverModels);
      final file = await widget.workspace.import(
        name: picked.name,
        expectedBytes: picked.size,
        source: source,
      );
      if (mounted)
        setState(() {
          _files.add(file);
          _input = file;
          _result = null;
          _status = null;
        });
    } catch (_) {
      if (mounted)
        setState(
          () =>
              _status = 'Input could not be imported. Check storage and retry.',
        );
    } finally {
      if (mounted) setState(() => _importing = false);
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
    onChanged: _busy || _importing
        ? null
        : (item) => setState(() {
            if (item?.id != value?.id) {
              _result = null;
              _status = null;
            }
            changed(item);
          }),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !_importing,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.package?.spec.name ?? 'Run custom algorithm'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.package case final package?) ...[
            Text(package.description),
            Text(
              package.spec.kind == 'csv'
                  ? 'CSV: ${package.spec.shape[0]} data rows, ${package.spec.shape[1]} columns. Header: ${package.spec.csvHeader ? 'yes' : 'no'}.'
                  : 'Image: PNG/JPEG. Preprocessing is configured by this algorithm.',
            ),
            OutlinedButton.icon(
              onPressed: _busy || _importing ? null : _chooseInput,
              icon: const Icon(Icons.attach_file),
              label: const Text('Choose input file'),
            ),
          ] else ...[
            const Text(
              'Import the task JSON, its exact ONNX model, and a CSV or image in Files first. Runs locally on CPU. Use trusted compatible exports.',
            ),
            const SizedBox(height: 16),
            _select(
              'Task description',
              _task,
              (v) => _task = v,
              _files.where((f) => f.name.toLowerCase().endsWith('.json')),
            ),
          ],
          const SizedBox(height: 16),
          _select(
            'Input file',
            _input,
            (v) => _input = v,
            _files.where(
              (f) =>
                  widget.package == null ||
                  (widget.package!.spec.kind == 'csv'
                      ? f.name.toLowerCase().endsWith('.csv')
                      : [
                          'png',
                          'jpg',
                          'jpeg',
                        ].contains(f.name.split('.').last.toLowerCase())),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Image tasks: opaque PNG/JPEG, RGB, stored pixel orientation (no automatic EXIF rotation). Resize and normalization come from the task JSON. Outputs are raw tensors, not automatically probabilities or diagnoses.',
          ),
          FilledButton(
            onPressed:
                _busy ||
                    _importing ||
                    (_task == null && widget.package == null) ||
                    _input == null
                ? null
                : _run,
            child: const Text('Run algorithm'),
          ),
          if (_importing)
            const LinearProgressIndicator(
              semanticsLabel: 'Importing algorithm input',
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
