import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../services/local_file_workspace.dart';
import '../services/startup_access_guard.dart';
import '../services/model_storage_preflight.dart';

typedef WorkspaceSelection = ({
  String name,
  int bytes,
  Stream<List<int>> source,
});

class FileWorkspaceScreen extends StatefulWidget {
  const FileWorkspaceScreen({super.key, this.workspace, this.pick});
  final InputWorkspaceStore? workspace;
  final Future<WorkspaceSelection?> Function()? pick;
  @override
  State<FileWorkspaceScreen> createState() => _FileWorkspaceScreenState();
}

class _FileWorkspaceScreenState extends State<FileWorkspaceScreen> {
  late final _workspace =
      widget.workspace ??
      LocalFileWorkspace(
        root: () async => Directory(
          '${(await getApplicationSupportDirectory()).path}/input_workspace',
        ),
        availableBytes: () async =>
            await queryAllocatableModelStorage() ??
            (throw const WorkspaceImportException('storage_unknown')),
      );
  List<WorkspaceFile>? _files;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final files = await _workspace.list();
      if (mounted)
        setState(() {
          _files = files;
          _error = null;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Files could not be read. Your originals have not been changed.',
        );
    }
  }

  void _admit() {
    final access = context.read<StartupAccessGuard?>();
    if (access == null)
      throw const WorkspaceImportException('startup_unavailable');
    access.require(StartupAccessOperation.recoverModels);
  }

  Future<WorkspaceSelection?> _pick() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
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
    try {
      _admit();
      final selection = await (widget.pick ?? _pick)();
      if (selection == null || !mounted) return;
      _admit();
      await _workspace.import(
        name: selection.name,
        expectedBytes: selection.bytes,
        source: selection.source,
      );
      await _refresh();
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error is WorkspaceImportException
              ? error.toString()
              : 'Import could not complete. Please retry.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview(WorkspaceFile item) async {
    setState(() => _busy = true);
    try {
      final text = await _workspace.withFile(item.id, (file) async {
        final bytes = await file
            .openRead(
              0,
              item.bytes < InputWorkspacePolicy.previewBytes
                  ? item.bytes
                  : InputWorkspacePolicy.previewBytes,
            )
            .fold<List<int>>([], (a, b) => a..addAll(b));
        return utf8.decode(bytes, allowMalformed: true);
      });
      if (!mounted) return;
      final textual = [
        'txt',
        'md',
        'csv',
        'json',
        'jsonl',
        'log',
      ].contains(item.name.split('.').last.toLowerCase());
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(item.name),
          content: SingleChildScrollView(
            child: SelectableText(
              textual
                  ? '${item.bytes > InputWorkspacePolicy.previewBytes ? 'Preview limited to the first ${InputWorkspacePolicy.previewBytes} bytes; original copy is unchanged.\n\n' : ''}$text'
                  : 'Stored locally: ${item.bytes} bytes.\nThis format needs a compatible task or decoder; importing it does not make a text model able to read it.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted)
        setState(
          () =>
              _error = 'Preview unavailable. The stored file was not modified.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(WorkspaceFile item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${item.name}?'),
        content: const Text(
          'Only the imported copy is removed. The original file is unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      _admit();
      await _workspace.remove(item.id);
      await _refresh();
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'The copy could not be removed. Retry when it is not in use.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Files and algorithms')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Import a local file for a compatible task. Files stay on this device. Custom algorithm execution is being added; stored files are not automatically sent to a chat model.',
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.upload_file),
            label: const Text('Import file'),
          ),
          if (_busy || (_files == null && _error == null))
            const LinearProgressIndicator(
              semanticsLabel: 'Copying or reading local files',
            ),
          if (_error != null) ...[
            Semantics(liveRegion: true, child: Text(_error!)),
            TextButton(
              onPressed: _busy ? null : _refresh,
              child: const Text('Retry'),
            ),
          ],
          if (_files?.isEmpty == true) const Text('No imported files yet'),
          for (final item in _files ?? <WorkspaceFile>[])
            ListTile(
              title: Text(item.name),
              subtitle: Text('${item.bytes} bytes • Stored locally'),
              onTap: _busy ? null : () => _preview(item),
              trailing: IconButton(
                tooltip: 'Remove imported file ${item.name}',
                onPressed: _busy ? null : () => _remove(item),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
        ],
      ),
    ),
  );
}
