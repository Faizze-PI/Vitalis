import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// New partials belong to one durable job and exact repository artifact.
/// Legacy model-scoped partials are deliberately not adopted or deleted.
final class ModelDownloadStaging {
  const ModelDownloadStaging(this.modelDirectory);

  final Directory modelDirectory;

  Future<File> partial(String jobId, String artifactName) async {
    if (jobId.isEmpty || artifactName.isEmpty) {
      throw const FormatException('Missing download staging identity');
    }
    final root = await modelDirectory.resolveSymbolicLinks();
    var parent = Directory(root);
    for (final component in [
      '.downloads',
      sha256.convert(utf8.encode(jobId)).toString(),
      sha256.convert(utf8.encode(artifactName)).toString(),
    ]) {
      parent = Directory(p.join(parent.path, component));
      if (await FileSystemEntity.type(parent.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw StateError('Download staging boundary rejected');
      }
      await parent.create();
      if (!p.equals(await parent.resolveSymbolicLinks(), parent.path)) {
        throw StateError('Download staging alias rejected');
      }
    }
    final partial = File(p.join(parent.path, 'artifact.gguf.part'));
    final type = await FileSystemEntity.type(partial.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw StateError('Download staging file rejected');
    }
    return partial;
  }
}
