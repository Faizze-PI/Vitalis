import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/custom_task_spec.dart';

Map<String, Object?> csvTask() => {
  'schema_version': 1,
  'runtime': 'onnx',
  'name': 'Linear demo',
  'model': {'file': 'linear.onnx', 'sha256': 'a' * 64},
  'input': {
    'name': 'features',
    'kind': 'csv',
    'dtype': 'float32',
    'shape': [3, 2],
    'header': true,
  },
  'outputs': ['prediction'],
};

void main() {
  test(
    'binds a compatible CSV task to its expected model hash and tensor shape',
    () {
      final spec = CustomTaskSpec.parse(csvTask(), maxInputElements: 100);
      expect(spec.inputName, 'features');
      expect(spec.shape, [3, 2]);
      expect(spec.elementCount, 6);
      expect(spec.modelSha256, 'a' * 64);
      expect(spec.csvHeader, isTrue);
      expect(spec.outputNames, ['prediction']);
    },
  );
  test('parses numeric CSV with headers quotes BOM and CRLF', () {
    final spec = CustomTaskSpec.parse(csvTask(), maxInputElements: 100);
    expect(
      spec.csvValues('\ufeff"first","second"\r\n"1",2\r\n-1,3\r\n0,0\r\n'),
      [1, 2, -1, 3, 0, 0],
    );
  });
  for (final data in [
    'first,second\n1,2\n',
    'first,second\nNaN,2\n-1,3\n0,0',
    'first,second\n"1,2\n-1,3\n0,0',
  ]) {
    test('rejects malformed or incompatible CSV ${data.length}', () {
      final spec = CustomTaskSpec.parse(csvTask(), maxInputElements: 100);
      expect(() => spec.csvValues(data), throwsFormatException);
    });
  }
  for (final runtime in ['python', 'executable', 'tflite']) {
    test('does not claim runtime support for $runtime', () {
      expect(
        () => CustomTaskSpec.parse({
          ...csvTask(),
          'runtime': runtime,
        }, maxInputElements: 100),
        throwsFormatException,
      );
    });
  }
  test('rejects tensor dimensions exceeding the supplied device budget', () {
    expect(
      () => CustomTaskSpec.parse(csvTask(), maxInputElements: 5),
      throwsFormatException,
    );
  });
  test('rejects model paths and unbound model hashes', () {
    for (final model in [
      {'file': '../a.onnx', 'sha256': 'a' * 64},
      {'file': 'a.onnx', 'sha256': ''},
    ]) {
      expect(
        () => CustomTaskSpec.parse({
          ...csvTask(),
          'model': model,
        }, maxInputElements: 100),
        throwsFormatException,
      );
    }
  });
  test('requires explicit image preprocessing instead of guessing', () {
    final task = {
      ...csvTask(),
      'input': {
        'name': 'image',
        'kind': 'image',
        'dtype': 'float32',
        'shape': [1, 3, 2, 2],
      },
    };
    expect(
      () => CustomTaskSpec.parse(task, maxInputElements: 100),
      throwsFormatException,
    );
    task['input'] = {
      'name': 'image',
      'kind': 'image',
      'dtype': 'float32',
      'shape': [1, 3, 2, 2],
      'layout': 'NCHW',
      'resize': 'stretch',
      'interpolation': 'nearest',
      'color_order': 'RGB',
      'orientation': 'stored',
      'scale': 1 / 255,
      'mean': [0, 0, 0],
      'std': [1, 1, 1],
    };
    final spec = CustomTaskSpec.parse(task, maxInputElements: 100);
    expect(spec.kind, 'image');
    expect(spec.elementCount, 12);
    final input = Map<String, Object?>.from(task['input']! as Map);
    input.remove('color_order');
    expect(
      () => CustomTaskSpec.parse({
        ...task,
        'input': input,
      }, maxInputElements: 100),
      throwsFormatException,
    );
  });
}
