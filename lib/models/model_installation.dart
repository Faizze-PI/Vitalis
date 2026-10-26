enum InstallationPhase {
  staging,
  validating,
  readyToInstall,
  projecting,
  installed,
  failed,
}

enum ModelHashAuthority { publisherSha256, immutableRevision, localIdentity }

final class InstallationConflict extends StateError {
  InstallationConflict() : super('Installation ownership or state changed');
}

final class InstallationShard {
  const InstallationShard({
    required this.index,
    required this.count,
    required this.fileName,
    required this.byteSize,
    required this.stagingPath,
    required this.finalPath,
    required this.hashAuthority,
    this.expectedSha256,
    this.entityTag,
  });

  final int index;
  final int count;
  final String fileName;
  final int byteSize;
  final String stagingPath;
  final String finalPath;
  final ModelHashAuthority hashAuthority;
  final String? expectedSha256;
  final String? entityTag;

  Map<String, Object?> toMap() => {
    'shard_index': index,
    'shard_count': count,
    'file_name': fileName,
    'byte_size': byteSize,
    'staging_path': stagingPath,
    'final_path': finalPath,
    'hash_authority': hashAuthority.name,
    'expected_sha256': expectedSha256?.toLowerCase(),
    'entity_tag': entityTag,
  };
}

final class InstallationSnapshot {
  InstallationSnapshot(
    Map<String, Object?> row,
    List<Map<String, Object?>> files,
  ) : row = Map.unmodifiable(row),
      shards = List.unmodifiable(files.map(Map<String, Object?>.unmodifiable));

  final Map<String, Object?> row;
  final List<Map<String, Object?>> shards;
  String get operationId => row['operation_id']! as String;
  String get modelId => row['model_id']! as String;
  int get revision => row['state_revision']! as int;
  InstallationPhase get phase =>
      InstallationPhase.values.byName(row['phase']! as String);
}
