import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';
import '../models/bundled_model_manifest.dart';
import '../models/model_descriptor.dart';

abstract final class LegacyModelPreferenceManifest {
  static const downloadedKey = 'model_downloaded'; // hardcode: HC-001
  static const filePathKey = 'model_file_path'; // hardcode: HC-001
  static const fileSha256Key = 'model_file_sha256'; // hardcode: HC-001
}

enum LegacyMigrationFailureCode {
  fileUnavailable,
  invalidHeader,
  recordedHashMismatch,
  incompleteMetadata,
  identityConflict,
  preferenceCleanupFailed,
}

/// Contains only a diagnostic code, never the private model path.
final class LegacyMigrationFailure implements Exception {
  const LegacyMigrationFailure(this.code);
  final LegacyMigrationFailureCode code;

  @override
  String toString() => 'LegacyMigrationFailure(${code.name})';
}

/// Imports the pre-registry global model preference exactly once.
///
/// Legacy keys are removed only after the path, GGUF metadata, and optional
/// historical hash have been verified and persisted in SQLite. A legacy hash
/// is not a publisher authority. Other content receives a local identity pending
/// validation; it must never overwrite the bundled identity or chat assignments.
class LegacyModelPreferenceMigration {
  LegacyModelPreferenceMigration({
    DatabaseHelper? database,
    Future<SharedPreferences> Function()? preferences,
    Future<GgufMetadata> Function(String)? metadataReader,
    Future<bool> Function(SharedPreferences, String)? removePreference,
  }) : _database = database ?? DatabaseHelper.instance,
       _preferences = preferences ?? SharedPreferences.getInstance,
       _metadataReader = metadataReader ?? GgufMetadata.fromFile,
       _removePreference = removePreference ?? _remove;

  final DatabaseHelper _database;
  final Future<SharedPreferences> Function() _preferences;
  final Future<GgufMetadata> Function(String) _metadataReader;
  final Future<bool> Function(SharedPreferences, String) _removePreference;

  static Future<bool> _remove(SharedPreferences prefs, String key) =>
      prefs.remove(key);

  Future<bool> run() async {
    final prefs = await _preferences();
    final path = prefs.getString(LegacyModelPreferenceManifest.filePathKey);
    if (path == null || path.isEmpty) return false;
    final file = File(path);
    if (!await file.exists() || await file.length() < 1024 * 1024) {
      throw const LegacyMigrationFailure(
        LegacyMigrationFailureCode.fileUnavailable,
      );
    }
    final header = await file.openRead(0, 4).expand((chunk) => chunk).toList();
    if (header.length != 4 || String.fromCharCodes(header) != 'GGUF') {
      throw const LegacyMigrationFailure(
        LegacyMigrationFailureCode.invalidHeader,
      );
    }
    final actualHash = (await sha256.bind(file.openRead()).first).toString();
    final recordedHash = prefs.getString(
      LegacyModelPreferenceManifest.fileSha256Key,
    );
    if (recordedHash != null &&
        recordedHash.isNotEmpty &&
        recordedHash.toLowerCase() != actualHash.toLowerCase()) {
      throw const LegacyMigrationFailure(
        LegacyMigrationFailureCode.recordedHashMismatch,
      );
    }
    // Do not assign the bundled repository, revision, or chat identity based on
    // a filename or a previously stored, locally computed digest.
    final bundled = actualHash == BundledModelManifest.sha256;
    final modelId = bundled
        ? BundledModelManifest.id
        : 'local-${actualHash.substring(0, 16)}';
    final metadata = await _metadataReader(path);
    final architecture = metadata.architecture?.trim();
    final tokenizer = metadata.get<String>('tokenizer.ggml.model')?.trim();
    final template = metadata.get<String>('tokenizer.chat_template')?.trim();
    if (architecture == null ||
        architecture.isEmpty ||
        tokenizer == null ||
        tokenizer.isEmpty ||
        template == null ||
        template.isEmpty) {
      throw const LegacyMigrationFailure(
        LegacyMigrationFailureCode.incompleteMetadata,
      );
    }
    final descriptor = ModelDescriptor(
      id: modelId,
      displayName: bundled
          ? BundledModelManifest.displayName
          : 'Recovered local model',
      source: bundled ? BundledModelManifest.source : 'legacy_local',
      compatibilityStatus: 'unvalidated',
      localPath: path,
      sha256: actualHash,
      byteSize: await file.length(),
      architecture: architecture,
      tokenizer: tokenizer,
      contextTrain: metadata.contextLength,
      chatTemplate: template,
      blockCount: metadata.get<int>('$architecture.block_count'),
      // Metadata presence is not a verified template or inference probe.
      supportsThinking: false,
      repository: bundled ? BundledModelManifest.repository : null,
      revision: bundled ? BundledModelManifest.revision : null,
      quantization: bundled ? BundledModelManifest.quantization : null,
      parameterCount: bundled ? BundledModelManifest.parameterCount : null,
      installationState: 'pending_validation',
    );
    final database = await _database.database;
    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'models',
        where: 'id = ?',
        whereArgs: [modelId],
      );
      if (rows.isEmpty) {
        await transaction.insert('models', descriptor.toMap());
      } else if (rows.single['local_path'] == null &&
          rows.single['installation_state'] == 'not_installed' &&
          (rows.single['sha256'] == null ||
              rows.single['sha256'] == actualHash)) {
        // Populate only an empty catalogue placeholder, never an installation.
        await transaction.update(
          'models',
          descriptor.toMap(),
          where: 'id = ?',
          whereArgs: [modelId],
        );
      } else if (rows.single['sha256'] != actualHash) {
        // Never replace an existing descriptor, even on a shortened-ID collision.
        throw const LegacyMigrationFailure(
          LegacyMigrationFailureCode.identityConflict,
        );
      }
      // No model_settings writes: recorded chat assignments are authoritative.
      // Re-entry after a committed transaction reuses the record unchanged.
    });
    // The path is the restart marker. Remove it last so interrupted cleanup can
    // re-enter safely after SQLite has committed. Never delete the model file.
    for (final key in [
      LegacyModelPreferenceManifest.downloadedKey,
      LegacyModelPreferenceManifest.fileSha256Key,
      LegacyModelPreferenceManifest.filePathKey,
    ]) {
      if (!await _removePreference(prefs, key)) {
        throw const LegacyMigrationFailure(
          LegacyMigrationFailureCode.preferenceCleanupFailed,
        );
      }
    }
    return true;
  }
}
