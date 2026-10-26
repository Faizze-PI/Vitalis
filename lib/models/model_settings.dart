import 'dart:convert';

import 'bundled_model_manifest.dart';
import 'model_defaults.dart';

enum TuningMode { automatic, advanced }

enum AccelerationPreference { cpu, experimentalGpu }

enum ThinkingMode { off, on }

class ModelSettings {
  final double temperature;
  final int topK;
  final double topP;
  final int maxTokens;
  final String systemPrompt;
  final String modelId;
  final TuningMode tuningMode;
  final ThinkingMode thinkingMode;
  final AccelerationPreference accelerationPreference;
  final int? contextSizeOverride;
  final int? generationThreadsOverride;
  final int? promptThreadsOverride;
  final int? batchSizeOverride;

  ModelSettings({
    this.temperature = ModelDefaults.temperature,
    this.topK = ModelDefaults.topK,
    this.topP = ModelDefaults.topP,
    this.maxTokens = ModelDefaults.maximumOutputTokens,
    this.systemPrompt = ModelDefaults.systemPrompt,
    this.modelId = BundledModelManifest.id,
    this.tuningMode = TuningMode.automatic,
    this.thinkingMode = ThinkingMode.off,
    this.accelerationPreference = AccelerationPreference.cpu,
    this.contextSizeOverride,
    this.generationThreadsOverride,
    this.promptThreadsOverride,
    this.batchSizeOverride,
  });

  ModelSettings copyWith({
    double? temperature,
    int? topK,
    double? topP,
    int? maxTokens,
    String? systemPrompt,
    String? modelId,
    TuningMode? tuningMode,
    ThinkingMode? thinkingMode,
    AccelerationPreference? accelerationPreference,
    int? contextSizeOverride,
    int? generationThreadsOverride,
    int? promptThreadsOverride,
    int? batchSizeOverride,
    bool clearContextSizeOverride = false,
    bool clearThreadOverrides = false,
    bool clearBatchSizeOverride = false,
  }) {
    return ModelSettings(
      temperature: temperature ?? this.temperature,
      topK: topK ?? this.topK,
      topP: topP ?? this.topP,
      maxTokens: maxTokens ?? this.maxTokens,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      modelId: modelId ?? this.modelId,
      tuningMode: tuningMode ?? this.tuningMode,
      thinkingMode: thinkingMode ?? this.thinkingMode,
      accelerationPreference:
          accelerationPreference ?? this.accelerationPreference,
      contextSizeOverride: clearContextSizeOverride
          ? null
          : contextSizeOverride ?? this.contextSizeOverride,
      generationThreadsOverride: clearThreadOverrides
          ? null
          : generationThreadsOverride ?? this.generationThreadsOverride,
      promptThreadsOverride: clearThreadOverrides
          ? null
          : promptThreadsOverride ?? this.promptThreadsOverride,
      batchSizeOverride: clearBatchSizeOverride
          ? null
          : batchSizeOverride ?? this.batchSizeOverride,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'temperature': temperature,
      'top_k': topK,
      'top_p': topP,
      'max_tokens': maxTokens,
      'system_prompt': systemPrompt,
      'model_id': modelId,
      'tuning_mode': tuningMode.name,
      'thinking_mode': thinkingMode.name,
      'acceleration_preference': accelerationPreference.name,
      'context_size_override': contextSizeOverride,
      'generation_threads_override': generationThreadsOverride,
      'prompt_threads_override': promptThreadsOverride,
      'batch_size_override': batchSizeOverride,
    };
  }

  factory ModelSettings.fromJson(Map<String, dynamic> json) {
    return ModelSettings(
      temperature:
          (json['temperature'] as num?)?.toDouble() ??
          ModelDefaults.temperature,
      topK: json['top_k'] as int? ?? ModelDefaults.topK,
      topP: (json['top_p'] as num?)?.toDouble() ?? ModelDefaults.topP,
      maxTokens:
          json['max_tokens'] as int? ?? ModelDefaults.maximumOutputTokens,
      systemPrompt:
          json['system_prompt'] as String? ?? ModelDefaults.systemPrompt,
      modelId: json['model_id'] as String? ?? BundledModelManifest.id,
      tuningMode: _enumOrDefault(
        TuningMode.values,
        json['tuning_mode'],
        TuningMode.automatic,
      ),
      thinkingMode: _enumOrDefault(
        ThinkingMode.values,
        json['thinking_mode'],
        ThinkingMode.off,
      ),
      accelerationPreference: _enumOrDefault(
        AccelerationPreference.values,
        json['acceleration_preference'],
        AccelerationPreference.cpu,
      ),
      contextSizeOverride: json['context_size_override'] as int?,
      generationThreadsOverride: json['generation_threads_override'] as int?,
      promptThreadsOverride: json['prompt_threads_override'] as int?,
      batchSizeOverride: json['batch_size_override'] as int?,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory ModelSettings.fromJsonString(String jsonString) {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) return ModelSettings();
    return ModelSettings.fromJson(decoded);
  }
}

T _enumOrDefault<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is! String) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
