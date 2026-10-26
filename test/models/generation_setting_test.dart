import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/generation_setting.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/model_defaults.dart';

void main() {
  final valid = <GenerationSetting, List<String>>{
    GenerationSetting.temperature: ['0', '-1', '3', '1e-4'],
    GenerationSetting.topP: ['0', '0.5', '1'],
    GenerationSetting.topK: ['0', '-1', '256', '2147483647', '-2147483648'],
    GenerationSetting.maxTokens: ['1', '8192', '9223372036854775807'],
  };
  for (final entry in valid.entries) {
    for (final value in entry.value) {
      test('${entry.key.name} accepts native-compatible $value', () {
        final original = ModelSettings(modelId: 'fixture');
        expect(entry.key.validate(value), isNull);
        final updated = entry.key.apply(original, value);
        expect(updated.modelId, 'fixture');
        expect(updated.systemPrompt, original.systemPrompt);
        expect(num.parse(entry.key.valueOf(updated)), num.parse(value));
      });
    }
  }
  final invalid = <GenerationSetting, List<String>>{
    GenerationSetting.temperature: [
      'NaN',
      'Infinity',
      '-Infinity',
      '1e300',
      '',
    ],
    GenerationSetting.topP: ['NaN', '-0.01', '1.01', '1e300', 'bad'],
    GenerationSetting.topK: ['2147483648', '-2147483649', '1.5', '0x10', 'bad'],
    GenerationSetting.maxTokens: [
      '0',
      '-1',
      '1.5',
      '9223372036854775808',
      'bad',
    ],
  };
  for (final entry in invalid.entries) {
    for (final value in entry.value) {
      test(
        '${entry.key.name} rejects unsupported $value without changing a record',
        () {
          final original = ModelSettings();
          expect(entry.key.validate(value), isNotNull);
          expect(
            () => entry.key.apply(original, value),
            throwsA(anyOf(isA<FormatException>(), isA<ArgumentError>())),
          );
          expect(original.maxTokens, ModelDefaults.maximumOutputTokens);
        },
      );
    }
  }
  test('repairing one field preserves unrelated stored settings', () {
    final original = ModelSettings(temperature: double.nan, maxTokens: 8192);
    final repaired = GenerationSetting.topK.apply(original, ' 256 ');
    expect(repaired.topK, 256);
    expect(repaired.temperature.isNaN, isTrue);
    expect(repaired.maxTokens, 8192);
  });
  test(
    'output presets derive from the single default and do not limit custom output',
    () {
      expect(GenerationSettingsPresentationPolicy.outputPresets, [
        '${ModelDefaults.maximumOutputTokens ~/ 4}',
        '${ModelDefaults.maximumOutputTokens}',
        '${ModelDefaults.maximumOutputTokens * 2}',
      ]);
      expect(
        GenerationSetting.maxTokens.validate(
          '${ModelDefaults.maximumOutputTokens * 4}',
        ),
        isNull,
      );
    },
  );
}
