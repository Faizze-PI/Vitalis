import 'dart:isolate';
import '../models/csv_table.dart';
import 'attached_file_reader.dart';
import 'local_file_workspace.dart';

/// Explicit local computation. Results are IEEE-754 numbers, not financial decimals.
final class CsvColumnSummary {
  const CsvColumnSummary({
    required this.count,
    required this.sum,
    required this.minimum,
    required this.maximum,
    required this.columnName,
  });
  final int count;
  final double sum, minimum, maximum;
  final String? columnName;
  double get mean => sum / count;

  static CsvColumnSummary calculate(
    String source, {
    required int column,
    required bool header,
  }) {
    final rows = parseCsvTable(source);
    if (rows.isEmpty || column < 0 || column >= rows.first.length) {
      throw const FormatException('Choose an existing column, starting at 1.');
    }
    if (rows.any((row) => row.length != rows.first.length)) {
      throw const FormatException('CSV rows must have equal column counts.');
    }
    final data = rows.skip(header ? 1 : 0);
    var count = 0;
    double sum = 0, correction = 0;
    double? minimum, maximum;
    for (final row in data) {
      final value = double.tryParse(row[column].trim());
      if (value == null || !value.isFinite) {
        throw const FormatException(
          'Every selected cell must contain a finite number. Blank values and formulas are not evaluated.',
        );
      }
      // Neumaier compensation reduces loss when magnitudes differ.
      final next = sum + value;
      correction += sum.abs() >= value.abs()
          ? (sum - next) + value
          : (value - next) + sum;
      sum = next;
      if (!sum.isFinite || !correction.isFinite) {
        throw const FormatException(
          'Column total exceeds the supported numeric range.',
        );
      }
      minimum = minimum == null || value < minimum ? value : minimum;
      maximum = maximum == null || value > maximum ? value : maximum;
      count++;
    }
    if (count == 0)
      throw const FormatException(
        'CSV has no data rows. Check the header setting.',
      );
    final total = sum + correction;
    if (!total.isFinite)
      throw const FormatException(
        'Column total exceeds the supported numeric range.',
      );
    return CsvColumnSummary(
      count: count,
      sum: total,
      minimum: minimum!,
      maximum: maximum!,
      columnName: header ? rows.first[column] : null,
    );
  }
}

// Capture only text and options in the worker, never providers or open files.
Future<CsvColumnSummary> _calculate(String text, int column, bool header) =>
    Isolate.run(
      () => CsvColumnSummary.calculate(text, column: column, header: header),
    );

class CsvAnalysisService {
  CsvAnalysisService({required this.workspace});
  final InputWorkspaceStore workspace;
  Future<CsvColumnSummary> analyze(
    WorkspaceFile file, {
    required int column,
    required bool header,
  }) async {
    if (!file.name.toLowerCase().endsWith('.csv'))
      throw const FormatException('Choose a CSV file.');
    final content = await AttachedFileReader(workspace: workspace).read([file]);
    return _calculate(content.single.text, column, header);
  }
}
