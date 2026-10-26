import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/runtime_profile.dart';
import 'package:vitalis_app/providers/generation_provider.dart';
import 'package:vitalis_app/services/chat_state_controller.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';
import 'package:vitalis_app/services/model_warmup_service.dart';
import 'package:vitalis_app/widgets/message_bubble.dart';
import 'package:vitalis_app/widgets/response_frame_observer.dart';

void main() {
  testWidgets(
    'real native response identity reaches a painted MessageBubble',
    (tester) async {
      final fixture = await tester.runAsync(() async {
        final path = Platform.environment['VITALIS_TEST_MODEL'] ?? '';
        expect(
          path,
          isNotEmpty,
          reason: 'Verified native fixture is mandatory',
        );
        expect(
          (await sha256.bind(File(path).openRead()).first).toString(),
          BundledModelManifest.sha256,
        );
        final repository = LlamaCppChatRepository.withModelPath(
          path,
          contextSize: 2048,
          batchSize: 128,
          threads: 2,
          supportsThinkingControl: true,
        );
        final provider = GenerationProvider(
          controller: ChatStateController(sentinel: _SafeHostTelemetry()),
          warmup: _FixtureWarmup(repository),
        );
        return (repository, provider);
      });
      expect(tester.takeException(), isNull);
      expect(fixture, isNotNull);
      final (repository, provider) = fixture!;
      addTearDown(() async {
        await tester.runAsync(() async {
          await provider.close();
          await repository.close();
        });
      });
      final response = await tester.runAsync(() async {
        final completed = Completer<String>();
        provider.onGenerationComplete = completed.complete;
        provider.onError = (code) {
          if (!completed.isCompleted) completed.completeError(StateError(code));
        };
        await provider.startGeneration(
          messages: [
            Message(
              chatId: 1,
              role: MessageRole.user,
              content: 'Reply briefly with READY.',
            ),
          ],
          settings: ModelSettings(
            maxTokens: 16,
            temperature: 0,
            contextSizeOverride: 2048,
          ),
        );
        return completed.future.timeout(const Duration(minutes: 3));
      });
      expect(tester.takeException(), isNull);
      expect(response, isNotNull);
      final output = response!;
      expect(output.trim(), isNotEmpty);
      final helper = provider.lastMetrics!.outputTiming!;
      final received = provider.lastResponseFrameTiming!;
      expect(received.nativeRequestId, helper.requestId);
      expect(received.firstReceivedTextMicros, isNotNull);
      expect(received.firstRenderedFrameMicros, isNull);
      expect(
        helper.firstSampledTokenMicros!,
        lessThanOrEqualTo(helper.firstEmittedTextMicros!),
      );
      final identity = provider.responseFrameIdentity!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResponseFrameObserver(
              responseIdentity: identity,
              onFrame: provider.recordResponseFrame,
              child: MessageBubble(
                message: Message(
                  chatId: 1,
                  role: MessageRole.assistant,
                  content: output,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(MessageBubble), findsOneWidget);
      final rendered = provider.lastResponseFrameTiming!;
      expect(rendered.nativeRequestId, helper.requestId);
      expect(
        rendered.firstRenderedFrameMicros!,
        greaterThanOrEqualTo(rendered.firstReceivedTextMicros!),
      );
      await tester.pump();
      expect(
        provider.lastResponseFrameTiming!.firstRenderedFrameMicros,
        rendered.firstRenderedFrameMicros,
      );
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

/// This is an injected safe host fixture, not physical sensor evidence.
final class _SafeHostTelemetry implements HardwareSentinelService {
  @override
  String? unsafeReasonHeavy() => null;
  @override
  bool isSafeForHeavyOperation() => true;
  @override
  Stream<bool> get onHealthChanged =>
      Stream<bool>.multi((_) {}, isBroadcast: true);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected host telemetry call: ${invocation.memberName}',
  );
}

final class _FixtureWarmup implements ModelWarmupService {
  _FixtureWarmup(this.repository);
  final LlamaCppChatRepository repository;
  @override
  bool get requiresRecovery => false;
  @override
  Future<void> cancelTuning() async {}
  @override
  void scheduleAutoTune(ModelSettings settings) {}
  @override
  Future<RuntimeProfile> resolveProfile(ModelSettings settings) async =>
      const RuntimeProfile(
        contextSize: 2048,
        reservedOutputTokens: 16,
        generationThreads: 2,
        promptThreads: 2,
        batchSize: 128,
        gpuLayers: 0,
        thinkingMode: ThinkingMode.off,
      );
  @override
  Future<LlamaCppChatRepository> ensureProfile(
    RuntimeProfile profile, {
    required String modelId,
  }) async {
    await repository.prepare();
    return repository;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected warmup fixture call: ${invocation.memberName}',
  );
}
