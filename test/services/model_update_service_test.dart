import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/hub_model.dart';
import 'package:vitalis_app/models/model_descriptor.dart';
import 'package:vitalis_app/models/model_download_job.dart';
import 'package:vitalis_app/services/model_download_manager.dart';
import 'package:vitalis_app/services/model_hub_client.dart';
import 'package:vitalis_app/services/model_update_service.dart';

void main() {
  final oldRevision = 'a' * 40;
  final newRevision = 'b' * 40;
  late _FakeHub hub;
  late _FakeDownloads downloads;
  late _FakeRecords records;
  late HubModelUpdateService service;

  setUp(() {
    hub = _FakeHub(newRevision);
    downloads = _FakeDownloads();
    records = _FakeRecords();
    service = HubModelUpdateService(
      hub: hub,
      downloads: downloads,
      records: records,
    );
  });

  test('check records a distinct immutable update revision', () async {
    final result = await service.check(_model(oldRevision));
    expect(result.available, isTrue);
    expect(result.latest!.revision, newRevision);
    expect(records.last!.updateRevision, newRevision);
  });

  test('apply downloads the same quantization at the new revision', () async {
    final job = await service.apply(_model(oldRevision));
    expect(job.revision, newRevision);
    expect(downloads.enqueued!.revision, newRevision);
    expect(downloads.variant!.quantization, 'Q4_K_M');
  });
}

ModelDescriptor _model(String revision) => ModelDescriptor(
  id: 'installed',
  displayName: 'model-Q4_K_M',
  source: 'huggingface',
  compatibilityStatus: 'compatible',
  repository: 'publisher/model',
  revision: revision,
  quantization: 'Q4_K_M',
  installationState: 'installed',
  localPath: 'model.gguf',
  sha256: 'c' * 64,
);

class _FakeHub implements ModelHubClient {
  _FakeHub(this.revision);
  final String revision;

  @override
  Future<HubModelSummary> repository(String repository) async =>
      HubModelSummary(
        id: repository,
        revision: revision,
        downloads: 1,
        gated: false,
        tags: const ['gguf'],
      );

  @override
  Future<List<GgufVariant>> resolveGgufArtifacts({
    required String repository,
    required String revision,
  }) async => [
    GgufVariant(
      repository: repository,
      revision: revision,
      displayName: 'model-Q4_K_M',
      quantization: 'Q4_K_M',
      files: const [GgufFile(name: 'model.gguf', sizeBytes: 10)],
    ),
  ];

  @override
  Future<HubSearchPage> search({
    String query = '',
    HubSort sort = HubSort.downloads,
    String? publisher,
    int limit = 20,
    Uri? page,
  }) => throw UnimplementedError();
}

class _FakeDownloads implements ModelDownloadOperations {
  HubModelSummary? enqueued;
  GgufVariant? variant;

  @override
  Future<ModelDownloadJob> enqueue({
    required HubModelSummary model,
    required GgufVariant variant,
  }) async {
    enqueued = model;
    this.variant = variant;
    final now = DateTime.utc(2026, 9, 2);
    return ModelDownloadJob(
      id: 'job',
      modelId: 'new-model',
      repository: model.id,
      revision: model.revision,
      state: ModelDownloadJobState.queued,
      downloadedBytes: 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<ModelDownloadJob> run(ModelDownloadJob original) async =>
      original.copyWith(state: ModelDownloadJobState.completed);
}

class _FakeRecords implements ModelUpdateRecordStore {
  ModelDescriptor? last;

  @override
  Future<void> write(ModelDescriptor model) async => last = model;
}
