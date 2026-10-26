import '../constants/app_constants.dart';
import 'model_descriptor.dart';
import 'model_library_policy.dart';
import 'model_settings.dart';
import 'runtime_capabilities.dart';

class RuntimeProfile {
  const RuntimeProfile({
    required this.contextSize,
    required this.reservedOutputTokens,
    required this.generationThreads,
    required this.promptThreads,
    required this.batchSize,
    required this.gpuLayers,
    required this.thinkingMode,
    this.stopSequences = const ['<|im_end|>', '<|endoftext|>'],
  });

  final int contextSize;
  final int reservedOutputTokens;
  final int generationThreads;
  final int promptThreads;
  final int batchSize;
  final int gpuLayers;
  final ThinkingMode thinkingMode;
  final List<String> stopSequences;

  RuntimeProfile copyWith({
    int? contextSize,
    int? reservedOutputTokens,
    int? generationThreads,
    int? promptThreads,
    int? batchSize,
    int? gpuLayers,
    ThinkingMode? thinkingMode,
    List<String>? stopSequences,
  }) => RuntimeProfile(
    contextSize: contextSize ?? this.contextSize,
    reservedOutputTokens: reservedOutputTokens ?? this.reservedOutputTokens,
    generationThreads: generationThreads ?? this.generationThreads,
    promptThreads: promptThreads ?? this.promptThreads,
    batchSize: batchSize ?? this.batchSize,
    gpuLayers: gpuLayers ?? this.gpuLayers,
    thinkingMode: thinkingMode ?? this.thinkingMode,
    stopSequences: stopSequences ?? this.stopSequences,
  );

  Map<String, Object?> toJson() => {
    'contextSize': contextSize,
    'reservedOutputTokens': reservedOutputTokens,
    'generationThreads': generationThreads,
    'promptThreads': promptThreads,
    'batchSize': batchSize,
    'gpuLayers': gpuLayers,
    'thinkingMode': thinkingMode.name,
    'stopSequences': stopSequences,
  };

  factory RuntimeProfile.fromJson(Map<String, Object?> json) => RuntimeProfile(
    contextSize: json['contextSize']! as int,
    reservedOutputTokens: json['reservedOutputTokens']! as int,
    generationThreads: json['generationThreads']! as int,
    promptThreads: json['promptThreads']! as int,
    batchSize: json['batchSize']! as int,
    gpuLayers: json['gpuLayers']! as int,
    thinkingMode: ThinkingMode.values.byName(json['thinkingMode']! as String),
    stopSequences: (json['stopSequences']! as List).cast<String>(),
  );

  factory RuntimeProfile.forSettings(
    ModelSettings settings, {
    required int processorCount,
    int maximumContextSize = AppConstants.nativeMaximumContextSize,
  }) {
    final availableProcessors = processorCount.clamp(1, 1024);
    final automaticThreads = (availableProcessors - 1).clamp(
      1,
      availableProcessors,
    );
    return RuntimeProfile(
      contextSize:
          (settings.contextSizeOverride ?? AppConstants.defaultContextSize)
              .clamp(AppConstants.minimumContextSize, maximumContextSize),
      reservedOutputTokens: settings.maxTokens,
      generationThreads:
          (settings.generationThreadsOverride ?? automaticThreads).clamp(
            1,
            availableProcessors,
          ),
      promptThreads: (settings.promptThreadsOverride ?? automaticThreads).clamp(
        1,
        availableProcessors,
      ),
      batchSize: (settings.batchSizeOverride ?? AppConstants.defaultBatchSize)
          .clamp(
            AppConstants.minimumBatchSize,
            AppConstants.nativeMaximumBatchSize,
          ),
      gpuLayers: 0,
      thinkingMode: settings.thinkingMode,
    );
  }

  factory RuntimeProfile.forCompatibilityProbe(
    ModelDescriptor model,
    RuntimeCapabilities capabilities,
  ) {
    final modelLimit =
        (model.contextTrain ?? AppConstants.conservativeUnknownContextSize)
            .clamp(
              AppConstants.minimumContextSize,
              AppConstants.nativeMaximumContextSize,
            );
    final memoryContextLimit = capabilities.availableMemoryBytes == null
        ? AppConstants.conservativeUnknownContextSize
        : (capabilities.availableMemoryBytes! *
                  AppConstants.contextMemoryBudgetFraction /
                  AppConstants.conservativeKvBytesPerToken)
              .floor();
    final contextSize =
        <int>[
              modelLimit,
              memoryContextLimit,
              CompatibilityProbePolicy.maximumContextTokens,
            ]
            .reduce((left, right) => left < right ? left : right)
            .clamp(
              AppConstants.minimumContextSize,
              CompatibilityProbePolicy.maximumContextTokens,
            );
    final knownTopology = capabilities.performanceProcessors;
    final threads = (knownTopology ?? 1).clamp(
      1,
      <int>[
        capabilities.logicalProcessors,
        CompatibilityProbePolicy.maximumThreads,
      ].reduce((left, right) => left < right ? left : right),
    );
    final knownSafe =
        capabilities.hasKnownSafeTelemetry && !capabilities.isSevere;
    return RuntimeProfile(
      contextSize: contextSize,
      reservedOutputTokens: CompatibilityProbePolicy.reservedOutputTokens,
      generationThreads: threads,
      promptThreads: threads,
      batchSize: knownSafe
          ? CompatibilityProbePolicy.knownSafeBatchSize
          : CompatibilityProbePolicy.conservativeBatchSize,
      gpuLayers: 0,
      thinkingMode: ThinkingMode.off,
    );
  }
}
