import 'dart:typed_data';

class NativeSamplingLimits {
  // Locked llama.h uses int32_t K and uint32_t seed.
  static const integerBits = 32; // hardcode: HC-074
}

/// Options for controlling text generation behavior.
///
/// Example:
/// ```dart
/// final options = GenerationOptions(
///   temperature: 0.8,
///   topP: 0.95,
///   maxTokens: 1024,
/// );
///
/// final stream = repo.streamChat('model', messages: messages, options: options);
/// ```
class GenerationOptions {
  /// Creates generation options with the specified parameters.
  ///
  /// [temperature] - Controls randomness (0.0 = deterministic, higher = more random).
  ///                 Default is 0.7.
  /// [topP] - Nucleus sampling: consider only tokens with cumulative probability
  ///          up to this value. Default is 0.9.
  /// [topK] - Consider only the top K most likely tokens. Default is 40.
  /// [maxTokens] - Maximum number of tokens to generate. Default is 2048.
  /// [seed] - Random seed for reproducible outputs. If null, uses random seed.
  ///          Default is null.
  /// [repeatPenalty] - Penalty for repeating tokens. Values > 1.0 discourage
  ///                   repetition. Default is null (no penalty).
  /// [frequencyPenalty] - Penalty based on token frequency. Default is null.
  /// [presencePenalty] - Penalty for presence of tokens. Default is null.
  const GenerationOptions({
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
    this.maxTokens = 2048,
    this.seed,
    this.repeatPenalty,
    this.frequencyPenalty,
    this.presencePenalty,
  });

  /// Controls randomness (0.0 = deterministic, higher = more random).
  final double temperature;

  /// Nucleus sampling threshold (0.0 to 1.0).
  final double topP;

  /// Top-K sampling limit.
  final int topK;

  /// Maximum number of tokens to generate.
  final int maxTokens;

  /// Random seed for reproducible outputs. If null, uses random seed.
  final int? seed;

  /// Penalty for repeating tokens (values > 1.0 discourage repetition).
  final double? repeatPenalty;

  /// Native additive penalty per occurrence: zero disables; positive values
  /// discourage repetition and negative values encourage it.
  final double? frequencyPenalty;

  /// Native additive penalty for a previously seen token: zero disables;
  /// positive values discourage repetition and negative values encourage it.
  final double? presencePenalty;

  /// Validate before reserving the runtime or allocating a native sampler.
  void validate() {
    validatePenalties();
    _checkNativeFloat('temperature', temperature);
    _checkNativeFloat('topP', topP);
    if (topP < 0 || topP > 1) {
      throw ArgumentError('topP must be between zero and one');
    }
    if (topK != topK.toSigned(NativeSamplingLimits.integerBits)) {
      throw ArgumentError('topK must fit native int32');
    }
    final selectedSeed = seed;
    if (selectedSeed != null &&
        selectedSeed !=
            selectedSeed.toUnsigned(NativeSamplingLimits.integerBits)) {
      throw ArgumentError('seed must fit native uint32');
    }
    if (maxTokens <= 0) throw ArgumentError('maxTokens must be positive');
  }

  /// Reject values that cannot safely reach llama.cpp's float parameters.
  void validatePenalties() {
    _checkNativeFloat('repeatPenalty', repeatPenalty, positive: true);
    _checkNativeFloat('frequencyPenalty', frequencyPenalty);
    _checkNativeFloat('presencePenalty', presencePenalty);
  }

  static void _checkNativeFloat(
    String name,
    double? value, {
    bool positive = false,
  }) {
    if (value == null) return;
    final nativeValue = Float32List.fromList([value]).single;
    if (!value.isFinite ||
        !nativeValue.isFinite ||
        (positive && nativeValue <= 0)) {
      throw ArgumentError(
        '$name must be a finite native float'
        '${positive ? ' greater than zero' : ''}',
      );
    }
  }

  /// Creates a copy with modified values.
  GenerationOptions copyWith({
    double? temperature,
    double? topP,
    int? topK,
    int? maxTokens,
    int? seed,
    double? repeatPenalty,
    double? frequencyPenalty,
    double? presencePenalty,
  }) {
    return GenerationOptions(
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      maxTokens: maxTokens ?? this.maxTokens,
      seed: seed ?? this.seed,
      repeatPenalty: repeatPenalty ?? this.repeatPenalty,
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
    );
  }

  @override
  String toString() {
    return 'GenerationOptions('
        'temperature: $temperature, '
        'topP: $topP, '
        'topK: $topK, '
        'maxTokens: $maxTokens, '
        'seed: $seed'
        ')';
  }
}
