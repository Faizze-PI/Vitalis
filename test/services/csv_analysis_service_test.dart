import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/services/csv_analysis_service.dart';
import 'package:vitalis_app/services/local_file_workspace.dart';

void main() {
  test('second-column fixture yields five instead of the model answer six', () {
    final r = CsvColumnSummary.calculate(
      'first,second\r\n1,2\r\n-1,3\r\n0,0\r\n',
      column: 1,
      header: true,
    );
    expect(r.count, 3);
    expect(r.sum, 5);
    expect(r.minimum, 0);
    expect(r.maximum, 3);
    expect(r.mean, closeTo(5 / 3, 1e-15));
    expect(r.columnName, 'second');
  });
  test(
    'supports BOM, quoted commas, escaped quotes, embedded newlines and no header',
    () {
      final r = CsvColumnSummary.calculate(
        '\ufeff"a,b",2\n"c\nq",3\n"a""b",0',
        column: 1,
        header: false,
      );
      expect(r.sum, 5);
      expect(r.count, 3);
    },
  );
  for (final input in [
    'a,b\n1',
    'a,b\n1,',
    'a,b\n1,NaN',
    'a,b\n1,Infinity',
    'a,b\n1,text',
    'a,b',
    'a,b\n1,1e308\n2,1e308',
    'a,b\n1,"2',
    'a,b\n1,"2"junk',
  ]) {
    test('rejects invalid or non-numeric input: $input', () {
      expect(
        () => CsvColumnSummary.calculate(input, column: 1, header: true),
        throwsFormatException,
      );
    });
  }
  test('requires a real selected column and does not guess header state', () {
    expect(
      () => CsvColumnSummary.calculate('1,2', column: -1, header: false),
      throwsFormatException,
    );
    expect(
      () => CsvColumnSummary.calculate('1,2', column: 2, header: false),
      throwsFormatException,
    );
    expect(
      () => CsvColumnSummary.calculate('a,b\n1,2', column: 1, header: false),
      throwsFormatException,
    );
  });
  test(
    'compensated sum preserves a small value between opposite large values',
    () {
      final r = CsvColumnSummary.calculate(
        '10000000000000000\n1\n-10000000000000000',
        column: 0,
        header: false,
      );
      expect(r.sum, 1);
    },
  );
  test('file service verifies bytes and never mutates the input', () async {
    final root = await Directory.systemTemp.createTemp('csv-analysis-');
    try {
      final store = LocalFileWorkspace(
        root: () async => root,
        availableBytes: () async => 10000000,
      );
      final bytes = utf8.encode('a,b\n1,2\n3,3');
      final file = await store.import(
        name: 'data.csv',
        expectedBytes: bytes.length,
        source: Stream.value(bytes),
      );
      final result = await CsvAnalysisService(
        workspace: store,
      ).analyze(file, column: 1, header: true);
      expect(result.sum, 5);
      expect((await store.list()).single.sha256, file.sha256);
      await store.withFile(file.id, (f) => f.writeAsString('a,b\n1,9\n3,3'));
      await expectLater(
        CsvAnalysisService(
          workspace: store,
        ).analyze(file, column: 1, header: true),
        throwsA(isA<Exception>()),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}
