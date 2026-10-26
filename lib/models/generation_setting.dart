import 'package:llm_llamacpp/llm_llamacpp.dart' show GenerationOptions;
import '../constants/app_strings.dart';
import 'model_defaults.dart';
import 'model_settings.dart';

/// Convenient requested lengths, not context, allocation or native limits.
abstract final class GenerationSettingsPresentationPolicy {
  static const shortOutputDivisor = 4; // hardcode: HC-075
  static const longOutputMultiplier = 2; // hardcode: HC-075
  static List<String> get outputPresets => [
    '${ModelDefaults.maximumOutputTokens ~/ shortOutputDivisor}',
    '${ModelDefaults.maximumOutputTokens}',
    '${ModelDefaults.maximumOutputTokens * longOutputMultiplier}',
  ];
}

enum GenerationSetting {
  temperature,
  topP,
  topK,
  maxTokens;

  String get label => switch (this) {
    temperature => AppStrings.temperatureLabel,
    topP => AppStrings.topPLabel,
    topK => AppStrings.topKLabel,
    maxTokens => AppStrings.maxTokensLabel,
  };
  bool get isInteger => this == topK || this == maxTokens;
  String get description => switch (this) {
    temperature =>
      'Higher values make replies less predictable. Finite native-compatible values are supported.',
    topP => 'Probability cutoff, from zero to one.',
    topK =>
      'Number of token candidates to consider. Zero disables this filter.',
    maxTokens =>
      'Requested maximum output. The context planner reduces it to the remaining context for each message. Presets are shortcuts, not limits.',
  };
  String valueOf(ModelSettings settings) => switch (this) {
    temperature => settings.temperature.toString(),
    topP => settings.topP.toString(),
    topK => settings.topK.toString(),
    maxTokens => settings.maxTokens.toString(),
  };

  GenerationOptions _options(String input) {
    final text = input.trim();
    final integer = isInteger ? int.tryParse(text, radix: 10) : null;
    final decimal = !isInteger ? double.tryParse(text) : null;
    if ((isInteger && integer == null) || (!isInteger && decimal == null)) {
      throw const FormatException('Not a number');
    }
    final options = switch (this) {
      temperature => GenerationOptions(temperature: decimal!),
      topP => GenerationOptions(topP: decimal!),
      topK => GenerationOptions(topK: integer!),
      maxTokens => GenerationOptions(maxTokens: integer!),
    };
    // Reuse the native ABI/probability authority; do not duplicate its ceilings.
    options.validate();
    return options;
  }

  String? validate(String input) {
    try {
      _options(input);
      return null;
    } on FormatException {
      return isInteger ? 'Enter a whole number.' : 'Enter a number.';
    } on ArgumentError {
      return switch (this) {
        temperature =>
          'Enter a finite temperature supported by the native runtime.',
        topP => 'Enter a probability from zero to one.',
        topK => 'Enter a whole number supported by the native runtime.',
        maxTokens => 'Enter a whole number greater than zero.',
      };
    }
  }

  ModelSettings apply(ModelSettings current, String input) {
    final options = _options(input);
    return switch (this) {
      temperature => current.copyWith(temperature: options.temperature),
      topP => current.copyWith(topP: options.topP),
      topK => current.copyWith(topK: options.topK),
      maxTokens => current.copyWith(maxTokens: options.maxTokens),
    };
  }
}
