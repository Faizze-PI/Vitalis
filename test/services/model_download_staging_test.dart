import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vitalis_app/services/model_download_staging.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('vitalis_job_staging_');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'jobs and same-basename artifacts cannot share writable bytes',
    () async {
      final layout = ModelDownloadStaging(root);
      final first = await layout.partial('job-one', 'a/model.gguf');
      final otherJob = await layout.partial('job-two', 'a/model.gguf');
      final otherArtifact = await layout.partial('job-one', 'b/model.gguf');
      await first.writeAsString('first');
      await otherJob.writeAsString('other-job');
      await otherArtifact.writeAsString('other-artifact');

      await first.delete();

      expect(await otherJob.readAsString(), 'other-job');
      expect(await otherArtifact.readAsString(), 'other-artifact');
      expect(p.isWithin(await root.resolveSymbolicLinks(), first.path), isTrue);
    },
  );

  test('untrusted identity strings cannot escape the storage root', () async {
    final file = await ModelDownloadStaging(
      root,
    ).partial('../../job/with\\separators', '../../artifact.gguf');
    await file.writeAsString('owned');
    expect(p.isWithin(await root.resolveSymbolicLinks(), file.path), isTrue);
    expect(await file.readAsString(), 'owned');
  });

  test('empty identities are rejected before creating staging paths', () async {
    final layout = ModelDownloadStaging(root);
    await expectLater(layout.partial('', 'model.gguf'), throwsFormatException);
    await expectLater(layout.partial('job', ''), throwsFormatException);
    expect(await root.list().isEmpty, isTrue);
  });

  test('a directory cannot masquerade as a writable partial', () async {
    final layout = ModelDownloadStaging(root);
    final file = await layout.partial('job', 'model.gguf');
    await Directory(file.path).create();
    await expectLater(layout.partial('job', 'model.gguf'), throwsStateError);
    expect(await Directory(file.path).exists(), isTrue);
  });
}
