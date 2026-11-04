import 'package:flutter/material.dart';
import '../services/csv_analysis_service.dart';
import '../services/attached_file_reader.dart';
import '../services/local_file_workspace.dart';

class CsvAnalysisScreen extends StatefulWidget {
  const CsvAnalysisScreen({
    super.key,
    required this.workspace,
    required this.files,
    this.service,
  });
  final InputWorkspaceStore workspace;
  final List<WorkspaceFile> files;
  final CsvAnalysisService? service;
  @override
  State<CsvAnalysisScreen> createState() => _CsvAnalysisScreenState();
}

class _CsvAnalysisScreenState extends State<CsvAnalysisScreen> {
  final _column = TextEditingController(
    text: '1',
  ); // HC-080: UI uses one-based column selection.
  late final _files = widget.files
      .where((f) => f.name.toLowerCase().endsWith('.csv'))
      .toList(growable: false);
  WorkspaceFile? _file;
  bool _header = true,
      _running = false; // HC-080: visible user override, never inferred.
  CsvColumnSummary? _result;
  String? _error;
  @override
  void initState() {
    super.initState();
    _file = _files.firstOrNull;
  }

  @override
  void dispose() {
    _column.dispose();
    super.dispose();
  }

  void _clear() {
    _result = null;
    _error = null;
  }

  Future<void> _run() async {
    if (_running || _file == null) return;
    final column = int.tryParse(_column.text.trim());
    if (column == null || column < 1) {
      setState(() {
        _clear();
        _error = 'Enter a column number starting at 1.';
      });
      return;
    }
    setState(() {
      _clear();
      _running = true;
    });
    try {
      final result =
          await (widget.service ??
                  CsvAnalysisService(workspace: widget.workspace))
              .analyze(_file!, column: column - 1, header: _header);
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted)
        setState(
          () => _error = switch (error) {
            FormatException e => e.message,
            FileAttachmentReadError e => e.message,
            _ => 'File analysis could not complete. Reopen the file and retry.',
          },
        );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_running,
    child: Scaffold(
      appBar: AppBar(title: const Text('Analyze CSV')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Local column statistics. No model or network is used. Choose the column and header setting explicitly; formulas and blank numeric cells are rejected.',
          ),
          if (_files.isEmpty)
            const Text('Import a CSV in Files and algorithms first.')
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _file?.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'CSV file'),
              items: [
                for (final f in _files)
                  DropdownMenuItem(
                    value: f.id,
                    child: Text(f.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _running
                  ? null
                  : (id) => setState(() {
                      _file = _files.firstWhere((f) => f.id == id);
                      _clear();
                    }),
            ),
            TextField(
              controller: _column,
              enabled: !_running,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Column number (starts at 1)',
              ),
              onChanged: (_) => setState(_clear),
            ),
            SwitchListTile(
              title: const Text('First row is a header'),
              value: _header,
              onChanged: _running
                  ? null
                  : (value) => setState(() {
                      _header = value;
                      _clear();
                    }),
            ),
            FilledButton(
              onPressed: _running ? null : _run,
              child: const Text('Calculate column'),
            ),
          ],
          if (_running)
            const LinearProgressIndicator(
              semanticsLabel: 'Calculating CSV column',
            ),
          if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
          if (_result case final r?) ...[
            Semantics(
              liveRegion: true,
              child: SelectableText(
                'Column: ${r.columnName ?? _column.text}\nRows: ${r.count}\nSum: ${r.sum}\nMinimum: ${r.minimum}\nMaximum: ${r.maximum}\nMean: ${r.mean}',
              ),
            ),
            const Text(
              'Computed from all data rows in the selected file. Floating-point rounding applies; this is not an exact decimal or financial calculator.',
            ),
          ],
        ],
      ),
    ),
  );
}
