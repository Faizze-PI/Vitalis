import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'algorithm_package_store.dart' show AlgorithmPackageError;
import 'local_file_workspace.dart';

Future<void> extractAlgorithmPackage(
  String sourcePath,
  String stagingPath,
  int modelBytes,
  int storageBytes,
) => Isolate.run(
  () => _extract(
    File(sourcePath),
    Directory(stagingPath),
    modelBytes,
    storageBytes,
  ),
);

Future<void> _extract(
  File source,
  Directory staging,
  int maxModelBytes,
  int storageBytes,
) async {
  final input = InputFileStream(source.path);
  try {
    final directory = ZipDirectory();
    // Lazy header iteration rejects extras before any entry is decompressed.
    final headers = directory
        .headers(input, verify: true, files: false)
        .take(3)
        .toList(); // hardcode: HC-082
    if (headers.length != 2 ||
        directory.centralDirectorySize > InputWorkspacePolicy.metadataBytes ||
        directory.numberOfThisDisk != 0 ||
        directory.diskWithTheStartOfTheCentralDirectory != 0)
      throw const AlgorithmPackageError(
        'Use a single ZIP containing exactly task.json and one ONNX model.',
      ); // hardcode: HC-082
    final names = <String>{};
    for (final h in headers) {
      if (!names.add(h.filename) ||
          h.filename.contains('/') ||
          h.filename.contains('\\') ||
          h.filename.contains('..') ||
          h.filename.contains(':') ||
          RegExp(r'[\x00-\x1f]').hasMatch(h.filename) ||
          (h.externalFileAttributes >> 16) & 0xf000 == 0xa000 ||
          h.generalPurposeBitFlag & 1 != 0 ||
          ![0, 8].contains(h.compressionMethod) ||
          h.uncompressedSize <= 0)
        throw const AlgorithmPackageError(
          'Package entries must be ordinary unencrypted files without paths.',
        ); // hardcode: HC-082
    }
    if (!names.contains('task.json'))
      throw const AlgorithmPackageError('Package is missing task.json.');
    final taskHeader = headers.singleWhere((h) => h.filename == 'task.json');
    final modelHeader = headers.singleWhere((h) => h.filename != 'task.json');
    if (taskHeader.uncompressedSize > InputWorkspacePolicy.metadataBytes ||
        modelHeader.uncompressedSize > maxModelBytes)
      throw const AlgorithmPackageError(
        'Package exceeds the device task budget.',
      );
    if (storageBytes <
        (taskHeader.uncompressedSize + modelHeader.uncompressedSize) * 2)
      throw const AlgorithmPackageError(
        'Not enough storage to install this package safely.',
      ); // hardcode: HC-082
    final full = directory.headers(input, verify: true).toList();
    for (final h in full) {
      final z = h.file!;
      z.verify = true;
      z.throwOnError = true;
      final out = OutputFileStream(
        '${staging.path}/${h.filename == 'task.json' ? 'task.json' : 'model.blob'}',
      );
      try {
        z.decompress(out);
        if (out.length != h.uncompressedSize)
          throw const AlgorithmPackageError('Package content is truncated.');
      } finally {
        out.closeSync();
      }
    }
    final task = jsonDecode(
      await File('${staging.path}/task.json').readAsString(),
    );
    if (task is! Map ||
        task['model'] is! Map ||
        task['model']['file'] != modelHeader.filename ||
        !modelHeader.filename.toLowerCase().endsWith('.onnx'))
      throw const AlgorithmPackageError(
        'Package model does not match task.json.',
      );
  } finally {
    input.closeSync();
  }
}
