import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/bundled_model_manifest.dart';
import '../models/model_descriptor.dart';
import '../models/startup_capabilities.dart';

abstract interface class StartupModelFiles {
  Future<bool> exists(String path);
  Future<int> size(String path);
  Future<String> digest(String path);
}

final class LocalStartupModelFiles implements StartupModelFiles {
  const LocalStartupModelFiles();
  @override
  Future<bool> exists(String path) => File(path).exists();
  @override
  Future<int> size(String path) => File(path).length();
  @override
  Future<String> digest(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();
}

/// Read-only availability/integrity assessment of one explicit registry identity.
/// Previously established compatibility is required; no native probe runs here.
final class ModelStartupInspector {
  const ModelStartupInspector({
    required this.findModel,
    required this.modelFiles,
    this.files = const LocalStartupModelFiles(),
  });

  final Future<ModelDescriptor?> Function(String) findModel;
  final Future<List<Map<String, dynamic>>> Function(String) modelFiles;
  final StartupModelFiles files;

  Future<StartupModelReadiness> inspect(String modelId) async {
    try {
      final model = await findModel(modelId);
      if (model == null || model.localPath == null) {
        return StartupModelReadiness.missing;
      }
      if (!model.isInstalled || model.compatibilityStatus != 'compatible') {
        return StartupModelReadiness.unknown;
      }
      final hash = model.sha256?.toLowerCase();
      if (!_validHash(hash)) return StartupModelReadiness.unknown;
      if (model.id == BundledModelManifest.id &&
          hash != BundledModelManifest.sha256) {
        return StartupModelReadiness.invalid;
      }
      final records = await modelFiles(modelId);
      if (records.isEmpty) {
        return await _inspectFile(model.localPath!, hash!, model.byteSize);
      }
      final split = records.length > 1;
      int? indexBase;
      if (split) {
        final recordedIndices = records
            .map((row) => row['shard_index'])
            .toSet();
        if (recordedIndices.length != records.length ||
            recordedIndices.any((value) => value is! int)) {
          return StartupModelReadiness.unknown;
        }
        indexBase = recordedIndices.contains(0) ? 0 : 1;
        var totalSize = 0;
        for (var offset = 0; offset < records.length; offset++) {
          if (!recordedIndices.contains(offset + indexBase)) {
            return StartupModelReadiness.unknown;
          }
          final size = records[offset]['byte_size'];
          if (size is! int || size <= 0) return StartupModelReadiness.unknown;
          totalSize += size;
        }
        if (model.byteSize != null && model.byteSize != totalSize) {
          return StartupModelReadiness.unknown;
        }
      }
      final paths = <String>{};
      final indices = <int>{};
      for (final row in records) {
        final path = row['local_path'] as String?;
        final expectedHash = (row['sha256'] as String?)?.toLowerCase();
        final count = row['shard_count'] as int?;
        final index = row['shard_index'] as int?;
        final recordSize = row['byte_size'] as int?;
        if (path == null) return StartupModelReadiness.missing;
        if (!paths.add(path) || !_validHash(expectedHash)) {
          return StartupModelReadiness.unknown;
        }
        if (path == model.localPath) {
          if (expectedHash != hash ||
              (split && index != indexBase) ||
              (!split &&
                  model.byteSize != null &&
                  recordSize != null &&
                  model.byteSize != recordSize)) {
            return StartupModelReadiness.unknown;
          }
        }
        if (records.length > 1 || count != null || index != null) {
          if (count != records.length ||
              index == null ||
              (split
                  ? index < indexBase! || index >= indexBase + records.length
                  : index != 0 && index != 1) ||
              !indices.add(index)) {
            return StartupModelReadiness.unknown;
          }
        }
        final state = await _inspectFile(
          path,
          expectedHash!,
          split ? recordSize : model.byteSize ?? recordSize,
        );
        if (state != StartupModelReadiness.ready) return state;
      }
      // A different shard set cannot stand in for the selected primary file.
      if (!paths.contains(model.localPath))
        return StartupModelReadiness.unknown;
      return StartupModelReadiness.ready;
    } catch (_) {
      // I/O/registry availability does not prove model corruption. Never mutate
      // registry records or log private paths during bootstrap assessment.
      return StartupModelReadiness.unknown;
    }
  }

  static bool _validHash(String? value) =>
      value != null &&
      value.length == sha256.convert(const <int>[]).bytes.length * 2 &&
      RegExp(r'^[0-9a-f]+$').hasMatch(value);

  Future<StartupModelReadiness> _inspectFile(
    String path,
    String expectedHash,
    int? expectedSize,
  ) async {
    if (!await files.exists(path)) return StartupModelReadiness.missing;
    if (expectedSize != null && await files.size(path) != expectedSize) {
      return StartupModelReadiness.invalid;
    }
    return (await files.digest(path)).toLowerCase() == expectedHash
        ? StartupModelReadiness.ready
        : StartupModelReadiness.invalid;
  }
}
