part of 'model_installation_journal.dart';

extension ModelInstallationProjection on ModelInstallationJournal {
  Future<InstallationSnapshot> ready(
    String id,
    int revision,
    ModelDescriptor model,
  ) => _mutate(id, revision, InstallationPhase.validating, (tx, current) async {
    final primary = current.shards.first;
    final expected =
        jsonDecode(current.row['expected_model_json']! as String) as Map;
    if (current.shards.any((s) => s['validation_state'] != 'validated') ||
        model.id != current.modelId ||
        model.compatibilityStatus != 'compatible' ||
        model.installationState != 'installed' ||
        model.localPath != primary['final_path'] ||
        model.sha256?.toLowerCase() != primary['actual_sha256'] ||
        model.byteSize !=
            current.shards.fold<int>(
              0,
              (sum, s) => sum + (s['byte_size']! as int),
            ) ||
        model.source != expected['source'] ||
        model.repository != expected['repository'] ||
        model.revision != expected['revision']) {
      throw InstallationConflict();
    }
    return {
      'phase': InstallationPhase.readyToInstall.name,
      'validated_model_json': jsonEncode(model.toMap()),
    };
  });

  Future<InstallationSnapshot> startProjection(String id, int revision) =>
      _mutate(
        id,
        revision,
        InstallationPhase.readyToInstall,
        (tx, current) async => {'phase': InstallationPhase.projecting.name},
      );

  Future<InstallationSnapshot> markMoved(String id, int revision, int index) =>
      _mutate(id, revision, InstallationPhase.projecting, (tx, current) async {
        if (!current.shards.any(
          (s) =>
              s['shard_index'] == index && s['validation_state'] == 'validated',
        )) {
          throw InstallationConflict();
        }
        await tx.update(
          'model_installation_shards',
          {'moved': 1},
          where: 'operation_id = ? AND shard_index = ?',
          whereArgs: [id, index],
        );
        return {};
      });

  Future<InstallationSnapshot> commit(String id, int revision) =>
      _mutate(id, revision, InstallationPhase.projecting, (tx, current) async {
        if (current.shards.any(
          (s) => s['moved'] != 1 || s['validation_state'] != 'validated',
        )) {
          throw InstallationConflict();
        }
        final models = await tx.query(
          'models',
          where: 'id = ?',
          whereArgs: [current.modelId],
        );
        if (models.length != 1 ||
            jsonEncode(models.single) != current.row['expected_model_json']) {
          throw InstallationConflict();
        }
        final artifacts = await tx.query(
          'model_files',
          where: 'model_id = ?',
          whereArgs: [current.modelId],
          orderBy: 'id',
        );
        if (jsonEncode(artifacts) != current.row['expected_files_json']) {
          throw InstallationConflict();
        }
        final validated = Map<String, Object?>.from(
          jsonDecode(current.row['validated_model_json']! as String) as Map,
        );
        await tx.update(
          'models',
          validated,
          where: 'id = ?',
          whereArgs: [current.modelId],
        );
        await tx.delete(
          'model_files',
          where: 'model_id = ?',
          whereArgs: [current.modelId],
        );
        for (final shard in current.shards) {
          await tx.insert('model_files', {
            'model_id': current.modelId,
            'file_name': shard['file_name'],
            'local_path': shard['final_path'],
            'byte_size': shard['byte_size'],
            'sha256': shard['expected_sha256'] ?? shard['actual_sha256'],
            'etag': shard['entity_tag'],
            'shard_index': shard['shard_index'],
            'shard_count': shard['shard_count'],
          });
        }
        return {'phase': InstallationPhase.installed.name};
      });
}
