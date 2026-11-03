import 'dart:typed_data';

/// Input preparation is declared by the exported task, never guessed from a name.
final class CustomTaskSpec {
  CustomTaskSpec._(
    this.name,
    this.modelFile,
    this.modelSha256,
    this.inputName,
    this.kind,
    this.shape,
    this.outputNames,
    this.csvHeader,
    this.image,
  );
  final String name, modelFile, modelSha256, inputName, kind;
  final List<int> shape;
  final List<String> outputNames;
  final bool csvHeader;
  final Map<String, Object?>? image;
  int get elementCount => shape.fold(1, (a, b) => a * b);

  static CustomTaskSpec parse(
    Map<String, dynamic> json, {
    required int maxInputElements,
  }) {
    Never invalid(String message) => throw FormatException(message);
    if (json['schema_version'] != 1 || json['runtime'] != 'onnx')
      invalid('Only version-1 ONNX tasks are supported.'); // hardcode: HC-078
    final model = json['model'];
    final input = json['input'];
    if (model is! Map || input is! Map)
      invalid('Task model and input descriptions are required.');
    String text(dynamic value) {
      if (value is! String || value.trim().isEmpty)
        invalid('A required task field is missing.');
      return value;
    }

    final filename = text(model['file']);
    if (!filename.toLowerCase().endsWith('.onnx') ||
        filename.contains('/') ||
        filename.contains('\\') ||
        filename.contains('..'))
      invalid('Select a single ONNX model filename, not a path.');
    final hash = text(model['sha256']).toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash))
      invalid('The task must declare its model SHA-256.');
    if (input['dtype'] != 'float32')
      invalid(
        'This task requires an unsupported input type. Export float32 inputs.',
      );
    final rawShape = input['shape'];
    if (rawShape is! List || rawShape.isEmpty || maxInputElements <= 0)
      invalid('A concrete input shape and memory budget are required.');
    var count = 1;
    final shape = <int>[];
    for (final dimension in rawShape) {
      if (dimension is! int ||
          dimension <= 0 ||
          dimension > maxInputElements ~/ count)
        invalid('Input shape exceeds the device budget or is not concrete.');
      count *= dimension;
      shape.add(dimension);
    }
    final kind = text(input['kind']);
    Map<String, Object?>? image;
    if (kind == 'csv') {
      if (shape.length != 2 || input['header'] is! bool)
        invalid(
          'CSV tasks require a row/column shape and an explicit header setting.',
        ); // hardcode: HC-078
    } else if (kind == 'image') {
      final layout = input['layout'];
      final scale = input['scale'];
      if (shape.length != 4 ||
          shape.first != 1 ||
          !['NCHW', 'NHWC'].contains(layout) ||
          input['resize'] != 'stretch' ||
          scale is! num ||
          !scale.isFinite ||
          scale <= 0)
        invalid(
          'Image tasks must declare layout, stretch resize and a finite scale.',
        ); // hardcode: HC-078
      final channels = shape[layout == 'NCHW' ? 1 : 3];
      if (channels != 3)
        invalid(
          'The first image adapter supports three-channel RGB inputs.',
        ); // hardcode: HC-078
      List<double> normalization(dynamic value, {required bool positive}) {
        if (value is! List || value.length != channels)
          invalid(
            'Declare mean and standard deviation for each image channel.',
          );
        return value.map((dynamic v) {
          if (v is! num || !v.isFinite || (positive && v <= 0))
            invalid('Image normalization is invalid.');
          return v.toDouble();
        }).toList();
      }

      image = {
        'layout': layout,
        'resize': 'stretch',
        'scale': scale.toDouble(),
        'mean': normalization(input['mean'], positive: false),
        'std': normalization(input['std'], positive: true),
      };
    } else {
      invalid('Only numeric CSV and image task inputs are supported.');
    }
    final outputs = json['outputs'];
    if (outputs is! List || outputs.isEmpty)
      invalid('Declare at least one named output.');
    final names = outputs.map(text).toList();
    if (names.toSet().length != names.length)
      invalid('Output names must be unique.');
    return CustomTaskSpec._(
      text(json['name']),
      filename,
      hash,
      text(input['name']),
      kind,
      List.unmodifiable(shape),
      List.unmodifiable(names),
      input['header'] == true,
      image,
    );
  }

  Float32List csvValues(String source) {
    if (kind != 'csv')
      throw const FormatException('The selected task requires an image.');
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
      if (rows.length > shape.first + (csvHeader ? 1 : 0))
        throw const FormatException(
          'CSV has more rows than the task declares.',
        );
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
    if (rows.length != shape.first + (csvHeader ? 1 : 0) ||
        rows.any((r) => r.length != shape[1]))
      throw const FormatException(
        'CSV rows and columns do not match the declared input shape.',
      );
    final values = Float32List(elementCount);
    var index = 0;
    for (final r in rows.skip(csvHeader ? 1 : 0)) {
      for (final raw in r) {
        final v = double.tryParse(raw.trim());
        if (v == null || !v.isFinite)
          throw const FormatException('CSV inputs must be finite numbers.');
        values[index] = v;
        if (!values[index].isFinite)
          throw const FormatException('CSV value exceeds float32 range.');
        index++;
      }
    }
    return values;
  }
}
