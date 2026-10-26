enum ModelDownloadJobState {
  queued,
  downloading,
  paused,
  validating,
  completed,
  cancelled,
  failed,
}

class ModelDownloadJob {
  static const nativeCancellationPending =
      'native_cancellation_pending'; // hardcode: HC-051

  const ModelDownloadJob({
    required this.id,
    required this.modelId,
    required this.repository,
    required this.revision,
    required this.state,
    required this.downloadedBytes,
    required this.createdAt,
    required this.updatedAt,
    this.totalBytes,
    this.retryCount = 0,
    this.errorCode,
  });

  final String id;
  final String modelId;
  final String repository;
  final String revision;
  final ModelDownloadJobState state;
  final int downloadedBytes;
  final int? totalBytes;
  final int retryCount;
  final String? errorCode;
  final DateTime createdAt;
  final DateTime updatedAt;

  double? get progress => totalBytes == null || totalBytes == 0
      ? null
      : (downloadedBytes / totalBytes!).clamp(0, 1);

  ModelDownloadJob copyWith({
    ModelDownloadJobState? state,
    int? downloadedBytes,
    int? totalBytes,
    int? retryCount,
    String? errorCode,
    bool clearError = false,
    DateTime? updatedAt,
  }) => ModelDownloadJob(
    id: id,
    modelId: modelId,
    repository: repository,
    revision: revision,
    state: state ?? this.state,
    downloadedBytes: downloadedBytes ?? this.downloadedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    retryCount: retryCount ?? this.retryCount,
    errorCode: clearError ? null : errorCode ?? this.errorCode,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'model_id': modelId,
    'repository': repository,
    'revision': revision,
    'state': state.name,
    'downloaded_bytes': downloadedBytes,
    'total_bytes': totalBytes,
    'retry_count': retryCount,
    'error_code': errorCode,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory ModelDownloadJob.fromMap(Map<String, Object?> map) =>
      ModelDownloadJob(
        id: map['id']! as String,
        modelId: map['model_id']! as String,
        repository: map['repository']! as String,
        revision: map['revision']! as String,
        state: ModelDownloadJobState.values.byName(map['state']! as String),
        downloadedBytes: map['downloaded_bytes']! as int,
        totalBytes: map['total_bytes'] as int?,
        retryCount: map['retry_count'] as int? ?? 0,
        errorCode: map['error_code'] as String?,
        createdAt: DateTime.parse(map['created_at']! as String),
        updatedAt: DateTime.parse(map['updated_at']! as String),
      );
}
