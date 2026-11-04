import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/algorithm_package_store.dart';
import '../services/custom_task_service.dart';
import '../services/local_file_workspace.dart';
import '../services/startup_access_guard.dart';
import 'custom_task_screen.dart';

typedef AlgorithmPackageSelection = ({
  String name,
  int bytes,
  Stream<List<int>> source,
});

class AlgorithmLibraryScreen extends StatefulWidget {
  const AlgorithmLibraryScreen({
    super.key,
    this.packages,
    this.workspace,
    this.pick,
    this.limits,
  });
  final AlgorithmPackageStore? packages;
  final InputWorkspaceStore? workspace;
  final Future<AlgorithmPackageSelection?> Function()? pick;
  final Future<({int modelBytes, int inputElements})> Function()? limits;
  @override
  State<AlgorithmLibraryScreen> createState() => _AlgorithmLibraryScreenState();
}

class _AlgorithmLibraryScreenState extends State<AlgorithmLibraryScreen> {
  late final _packages = widget.packages ?? AlgorithmPackageStore.application();
  late final _workspace = widget.workspace ?? LocalFileWorkspace.application();
  List<AlgorithmPackage>? _items;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _admit() {
    final guard = context.read<StartupAccessGuard?>();
    if (guard == null)
      throw const WorkspaceImportException('startup_unavailable');
    guard.require(StartupAccessOperation.recoverModels);
  }

  Future<void> _refresh() async {
    try {
      final items = await _packages.list();
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Algorithms could not be read. Retry without removing existing files.',
        );
    }
  }

  Future<AlgorithmPackageSelection?> _pick() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withReadStream: true,
    );
    if (result == null) return null;
    final file = result.files.single;
    final source =
        file.readStream ??
        (file.path == null ? null : File(file.path!).openRead());
    if (source == null)
      throw const WorkspaceImportException('file_unavailable');
    return (name: file.name, bytes: file.size, source: source);
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    WorkspaceFile? temporary;
    try {
      _admit();
      final selection = await (widget.pick ?? _pick)();
      if (!mounted || selection == null) return;
      _admit();
      final limits = await (widget.limits ?? CustomTaskService.deviceLimits)();
      if (!mounted) return;
      _admit();
      temporary = await _workspace.import(
        name: selection.name,
        expectedBytes: selection.bytes,
        source: selection.source,
      );
      await _workspace.withFile(
        temporary.id,
        (file) => _packages.install(
          file,
          maxModelBytes: limits.modelBytes,
          maxInputElements: limits.inputElements,
        ),
      );
      await _refresh();
    } on AlgorithmPackageError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Package import failed. Existing algorithms and original files are unchanged.',
        );
    } finally {
      if (temporary != null) {
        try {
          await _workspace.remove(temporary.id);
        } catch (_) {
          if (mounted)
            setState(
              () => _error =
                  'Temporary package copy remains in Files. Check the algorithm list before retrying.',
            );
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(AlgorithmPackage item) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _admit();
      final files = await _workspace.list();
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CustomTaskScreen(
            package: item,
            packages: _packages,
            workspace: _workspace,
            files: files,
          ),
        ),
      );
      await _refresh();
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'This algorithm cannot be opened yet. Retry when startup and runtime recovery finish.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(AlgorithmPackage item) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${item.spec.name}?'),
        content: const Text(
          'Only this imported algorithm is removed. Input files and chats are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _admit();
      await _packages.remove(item.id);
      await _refresh();
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Algorithm could not be removed. It may still be running.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Algorithms')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Import a compatible ONNX algorithm package, choose a CSV or image, then run it on this device. Import checks the package and model hash; execution checks runtime compatibility.',
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.add),
            label: const Text('Import algorithm package'),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!, semanticsLabel: _error),
          if (!_busy && _error != null)
            TextButton(
              onPressed: () {
                setState(() => _error = null);
                _refresh();
              },
              child: const Text('Retry'),
            ),
          if (_items == null && _error == null)
            const Center(child: CircularProgressIndicator()),
          if (_items?.isEmpty ?? false)
            const Text('No algorithms imported yet'),
          for (final item in _items ?? <AlgorithmPackage>[])
            ListTile(
              title: Text(item.spec.name),
              subtitle: Text(item.description),
              enabled: !_busy,
              onTap: () => _open(item),
              trailing: IconButton(
                tooltip: 'Remove ${item.spec.name}',
                onPressed: _busy ? null : () => _remove(item),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
        ],
      ),
    ),
  );
}
