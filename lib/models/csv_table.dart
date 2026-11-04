/// Comma-separated UTF-8 text with explicit quoting; no formula execution.
List<List<String>> parseCsvTable(String source, {int? maxRows}) {
  final rows = <List<String>>[];
  var row = <String>[];
  var cell = StringBuffer();
  var quoted = false;
  var closed = false;
  void field() {
    row.add(cell.toString());
    cell = StringBuffer();
    closed = false;
  }

  void line() {
    field();
    rows.add(row);
    row = [];
    if (maxRows != null && rows.length > maxRows)
      throw const FormatException('CSV has more rows than permitted.');
  }

  final text = source.startsWith('\ufeff') ? source.substring(1) : source;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        cell.write(ch);
      }
    } else if (ch == ',') {
      field();
    } else if (ch == '\r' || ch == '\n') {
      line();
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
    } else if (closed) {
      if (ch.trim().isNotEmpty)
        throw const FormatException('Invalid text after a quoted CSV value.');
    } else if (ch == '"') {
      if (cell.isNotEmpty)
        throw const FormatException('Invalid CSV quotation.');
      quoted = true;
    } else {
      cell.write(ch);
    }
  }
  if (quoted) throw const FormatException('Unclosed CSV quotation.');
  if (cell.isNotEmpty || row.isNotEmpty || closed) line();
  return rows;
}
