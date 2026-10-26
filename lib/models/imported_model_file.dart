class ImportedModelFile {
  const ImportedModelFile({
    required this.name,
    required this.size,
    required this.readStream,
  });
  final String name;
  final int size;
  final Stream<List<int>>? readStream;
}

typedef ModelImportPicker = Future<ImportedModelFile?> Function();
typedef ModelImportSetPicker = Future<List<ImportedModelFile>?> Function();
