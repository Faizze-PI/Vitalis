import 'package:path/path.dart' as p;

import 'model_installation.dart';
import 'model_storage_error.dart';

/// Existing local hash authority is not upgraded to a publisher attestation.
final class RestorationArtifact {
  RestorationArtifact(this.row, this.index);
  final Map<String, Object?> row;
  final int index;
  String get fileName => row['file_name']! as String;
  String get basename => p.basename(fileName);
  String get hash => (row['sha256']! as String).toLowerCase();
  int get size => row['byte_size']! as int;
  String? get entityTag => row['etag'] as String?;

  static List<RestorationArtifact> inspect(List<Map<String, Object?>> rows) {
    if (rows.length < 2) throw InstallationConflict();
    final sorted = [...rows]
      ..sort(
        (a, b) => ((a['shard_index'] as int?) ?? -1).compareTo(
          (b['shard_index'] as int?) ?? -1,
        ),
      );
    final base = sorted.first['shard_index'];
    if (base != 0 && base != 1) throw InstallationConflict();
    final names = <String>{};
    final hashes = <String>{};
    final artifacts = <RestorationArtifact>[];
    for (final (index, row) in sorted.indexed) {
      final name = row['file_name'];
      final hash = row['sha256'];
      final size = row['byte_size'];
      if (name is! String ||
          hash is! String ||
          size is! int ||
          size <= 0 ||
          row['shard_count'] != rows.length ||
          row['shard_index'] != index + (base! as int) ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) ||
          name.contains('..') ||
          name.contains('\\') ||
          p.isAbsolute(name)) {
        throw InstallationConflict();
      }
      final basename = p.basename(name);
      final ordinal = RegExp(
        r'-(\d{5})-of-(\d{5})\.gguf$',
        caseSensitive: false,
      ).firstMatch(basename);
      if (ordinal == null ||
          int.parse(ordinal.group(1)!) != index + 1 ||
          int.parse(ordinal.group(2)!) != rows.length ||
          !names.add(basename.toLowerCase()) ||
          !hashes.add(hash.toLowerCase())) {
        throw InstallationConflict();
      }
      artifacts.add(RestorationArtifact(Map.unmodifiable(row), index));
    }
    return List.unmodifiable(artifacts);
  }

  void requirePrimaryIdentity(
    String? expectedHash,
    int? expectedSize,
    List<RestorationArtifact> set,
  ) {
    if (expectedHash?.toLowerCase() != hash ||
        (expectedSize != null &&
            expectedSize != set.fold<int>(0, (n, a) => n + a.size))) {
      throw ModelIdentityMismatch();
    }
  }
}
