import 'package:dio/dio.dart';

import '../models/hub_model.dart';

abstract interface class ModelHubClient {
  Future<HubModelSummary> repository(String repository);

  Future<HubSearchPage> search({
    String query = '',
    HubSort sort = HubSort.downloads,
    String? publisher,
    int limit = 20,
    Uri? page,
  });

  Future<List<GgufVariant>> resolveGgufArtifacts({
    required String repository,
    required String revision,
  });
}

class HuggingFaceModelHubClient implements ModelHubClient {
  HuggingFaceModelHubClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://huggingface.co',
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              headers: const {'Accept': 'application/json'},
            ),
          );

  final Dio _dio;

  @override
  Future<HubModelSummary> repository(String repository) async {
    _validateRepository(repository);
    final encoded = repository.split('/').map(Uri.encodeComponent).join('/');
    final response = await _dio.get<Object?>('/api/models/$encoded');
    if (response.data is! Map) {
      throw const FormatException('Invalid Hub repository');
    }
    final model = _parseSummary(
      (response.data! as Map).cast<String, Object?>(),
    );
    if (model.id != repository) {
      throw const FormatException('Hub repository identity changed');
    }
    if (model.gated) {
      throw const ModelHubAccessException('Only public models are supported');
    }
    return model;
  }

  @override
  Future<HubSearchPage> search({
    String query = '',
    HubSort sort = HubSort.downloads,
    String? publisher,
    int limit = 20,
    Uri? page,
  }) async {
    if (page != null) _validatePageUri(page);
    final response = page == null
        ? await _dio.get<Object?>(
            '/api/models',
            queryParameters: {
              if (query.trim().isNotEmpty) 'search': query.trim(),
              if (publisher != null && publisher.trim().isNotEmpty)
                'author': publisher.trim(),
              'filter': 'gguf',
              'limit': limit.clamp(1, 50),
              if (sort != HubSort.relevance)
                'sort': sort == HubSort.downloads
                    ? 'downloads'
                    : 'lastModified',
              if (sort != HubSort.relevance) 'direction': -1,
              'full': true,
            },
          )
        : await _dio.getUri<Object?>(page);
    final raw = response.data;
    if (raw is! List) throw const FormatException('Invalid Hub model list');
    final models = raw
        .whereType<Map>()
        .map((entry) => _parseSummary(entry.cast<String, Object?>()))
        .where((model) => !model.gated)
        .toList(growable: false);
    return HubSearchPage(
      models: models,
      nextUrl: _nextLink(response.headers.value('link')),
    );
  }

  @override
  Future<List<GgufVariant>> resolveGgufArtifacts({
    required String repository,
    required String revision,
  }) async {
    _validateRepository(repository);
    _validateRevision(revision);
    final encodedRepository = repository
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');
    final response = await _dio.get<Object?>(
      '/api/models/$encodedRepository/revision/${Uri.encodeComponent(revision)}',
      queryParameters: const {'blobs': true},
    );
    final raw = response.data;
    if (raw is! Map) throw const FormatException('Invalid Hub repository');
    final map = raw.cast<String, Object?>();
    if (map['gated'] == true || map['private'] == true) {
      throw const ModelHubAccessException('Only public models are supported');
    }
    final resolvedRevision = map['sha'] as String? ?? revision;
    _validateRevision(resolvedRevision);
    final siblings = map['siblings'];
    if (siblings is! List) return const [];
    final files = siblings
        .whereType<Map>()
        .map((entry) => _parseFile(entry.cast<String, Object?>()))
        .where((file) => file.name.toLowerCase().endsWith('.gguf'))
        .toList();
    return _groupVariants(repository, resolvedRevision, files);
  }

  HubModelSummary _parseSummary(Map<String, Object?> json) {
    final id = (json['id'] ?? json['modelId']) as String?;
    final revision = json['sha'] as String?;
    if (id == null || revision == null) {
      throw const FormatException('Hub model is missing identity');
    }
    _validateRepository(id);
    _validateRevision(revision);
    final cardData = json['cardData'] is Map
        ? (json['cardData'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final safetensors = json['safetensors'] is Map
        ? (json['safetensors'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    return HubModelSummary(
      id: id,
      revision: revision,
      author: json['author'] as String?,
      license: (cardData['license'] ?? json['license']) as String?,
      parameterCount: _asInt(safetensors['total'] ?? json['numParameters']),
      downloads: _asInt(json['downloads']) ?? 0,
      lastModified: DateTime.tryParse(json['lastModified'] as String? ?? ''),
      gated: json['gated'] == true || json['private'] == true,
      tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }

  GgufFile _parseFile(Map<String, Object?> json) {
    final name = json['rfilename'] as String? ?? json['path'] as String?;
    if (name == null || name.contains('..') || name.startsWith('/')) {
      throw const FormatException('Unsafe Hub file name');
    }
    final lfs = json['lfs'] is Map
        ? (json['lfs'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final split = RegExp(
      r'-(\d{5})-of-(\d{5})\.gguf$',
      caseSensitive: false,
    ).firstMatch(name);
    final oid = (lfs['sha256'] ?? lfs['oid']) as String?;
    return GgufFile(
      name: name,
      sizeBytes: _asInt(lfs['size'] ?? json['size']),
      sha256: oid?.replaceFirst('sha256:', ''),
      etag: json['blobId'] as String?,
      shardIndex: split == null ? null : int.parse(split.group(1)!) - 1,
      shardCount: split == null ? null : int.parse(split.group(2)!),
    );
  }

  List<GgufVariant> _groupVariants(
    String repository,
    String revision,
    List<GgufFile> files,
  ) {
    final groups = <String, List<GgufFile>>{};
    for (final file in files) {
      final key = file.shardCount == null
          ? file.name
          : file.name.replaceFirst(
              RegExp(r'-\d{5}-of-\d{5}(?=\.gguf$)', caseSensitive: false),
              '',
            );
      groups.putIfAbsent(key, () => []).add(file);
    }
    final variants = <GgufVariant>[];
    for (final entry in groups.entries) {
      final group = entry.value
        ..sort((a, b) => (a.shardIndex ?? 0).compareTo(b.shardIndex ?? 0));
      final expected = group.first.shardCount;
      if (expected != null &&
          (expected <= 0 ||
              group.length != expected ||
              group.any(
                (file) =>
                    file.shardCount != expected ||
                    file.shardIndex == null ||
                    file.shardIndex! < 0 ||
                    file.shardIndex! >= expected,
              ) ||
              group.map((file) => file.shardIndex).toSet().length !=
                  expected)) {
        continue;
      }
      variants.add(
        GgufVariant(
          repository: repository,
          revision: revision,
          displayName: entry.key.replaceFirst(
            RegExp(r'\.gguf$', caseSensitive: false),
            '',
          ),
          quantization: _quantization(entry.key),
          files: List.unmodifiable(group),
        ),
      );
    }
    variants.sort(
      (a, b) => (a.totalBytes ?? 1 << 62).compareTo(b.totalBytes ?? 1 << 62),
    );
    return List.unmodifiable(variants);
  }

  String? _quantization(String name) => RegExp(
    r'(?:^|[-_.])(IQ\d(?:_[A-Z0-9]+)?|Q\d(?:_[A-Z0-9]+)+)(?:[-_.]|$)',
    caseSensitive: false,
  ).firstMatch(name)?.group(1)?.toUpperCase();

  int? _asInt(Object? value) => switch (value) {
    int number => number,
    num number => number.toInt(),
    String text => int.tryParse(text),
    _ => null,
  };

  Uri? _nextLink(String? link) {
    if (link == null) return null;
    for (final part in link.split(',')) {
      if (!part.contains('rel="next"')) continue;
      final match = RegExp(r'<([^>]+)>').firstMatch(part);
      final uri = match == null ? null : Uri.tryParse(match.group(1)!);
      if (uri != null &&
          uri.scheme == 'https' &&
          uri.host == 'huggingface.co') {
        return uri;
      }
    }
    return null;
  }

  void _validateRepository(String repository) {
    if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repository)) {
      throw const FormatException('Invalid Hub repository identity');
    }
  }

  void _validateRevision(String revision) {
    if (!RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(revision)) {
      throw const FormatException('Hub revision must be an immutable commit');
    }
  }

  void _validatePageUri(Uri page) {
    if (page.scheme != 'https' ||
        page.host != 'huggingface.co' ||
        page.userInfo.isNotEmpty ||
        page.path != '/api/models') {
      throw const FormatException('Unsafe Hub pagination target');
    }
  }
}

class ModelHubAccessException implements Exception {
  const ModelHubAccessException(this.message);
  final String message;
  @override
  String toString() => message;
}
