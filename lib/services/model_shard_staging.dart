part of 'model_shard_restorer.dart';

extension _ModelShardStaging on ModelShardRestorer {
  Future<void> _stage(
    List<ImportedModelFile> files,
    InstallationSnapshot state,
    List<RestorationArtifact> artifacts,
    Directory root,
  ) async {
    final candidates = await root.createTemp('restore-candidates-');
    try {
      final remaining = [...artifacts];
      for (final (index, picked) in files.indexed) {
        checkActive();
        final candidate = File(p.join(candidates.path, '$index.part'));
        final output = candidate.openWrite();
        try {
          var received = 0;
          await for (final chunk in picked.readStream!) {
            checkActive();
            received += chunk.length;
            if (received > picked.size) throw ModelIdentityMismatch();
            output.add(chunk);
          }
          await output.flush();
          if (received != picked.size) throw ModelIdentityMismatch();
        } finally {
          await output.close();
        }
        checkActive();
        final hash = (await sha256.bind(candidate.openRead()).first).toString();
        final matching = remaining
            .where((a) => a.hash == hash && a.size == picked.size)
            .toList();
        if (matching.length != 1) throw ModelIdentityMismatch();
        final artifact = matching.single;
        remaining.remove(artifact);
        final destination = File(
          state.shards[artifact.index]['staging_path']! as String,
        );
        await LlamaCppChatRepository.withModelFilesMutation(
          [candidate.path, destination.path],
          () async {
            checkActive();
            if (await destination.exists()) {
              final existingHash =
                  (await sha256.bind(destination.openRead()).first).toString();
              if (existingHash == hash &&
                  await destination.length() == picked.size)
                return;
              final quarantine = await destination.parent.parent.createTemp(
                'rejected-',
              );
              await destination.rename(
                p.join(quarantine.path, artifact.basename),
              );
            }
            await candidate.rename(destination.path);
          },
        );
      }
      if (remaining.isNotEmpty) throw ModelIdentityMismatch();
    } finally {
      // This invocation created these candidates and never passes their paths
      // to native inference. Journal-owned staging is retained on every failure.
      await candidates.delete(recursive: true);
    }
  }
}
