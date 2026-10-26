import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:path/path.dart' as p;

import '../database/model_installation_journal.dart';
import '../models/model_installation.dart';

typedef InstallationFileLease =
    Future<void> Function(
      Iterable<String> paths,
      Future<void> Function() action,
    );
typedef InstallationFileMove =
    Future<void> Function(File source, File destination);

enum InstallationFileFailureCode { boundary, missing, integrity, io }

final class InstallationFileFailure extends StateError {
  InstallationFileFailure(this.code)
    : super('Installation file check: ${code.name}');
  final InstallationFileFailureCode code;
}

final class InstallationPromotionInterrupted extends StateError {
  InstallationPromotionInterrupted()
    : super('Installation promotion interrupted');
}

/// Promotes only an already validated journal. Never overwrites or deletes a
/// destination; interrupted renames are recognized by their exact bytes.
final class ModelInstallationPromoter {
  ModelInstallationPromoter({
    required ModelInstallationJournal journal,
    required Future<List<Directory>> Function() roots,
    InstallationFileLease? withFileLease,
    InstallationFileMove? move,
  }) : _journal = journal,
       _roots = roots,
       _withFileLease = withFileLease ?? _nativeLease,
       _move = move ?? _durableMove;

  final ModelInstallationJournal _journal;
  final Future<List<Directory>> Function() _roots;
  final InstallationFileLease _withFileLease;
  final InstallationFileMove _move;

  static Future<void> _nativeLease(
    Iterable<String> paths,
    Future<void> Function() action,
  ) => LlamaCppChatRepository.withModelFilesMutation(paths, action);

  static Future<void> _durableMove(File source, File destination) async {
    final handle = await source.open(mode: FileMode.append);
    try {
      await handle.flush();
    } finally {
      await handle.close();
    }
    await source.rename(destination.path);
  }

  Future<void> checkPaths(InstallationSnapshot state) async {
    final roots = [
      for (final root in await _roots())
        p.normalize(p.absolute(await root.resolveSymbolicLinks())),
    ];
    await _checkBoundaries([
      for (final shard in state.shards) ...[
        shard['staging_path']! as String,
        shard['final_path']! as String,
      ],
    ], roots);
  }

  Future<InstallationSnapshot> promote(
    String operationId, {
    bool Function()? canContinue,
  }) async {
    void checkStop() {
      if (canContinue?.call() == false)
        throw InstallationPromotionInterrupted();
    }

    checkStop();
    var snapshot = await _journal.read(operationId);
    if (snapshot.phase == InstallationPhase.installed) return snapshot;
    _requirePromotion(snapshot);
    try {
      final roots = [
        for (final root in await _roots())
          p.normalize(p.absolute(await root.resolveSymbolicLinks())),
      ];
      final paths = [
        for (final shard in snapshot.shards) ...[
          shard['staging_path']! as String,
          shard['final_path']! as String,
        ],
      ];
      // Validate before acquiring native path authority, and again inside it.
      await _checkBoundaries(paths, roots);
      await _withFileLease(paths, () async {
        checkStop();
        snapshot = await _journal.read(operationId);
        _requirePromotion(snapshot);
        final currentPaths = [
          for (final shard in snapshot.shards) ...[
            shard['staging_path']! as String,
            shard['final_path']! as String,
          ],
        ];
        if (currentPaths.length != paths.length ||
            currentPaths.indexed.any((entry) => entry.$2 != paths[entry.$1])) {
          throw InstallationConflict();
        }
        await _checkBoundaries(paths, roots);
        for (final shard in snapshot.shards) {
          checkStop();
          await _checkAvailableShard(shard);
        }
        checkStop();
        if (snapshot.phase == InstallationPhase.readyToInstall) {
          snapshot = await _journal.startProjection(
            operationId,
            snapshot.revision,
          );
        }
        for (final shard in snapshot.shards) {
          checkStop();
          final destination = File(shard['final_path']! as String);
          if (!await destination.exists()) {
            final source = File(shard['staging_path']! as String);
            await _move(source, destination);
          }
          // Recheck the actual destination even after a recovered/adapter move.
          await _verify(destination, shard);
          snapshot = await _journal.markMoved(
            operationId,
            snapshot.revision,
            shard['shard_index']! as int,
          );
        }
        checkStop();
        snapshot = await _journal.commit(operationId, snapshot.revision);
      });
      return snapshot;
    } on FileSystemException {
      // Filesystem messages include private paths; expose only a typed code.
      throw InstallationFileFailure(InstallationFileFailureCode.io);
    }
  }

  void _requirePromotion(InstallationSnapshot state) {
    if (state.phase != InstallationPhase.readyToInstall &&
        state.phase != InstallationPhase.projecting)
      throw InstallationConflict();
  }

  Future<void> _checkBoundaries(List<String> paths, List<String> roots) async {
    final identities = <String>{};
    for (final path in paths) {
      final normalized = p.normalize(p.absolute(path));
      final parent = p.normalize(
        await Directory(p.dirname(normalized)).resolveSymbolicLinks(),
      );
      final canonical = p.join(parent, p.basename(normalized));
      final identity = Platform.isWindows ? canonical.toLowerCase() : canonical;
      if (!identities.add(identity) ||
          !roots.any((root) => p.isWithin(root, canonical)) ||
          await FileSystemEntity.type(path, followLinks: false) ==
              FileSystemEntityType.link) {
        throw InstallationFileFailure(InstallationFileFailureCode.boundary);
      }
    }
  }

  Future<void> _checkAvailableShard(Map<String, Object?> shard) async {
    final destination = File(shard['final_path']! as String);
    if (await destination.exists()) {
      await _verify(destination, shard);
      return;
    }
    await _verify(File(shard['staging_path']! as String), shard);
  }

  Future<void> _verify(File file, Map<String, Object?> shard) async {
    if (!await file.exists()) {
      throw InstallationFileFailure(InstallationFileFailureCode.missing);
    }
    if (shard['validation_state'] != 'validated' ||
        await file.length() != shard['byte_size'] ||
        (await sha256.bind(file.openRead()).first).toString() !=
            shard['actual_sha256']) {
      throw InstallationFileFailure(InstallationFileFailureCode.integrity);
    }
  }
}
