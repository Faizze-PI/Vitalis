import 'model_library_policy.dart';
import 'package:llm_llamacpp/src/verified_thinking_templates.dart';

class ModelDescriptor {
  const ModelDescriptor({
    required this.id,
    required this.displayName,
    required this.source,
    required this.compatibilityStatus,
    this.localPath,
    this.sha256,
    this.byteSize,
    this.architecture,
    this.tokenizer,
    this.contextTrain,
    this.chatTemplate,
    this.blockCount,
    this.supportsThinking = false,
    this.installedAt,
    this.repository,
    this.revision,
    this.quantization,
    this.parameterCount,
    this.license,
    this.remoteMetadataJson,
    this.installationState = 'not_installed',
    this.lastUsedAt,
    this.updateRevision,
  });

  final String id;
  final String displayName;
  final String source;
  final String compatibilityStatus;
  final String? localPath;
  final String? sha256;
  final int? byteSize;
  final String? architecture;
  final String? tokenizer;
  final int? contextTrain;
  final String? chatTemplate;
  final int? blockCount;
  final bool supportsThinking;
  final DateTime? installedAt;
  final String? repository;
  final String? revision;
  final String? quantization;
  final int? parameterCount;
  final String? license;
  final String? remoteMetadataJson;
  final String installationState;
  final DateTime? lastUsedAt;
  final String? updateRevision;

  bool get isInstalled =>
      installationState == 'installed' && localPath != null && sha256 != null;

  bool get isLargeModel =>
      parameterCount != null &&
      parameterCount! > ModelLibraryPolicy.largeModelParameterThreshold;

  Map<String, Object?> toMap() => {
    'id': id,
    'display_name': displayName,
    'local_path': localPath,
    'source': source,
    'sha256': sha256,
    'byte_size': byteSize,
    'architecture': architecture,
    'tokenizer': tokenizer,
    'context_train': contextTrain,
    'chat_template': chatTemplate,
    'block_count': blockCount,
    'supports_thinking': supportsThinking ? 1 : 0,
    'compatibility_status': compatibilityStatus,
    'installed_at': installedAt?.toIso8601String(),
    'repository': repository,
    'revision': revision,
    'quantization': quantization,
    'parameter_count': parameterCount,
    'license': license,
    'remote_metadata_json': remoteMetadataJson,
    'installation_state': installationState,
    'last_used_at': lastUsedAt?.toIso8601String(),
    'update_revision': updateRevision,
  };

  factory ModelDescriptor.fromMap(Map<String, Object?> map) => ModelDescriptor(
    id: map['id']! as String,
    displayName: map['display_name']! as String,
    localPath: map['local_path'] as String?,
    source: map['source']! as String,
    sha256: map['sha256'] as String?,
    byteSize: map['byte_size'] as int?,
    architecture: map['architecture'] as String?,
    tokenizer: map['tokenizer'] as String?,
    contextTrain: map['context_train'] as int?,
    chatTemplate: map['chat_template'] as String?,
    blockCount: map['block_count'] as int?,
    supportsThinking:
        (map['supports_thinking'] as int? ?? 0) == 1 &&
        VerifiedThinkingTemplates.supports(map['chat_template'] as String?),
    compatibilityStatus: map['compatibility_status']! as String,
    installedAt: map['installed_at'] == null
        ? null
        : DateTime.parse(map['installed_at']! as String),
    repository: map['repository'] as String?,
    revision: map['revision'] as String?,
    quantization: map['quantization'] as String?,
    parameterCount: map['parameter_count'] as int?,
    license: map['license'] as String?,
    remoteMetadataJson: map['remote_metadata_json'] as String?,
    installationState:
        map['installation_state'] as String? ??
        (map['local_path'] == null ? 'not_installed' : 'installed'),
    lastUsedAt: map['last_used_at'] == null
        ? null
        : DateTime.parse(map['last_used_at']! as String),
    updateRevision: map['update_revision'] as String?,
  );
}
