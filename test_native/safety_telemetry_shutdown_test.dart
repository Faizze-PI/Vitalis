import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/models/bundled_model_manifest.dart';
import 'package:vitalis_app/services/chat_state_controller.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final failDuringText in [false, true]) {
    test(
      'failed watchdog stops native decoding (during text: $failDuringText)',
      () async {
        final path = Platform.environment['VITALIS_TEST_MODEL'];
        expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
        expect(
          (await sha256.bind(File(path!).openRead()).first).toString(),
          BundledModelManifest.sha256,
        );
        final repository = _ObservedRepository(path);
        final sentinel = _Sentinel();
        var scheduled = 0;
        var failNextTimer = false;
        var monitoringFailed = false;
        final controller = ChatStateController(
          sentinel: sentinel,
          watchdogTimerFactory: (duration, action) {
            if (++scheduled == 3 && !failDuringText || failNextTimer) {
              failNextTimer = false;
              monitoringFailed = true;
              throw StateError('private/watchdog/path failure');
            }
            return Timer(duration, action);
          },
        );
        addTearDown(() async {
          await controller.close();
          await repository.close();
          await sentinel.health.close();
        });
        await repository.prepare();
        var visibleAfterFailure = 0;
        var visibleChunks = 0;
        var completions = 0;
        final errors = <String>[];
        controller.onToken = (text) {
          if (monitoringFailed) visibleAfterFailure++;
          if (text.isNotEmpty) {
            visibleChunks++;
            if (failDuringText) failNextTimer = true;
          }
        };
        controller.onComplete = () => completions++;
        controller.onError = errors.add;
        await controller.startGeneration(
          repository: repository,
          messages: [
            LLMMessage(
              role: LLMRole.user,
              content:
                  'Write a long detailed numbered list of harmless household objects.',
            ),
          ],
          options: const GenerationOptions(maxTokens: 512),
        );
        // Only the injected scheduler failure can initiate this observed Stop.
        await repository.stopRequested.future;
        await controller.cancelInference();
        expect(monitoringFailed, isTrue);
        expect(visibleChunks, failDuringText ? greaterThan(0) : 0);
        expect(visibleAfterFailure, 0);
        expect(completions, 0);
        expect(errors.single, 'Generation monitoring became unavailable.');
        expect(repository.lastMetrics?.completionReason, 'cancelled');
        expect(
          repository.lastMetrics?.cancellationAcknowledgementMicros,
          isNotNull,
        );
        expect(repository.operationSnapshot.hasNativeWork, isFalse);
        expect(controller.cleanupFailed, isFalse);
        await controller.close();
        await for (final _ in repository.streamChatWithGenerationOptions(
          'after-watchdog-failure',
          messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
          generationOptions: const GenerationOptions(maxTokens: 16),
        )) {}
        expect(repository.lastMetrics?.generatedTokens, greaterThan(0));
        expect(repository.lastMetrics?.completionReason, isNot('cancelled'));
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }
  for (final streamCloses in [false, true]) {
    test(
      'lost telemetry stops native decoding (stream closes: $streamCloses)',
      () async {
        final path = Platform.environment['VITALIS_TEST_MODEL'];
        expect(path, isNotNull, reason: 'VITALIS_TEST_MODEL is mandatory');
        expect(
          (await sha256.bind(File(path!).openRead()).first).toString(),
          BundledModelManifest.sha256,
        );
        final repository = _ObservedRepository(path);
        final sentinel = _Sentinel();
        final controller = ChatStateController(sentinel: sentinel);
        addTearDown(() async {
          await controller.close();
          await repository.close();
          await sentinel.health.close();
        });
        await repository.prepare();
        final firstText = Completer<void>();
        var visibleAfterStop = 0;
        var observationLost = false;
        var completions = 0;
        final errors = <String>[];
        controller.onToken = (text) {
          if (observationLost) visibleAfterStop++;
          if (text.isNotEmpty && !firstText.isCompleted) firstText.complete();
        };
        controller.onComplete = () => completions++;
        controller.onError = errors.add;
        await controller.startGeneration(
          repository: repository,
          messages: [
            LLMMessage(
              role: LLMRole.user,
              content:
                  'Write a long detailed numbered list of harmless household objects.',
            ),
          ],
          options: const GenerationOptions(maxTokens: 512),
        );
        await firstText.future;
        expect(repository.stopRequested.isCompleted, isFalse);
        observationLost = true;
        if (streamCloses) {
          await sentinel.health.close();
        } else {
          sentinel.health.addError(StateError('private/sensor/path failure'));
        }
        // Prove the telemetry event requests Stop before any test-initiated Stop.
        await repository.stopRequested.future;
        await controller.cancelInference();
        expect(repository.lastMetrics?.completionReason, 'cancelled');
        expect(
          repository.lastMetrics?.cancellationAcknowledgementMicros,
          isNotNull,
        );
        expect(repository.operationSnapshot.hasNativeWork, isFalse);
        expect(controller.status, ChatStatus.error);
        expect(controller.cleanupFailed, isFalse);
        expect(visibleAfterStop, 0);
        expect(completions, 0);
        expect(errors.single, 'Safety telemetry became unavailable.');
        await controller.close();
        await for (final _ in repository.streamChatWithGenerationOptions(
          'after-telemetry-stop',
          messages: [LLMMessage(role: LLMRole.user, content: 'Say hello.')],
          generationOptions: const GenerationOptions(maxTokens: 16),
        )) {}
        expect(repository.lastMetrics?.generatedTokens, greaterThan(0));
        expect(repository.lastMetrics?.completionReason, isNot('cancelled'));
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }
}

class _ObservedRepository extends LlamaCppChatRepository {
  _ObservedRepository(String path)
    : super.withModelPath(path, contextSize: 2048, batchSize: 128, threads: 2);
  final stopRequested = Completer<void>();
  @override
  Future<void> cancelActiveInference() {
    if (!stopRequested.isCompleted) stopRequested.complete();
    return super.cancelActiveInference();
  }
}

class _Sentinel implements HardwareSentinelService {
  final health = StreamController<bool>.broadcast(sync: true);
  @override
  Stream<bool> get onHealthChanged => health.stream;
  @override
  String? unsafeReasonHeavy() => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
