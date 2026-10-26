import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:path/path.dart' as p;

import '../database/model_installation_journal.dart';
import '../models/imported_model_file.dart';
import '../models/model_descriptor.dart';
import '../models/model_installation.dart';
import '../models/model_storage_error.dart';
import '../models/model_verification_phase.dart';
import '../models/restoration_artifact.dart';
import 'model_installation_promoter.dart';

part 'model_shard_staging.dart';

/// User-invoked exact-byte recovery. Retains journal-owned files on interruption;
/// native probe cleanup remains the registry's acknowledged owner operation.
final class ModelShardRestorer {
  ModelShardRestorer({
    required this.journal,
    required this.modelsDirectory,
    required this.picker,
    required this.validate,
    required this.checkActive,
  });
  final ModelInstallationJournal journal;
  final Future<Directory> Function() modelsDirectory;
  final ModelImportSetPicker picker;
  final Future<ModelDescriptor> Function(
    ModelDescriptor model,
    String primaryPath,
  )
  validate;
  final void Function() checkActive;

  Future<ModelDescriptor?> restore(
    ModelDescriptor current,
    List<Map<String, Object?>> records, {
    ModelVerificationPhaseSink? onPhase,
  }) async {
    checkActive();
    final artifacts = RestorationArtifact.inspect(records);
    artifacts.first.requirePrimaryIdentity(
      current.sha256,
      current.byteSize,
      artifacts,
    );
    final root = await modelsDirectory();
    await root.create(recursive: true);
    checkActive();
    final pending = await journal.pending(modelId: current.id);
    checkActive();
    if (pending.length > 1 || pending.any((s) => s.row['job_id'] != null)) {
      throw ModelStorageBusy();
    }
    InstallationSnapshot state;
    List<ImportedModelFile>? picked;
    if (pending.isEmpty) {
      if ((await Future.wait(
        records.map(
          (row) async =>
              row['local_path'] is String &&
              await File(row['local_path']! as String).exists(),
        ),
      )).every((present) => present)) {
        throw StateError('The recorded model files are still present');
      }
      checkActive();
      picked = await picker();
      checkActive();
      if (picked == null) return null;
      _checkPicked(picked, artifacts);
      final operation = await root.createTemp('restore-set-');
      final staging = await Directory(
        p.join(operation.path, 'staging'),
      ).create();
      final installed = await Directory(
        p.join(operation.path, 'installed'),
      ).create();
      checkActive();
      state = await journal.begin(
        operationId: 'restore-${p.basename(operation.path)}',
        modelId: current.id,
        expectedModel: current,
        shards: [
          for (final artifact in artifacts)
            InstallationShard(
              index: artifact.index,
              count: artifacts.length,
              fileName: artifact.fileName,
              byteSize: artifact.size,
              expectedSha256: artifact.hash,
              hashAuthority: ModelHashAuthority.localIdentity,
              entityTag: artifact.entityTag,
              stagingPath: p.join(staging.path, artifact.basename),
              finalPath: p.join(installed.path, artifact.basename),
            ),
        ],
      );
    } else {
      state = pending.single;
      final expected = ModelDescriptor.fromMap(
        Map<String, Object?>.from(
          jsonDecode(state.row['expected_model_json']! as String) as Map,
        ),
      );
      if (jsonEncode(expected.toMap()) != jsonEncode(current.toMap())) {
        throw InstallationConflict();
      }
    }
    checkActive();
    final promoter = ModelInstallationPromoter(
      journal: journal,
      roots: () async => [root],
    );
    await _checkLayout(state, root, artifacts);
    await promoter.checkPaths(state);
    checkActive();
    if (state.phase == InstallationPhase.staging ||
        state.phase == InstallationPhase.validating) {
      if (picked == null && !await _allStaged(state)) {
        picked = await picker();
        checkActive();
        if (picked == null) return null;
        _checkPicked(picked, artifacts);
      }
      if (state.phase == InstallationPhase.staging) {
        checkActive();
        state = await journal.startValidation(
          state.operationId,
          state.revision,
        );
      }
      onPhase?.call(ModelVerificationPhase.hashing);
      if (picked != null) await _stage(picked, state, artifacts, root);
      for (final shard in state.shards) {
        checkActive();
        final file = File(shard['staging_path']! as String);
        final hash = (await sha256.bind(file.openRead()).first).toString();
        state = await journal.validateShard(
          state.operationId,
          state.revision,
          index: shard['shard_index']! as int,
          byteSize: await file.length(),
          sha256: hash,
        );
      }
      checkActive();
      final primary = state.shards.first;
      final validated = await validate(
        ModelDescriptor.fromMap({
          ...current.toMap(),
          'byte_size': artifacts.fold<int>(0, (n, a) => n + a.size),
        }),
        primary['staging_path']! as String,
      );
      checkActive();
      state = await journal.ready(
        state.operationId,
        state.revision,
        ModelDescriptor.fromMap({
          ...validated.toMap(),
          'local_path': primary['final_path'],
        }),
      );
    }
    final installed = await promoter.promote(
      state.operationId,
      canContinue: () {
        checkActive();
        return true;
      },
    );
    return ModelDescriptor.fromMap(
      Map<String, Object?>.from(
        jsonDecode(installed.row['validated_model_json']! as String) as Map,
      ),
    );
  }

  void _checkPicked(
    List<ImportedModelFile> files,
    List<RestorationArtifact> artifacts,
  ) {
    if (files.length != artifacts.length ||
        files.any(
          (file) =>
              file.readStream == null ||
              !artifacts.any((artifact) => artifact.size == file.size),
        )) {
      throw ModelIdentityMismatch();
    }
  }

  Future<bool> _allStaged(InstallationSnapshot state) async {
    for (final shard in state.shards) {
      checkActive();
      final file = File(shard['staging_path']! as String);
      if (!await file.exists() ||
          await file.length() != shard['byte_size'] ||
          (await sha256.bind(file.openRead()).first).toString() !=
              shard['expected_sha256']) {
        return false;
      }
    }
    return true;
  }

  Future<void> _checkLayout(
    InstallationSnapshot state,
    Directory root,
    List<RestorationArtifact> artifacts,
  ) async {
    if (state.shards.length != artifacts.length) throw InstallationConflict();
    final operation = Directory(
      p.dirname(p.dirname(state.shards.first['staging_path']! as String)),
    );
    final canonical = await operation.resolveSymbolicLinks();
    if (!p.equals(p.dirname(canonical), await root.resolveSymbolicLinks()) ||
        !p.basename(canonical).startsWith('restore-set-') ||
        state.operationId != 'restore-${p.basename(canonical)}')
      throw InstallationConflict();
    for (final artifact in artifacts) {
      final shard = state.shards[artifact.index];
      final staged = shard['staging_path']! as String;
      final finalPath = shard['final_path']! as String;
      if (shard['file_name'] != artifact.fileName ||
          shard['expected_sha256'] != artifact.hash ||
          shard['byte_size'] != artifact.size ||
          shard['entity_tag'] != artifact.entityTag ||
          p.basename(staged) != artifact.basename ||
          p.basename(finalPath) != artifact.basename ||
          !p.equals(
            await Directory(p.dirname(staged)).resolveSymbolicLinks(),
            p.join(canonical, 'staging'),
          ) ||
          !p.equals(
            await Directory(p.dirname(finalPath)).resolveSymbolicLinks(),
            p.join(canonical, 'installed'),
          )) {
        throw InstallationConflict();
      }
    }
  }
}
