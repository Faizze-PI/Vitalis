import '../database/database_helper.dart';
import '../models/hub_model.dart';
import '../models/model_descriptor.dart';
import '../models/model_download_job.dart';
import 'model_download_manager.dart';
import 'model_hub_client.dart';

class ModelUpdateAvailability {
  const ModelUpdateAvailability({
    required this.available,
    required this.currentRevision,
    this.latest,
  });

  final bool available;
  final String? currentRevision;
  final HubModelSummary? latest;
}

abstract interface class ModelUpdateService {
  Future<ModelUpdateAvailability> check(ModelDescriptor model);
  Future<ModelDownloadJob> apply(ModelDescriptor model);
}

abstract interface class ModelUpdateRecordStore {
  Future<void> write(ModelDescriptor model);
}

class DatabaseModelUpdateRecordStore implements ModelUpdateRecordStore {
  DatabaseModelUpdateRecordStore({DatabaseHelper? database})
    : _database = database ?? DatabaseHelper.instance;

  final DatabaseHelper _database;

  @override
  Future<void> write(ModelDescriptor model) =>
      _database.upsertModel(model.toMap());
}

class HubModelUpdateService implements ModelUpdateService {
  HubModelUpdateService({
    required ModelHubClient hub,
    required ModelDownloadOperations downloads,
    DatabaseHelper? database,
    ModelUpdateRecordStore? records,
  }) : _hub = hub,
       _downloads = downloads,
       _records = records ?? DatabaseModelUpdateRecordStore(database: database);

  final ModelHubClient _hub;
  final ModelDownloadOperations _downloads;
  final ModelUpdateRecordStore _records;

  @override
  Future<ModelUpdateAvailability> check(ModelDescriptor model) async {
    if (model.source != 'huggingface' || model.repository == null) {
      return ModelUpdateAvailability(
        available: false,
        currentRevision: model.revision,
      );
    }
    final latest = await _hub.repository(model.repository!);
    final available =
        model.revision != null && latest.revision != model.revision;
    await _records.write(
      ModelDescriptor.fromMap({
        ...model.toMap(),
        'update_revision': available ? latest.revision : null,
      }),
    );
    return ModelUpdateAvailability(
      available: available,
      currentRevision: model.revision,
      latest: latest,
    );
  }

  @override
  Future<ModelDownloadJob> apply(ModelDescriptor model) async {
    final availability = await check(model);
    final latest = availability.latest;
    if (!availability.available || latest == null) {
      throw StateError('No model update is available');
    }
    final variants = await _hub.resolveGgufArtifacts(
      repository: latest.id,
      revision: latest.revision,
    );
    final matching = variants.where(
      (variant) =>
          (model.quantization != null &&
              variant.quantization == model.quantization) ||
          variant.displayName == model.displayName,
    );
    if (matching.isEmpty) {
      throw StateError(
        'The installed quantization is unavailable at the new revision',
      );
    }
    final job = await _downloads.enqueue(
      model: latest,
      variant: matching.first,
    );
    return _downloads.run(job);
  }
}
