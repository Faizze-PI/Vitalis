import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/models/model_settings.dart';

void main() {
  group('ModelSettings', () {
    test('serialization round trip', () {
      final original = ModelSettings(
        temperature: 0.8,
        topK: 50,
        topP: 0.85,
        maxTokens: 1024,
        systemPrompt: 'Test prompt',
        modelId: 'local-test',
        tuningMode: TuningMode.advanced,
        thinkingMode: ThinkingMode.on,
        accelerationPreference: AccelerationPreference.experimentalGpu,
        contextSizeOverride: 12288,
        generationThreadsOverride: 6,
        promptThreadsOverride: 8,
        batchSizeOverride: 384,
      );

      final json = original.toJson();
      final restored = ModelSettings.fromJson(json);

      expect(restored.temperature, 0.8);
      expect(restored.topK, 50);
      expect(restored.topP, 0.85);
      expect(restored.maxTokens, 1024);
      expect(restored.systemPrompt, 'Test prompt');
      expect(restored.modelId, 'local-test');
      expect(restored.tuningMode, TuningMode.advanced);
      expect(restored.thinkingMode, ThinkingMode.on);
      expect(
        restored.accelerationPreference,
        AccelerationPreference.experimentalGpu,
      );
      expect(restored.contextSizeOverride, 12288);
      expect(restored.generationThreadsOverride, 6);
      expect(restored.promptThreadsOverride, 8);
      expect(restored.batchSizeOverride, 384);
    });

    test('copyWith preserves unchanged values', () {
      final original = ModelSettings(temperature: 0.5);
      final copied = original.copyWith(topK: 100);

      expect(copied.temperature, 0.5);
      expect(copied.topK, 100);
      expect(copied.topP, original.topP);
      expect(copied.maxTokens, original.maxTokens);
    });

    test('JSON string round trip', () {
      final original = ModelSettings(temperature: 0.3);
      final jsonString = original.toJsonString();
      final restored = ModelSettings.fromJsonString(jsonString);
      expect(restored.temperature, 0.3);
    });

    test('default values', () {
      final settings = ModelSettings();
      expect(settings.temperature, 0.7);
      expect(settings.topK, 40);
      expect(settings.topP, 0.9);
      expect(settings.maxTokens, 2048);
      expect(settings.systemPrompt, 'You are a helpful assistant.');
      expect(settings.thinkingMode, ThinkingMode.off);
      expect(settings.accelerationPreference, AccelerationPreference.cpu);
    });

    test('unknown persisted enum values fall back safely', () {
      final restored = ModelSettings.fromJson({
        'tuning_mode': 'future-mode',
        'thinking_mode': 'invalid',
        'acceleration_preference': 'unsupported',
      });
      expect(restored.tuningMode, TuningMode.automatic);
      expect(restored.thinkingMode, ThinkingMode.off);
      expect(restored.accelerationPreference, AccelerationPreference.cpu);
    });
  });
}
