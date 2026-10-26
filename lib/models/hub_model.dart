import 'model_library_policy.dart';

enum HubSort { relevance, downloads, recentlyUpdated }

enum DeviceFitLevel {
  recommended,
  likely,
  slow,
  memoryRisk,
  insufficientDisk,
  incompatible,
  unknown,
}

class HubModelSummary {
  const HubModelSummary({
    required this.id,
    required this.revision,
    required this.tags,
    required this.downloads,
    required this.gated,
    this.author,
    this.license,
    this.parameterCount,
    this.lastModified,
  });

  final String id;
  final String revision;
  final String? author;
  final String? license;
  final int? parameterCount;
  final int downloads;
  final DateTime? lastModified;
  final bool gated;
  final List<String> tags;

  bool get isLargeModel =>
      parameterCount != null &&
      parameterCount! > ModelLibraryPolicy.largeModelParameterThreshold;

  Map<String, Object?> toJson() => {
    'id': id,
    'revision': revision,
    'author': author,
    'license': license,
    'parameterCount': parameterCount,
    'downloads': downloads,
    'lastModified': lastModified?.toUtc().toIso8601String(),
    'gated': gated,
    'tags': tags,
  };

  factory HubModelSummary.fromJson(Map<String, Object?> json) =>
      HubModelSummary(
        id: json['id']! as String,
        revision: json['revision']! as String,
        author: json['author'] as String?,
        license: json['license'] as String?,
        parameterCount: json['parameterCount'] as int?,
        downloads: json['downloads']! as int,
        lastModified: json['lastModified'] == null
            ? null
            : DateTime.parse(json['lastModified']! as String),
        gated: json['gated']! as bool,
        tags: (json['tags']! as List).cast<String>(),
      );
}

class GgufFile {
  const GgufFile({
    required this.name,
    required this.sizeBytes,
    this.sha256,
    this.etag,
    this.shardIndex,
    this.shardCount,
  });

  final String name;
  final int? sizeBytes;
  final String? sha256;
  final String? etag;

  /// Zero-based index; standard GGUF filename ordinals are converted on parsing.
  final int? shardIndex;
  final int? shardCount;
}

class GgufVariant {
  const GgufVariant({
    required this.repository,
    required this.revision,
    required this.displayName,
    required this.files,
    this.quantization,
  });

  final String repository;
  final String revision;
  final String displayName;
  final String? quantization;
  final List<GgufFile> files;

  int? get totalBytes {
    if (files.any((file) => file.sizeBytes == null)) return null;
    return files.fold<int>(0, (total, file) => total + file.sizeBytes!);
  }

  bool get isSplit => files.length > 1;
}

class HubSearchPage {
  const HubSearchPage({required this.models, this.nextUrl});

  final List<HubModelSummary> models;
  final Uri? nextUrl;

  Map<String, Object?> toJson() => {
    'models': models.map((model) => model.toJson()).toList(growable: false),
    'nextUrl': nextUrl?.toString(),
  };

  factory HubSearchPage.fromJson(Map<String, Object?> json) => HubSearchPage(
    models: (json['models']! as List)
        .cast<Map>()
        .map((model) => HubModelSummary.fromJson(model.cast<String, Object?>()))
        .toList(growable: false),
    nextUrl: json['nextUrl'] == null
        ? null
        : Uri.parse(json['nextUrl']! as String),
  );
}

class DeviceFitAssessment {
  const DeviceFitAssessment({
    required this.level,
    required this.reason,
    required this.estimatedMemoryBytes,
    required this.requiresLargeModelWarning,
  });

  final DeviceFitLevel level;
  final String reason;
  final int? estimatedMemoryBytes;
  final bool requiresLargeModelWarning;
}
