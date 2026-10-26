import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/model_download_job.dart';

void main() {
  test('download job round trips persistent state and progress', () {
    final now = DateTime.utc(2026, 9, 2);
    final original = ModelDownloadJob(
      id: 'job-1',
      modelId: 'model-1',
      repository: 'publisher/model',
      revision: List.filled(40, 'a').join(),
      state: ModelDownloadJobState.downloading,
      downloadedBytes: 50,
      totalBytes: 100,
      retryCount: 2,
      errorCode: 'network',
      createdAt: now,
      updatedAt: now,
    );

    final restored = ModelDownloadJob.fromMap(original.toMap());

    expect(restored.state, ModelDownloadJobState.downloading);
    expect(restored.progress, 0.5);
    expect(restored.retryCount, 2);
    expect(restored.errorCode, 'network');
  });

  test('clearError removes the previous failure code', () {
    final now = DateTime.utc(2026, 9, 2);
    final job = ModelDownloadJob(
      id: 'job-1',
      modelId: 'model-1',
      repository: 'publisher/model',
      revision: List.filled(40, 'b').join(),
      state: ModelDownloadJobState.failed,
      downloadedBytes: 0,
      errorCode: 'network',
      createdAt: now,
      updatedAt: now,
    );

    expect(job.copyWith(clearError: true).errorCode, isNull);
  });
}
