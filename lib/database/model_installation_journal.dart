import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/model_descriptor.dart';
import '../models/model_installation.dart';

part 'model_installation_projection.dart';

/// Database intent/projection authority; filesystem and native validation remain
/// owned by the installation coordinator. No files are deleted by this store.
final class ModelInstallationJournal {
  ModelInstallationJournal({
    required Future<Database> Function() database,
    DateTime Function()? clock,
  }) : _database = database,
       _clock = clock ?? DateTime.now;

  final Future<Database> Function() _database;
  final DateTime Function() _clock;
  static final _sha256 = RegExp(r'^[a-fA-F0-9]{64}$');

  Future<InstallationSnapshot> begin({
    required String operationId,
    required String modelId,
    required List<InstallationShard> shards,
    String? jobId,
    ModelDescriptor? expectedModel,
  }) async {
    if (operationId.isEmpty ||
        modelId.isEmpty ||
        shards.isEmpty ||
        shards.any(
          (s) =>
              s.count != shards.length ||
              s.index < 0 ||
              s.index >= shards.length ||
              s.byteSize <= 0 ||
              s.fileName.isEmpty ||
              s.stagingPath.isEmpty ||
              s.finalPath.isEmpty ||
              s.stagingPath == s.finalPath ||
              (s.expectedSha256 != null &&
                  !_sha256.hasMatch(s.expectedSha256!)) ||
              (s.hashAuthority != ModelHashAuthority.immutableRevision &&
                  s.expectedSha256 == null),
        ) ||
        shards.map((s) => s.index).toSet().length != shards.length ||
        shards.map((s) => s.fileName).toSet().length != shards.length ||
        shards.map((s) => s.stagingPath).toSet().length != shards.length ||
        shards.map((s) => s.finalPath).toSet().length != shards.length) {
      throw const FormatException('Invalid installation shard set');
    }
    final db = await _database();
    return db.transaction((tx) async {
      final model = await tx.query(
        'models',
        where: 'id = ?',
        whereArgs: [modelId],
      );
      if (model.length != 1) throw InstallationConflict();
      if (expectedModel != null &&
          jsonEncode(expectedModel.toMap()) !=
              jsonEncode(ModelDescriptor.fromMap(model.single).toMap())) {
        throw InstallationConflict();
      }
      final primary = shards.singleWhere((s) => s.index == 0);
      if (model.single['sha256'] case final String existingHash) {
        if (primary.expectedSha256 != null &&
            primary.expectedSha256!.toLowerCase() !=
                existingHash.toLowerCase()) {
          throw InstallationConflict();
        }
      }
      if (shards.any(
            (s) => s.hashAuthority == ModelHashAuthority.immutableRevision,
          ) &&
          ((model.single['revision'] as String?)?.isNotEmpty != true ||
              (model.single['repository'] as String?)?.isNotEmpty != true)) {
        throw const FormatException('Immutable revision authority is missing');
      }
      final existing = await tx.query(
        'model_installation_journal',
        where: 'operation_id = ? OR (model_id = ? AND phase NOT IN (?, ?))',
        whereArgs: [operationId, modelId, 'installed', 'failed'],
      );
      if (existing.isNotEmpty) throw InstallationConflict();
      final stamp = _clock().toIso8601String();
      final artifacts = await tx.query(
        'model_files',
        where: 'model_id = ?',
        whereArgs: [modelId],
        orderBy: 'id',
      );
      await tx.insert('model_installation_journal', {
        'operation_id': operationId,
        'job_id': jobId,
        'model_id': modelId,
        'repository': model.single['repository'],
        'revision': model.single['revision'],
        'phase': InstallationPhase.staging.name,
        'state_revision': 0,
        'expected_model_json': jsonEncode(model.single),
        'expected_files_json': jsonEncode(artifacts),
        'created_at': stamp,
        'updated_at': stamp,
      });
      for (final shard in shards) {
        await tx.insert('model_installation_shards', {
          ...shard.toMap(),
          'operation_id': operationId,
        });
      }
      return _read(tx, operationId);
    });
  }

  Future<InstallationSnapshot> read(String id) async {
    final db = await _database();
    return db.transaction((tx) => _read(tx, id));
  }

  Future<List<InstallationSnapshot>> pending({String? modelId}) async {
    final db = await _database();
    return db.transaction((tx) async {
      final rows = await tx.query(
        'model_installation_journal',
        where:
            'phase NOT IN (?, ?)${modelId == null ? '' : ' AND model_id = ?'}',
        whereArgs: ['installed', 'failed', if (modelId != null) modelId],
        orderBy: 'created_at, operation_id',
      );
      return [
        for (final row in rows) await _read(tx, row['operation_id']! as String),
      ];
    });
  }

  Future<InstallationSnapshot> startValidation(String id, int revision) =>
      _mutate(
        id,
        revision,
        InstallationPhase.staging,
        (tx, current) async => {'phase': InstallationPhase.validating.name},
      );

  Future<InstallationSnapshot> validateShard(
    String id,
    int revision, {
    required int index,
    required int byteSize,
    required String sha256,
  }) =>
      _mutate(id, revision, InstallationPhase.validating, (tx, current) async {
        final matches = current.shards.where((s) => s['shard_index'] == index);
        if (matches.length != 1 || !_sha256.hasMatch(sha256))
          throw InstallationConflict();
        final shard = matches.single;
        final hash = sha256.toLowerCase();
        final expectedModel =
            jsonDecode(current.row['expected_model_json']! as String) as Map;
        if (shard['byte_size'] != byteSize ||
            (index == 0 &&
                expectedModel['sha256'] != null &&
                (expectedModel['sha256'] as String).toLowerCase() != hash) ||
            (shard['expected_sha256'] != null &&
                shard['expected_sha256'] != hash)) {
          throw InstallationConflict();
        }
        await tx.update(
          'model_installation_shards',
          {'actual_sha256': hash, 'validation_state': 'validated'},
          where: 'operation_id = ? AND shard_index = ?',
          whereArgs: [id, index],
        );
        return {};
      });

  Future<InstallationSnapshot> _mutate(
    String id,
    int revision,
    InstallationPhase phase,
    Future<Map<String, Object?>> Function(Transaction, InstallationSnapshot)
    action,
  ) async {
    final db = await _database();
    return db.transaction((tx) async {
      final current = await _read(tx, id);
      if (current.revision != revision || current.phase != phase)
        throw InstallationConflict();
      final updates = await action(tx, current);
      await tx.update(
        'model_installation_journal',
        {
          ...updates,
          'state_revision': revision + 1,
          'updated_at': _clock().toIso8601String(),
        },
        where: 'operation_id = ?',
        whereArgs: [id],
      );
      return _read(tx, id);
    });
  }

  Future<InstallationSnapshot> _read(DatabaseExecutor db, String id) async {
    final rows = await db.query(
      'model_installation_journal',
      where: 'operation_id = ?',
      whereArgs: [id],
    );
    if (rows.length != 1) throw InstallationConflict();
    final shards = await db.query(
      'model_installation_shards',
      where: 'operation_id = ?',
      whereArgs: [id],
      orderBy: 'shard_index',
    );
    if (shards.isEmpty ||
        shards.indexed.any(
          (entry) =>
              entry.$2['shard_index'] != entry.$1 ||
              entry.$2['shard_count'] != shards.length,
        )) {
      throw InstallationConflict();
    }
    return InstallationSnapshot(rows.single, shards);
  }
}
