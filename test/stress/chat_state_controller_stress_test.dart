import 'dart:async';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/services/chat_state_controller.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';

class _MockSentinel implements HardwareSentinelService {
  @override
  int get currentLevel => 100;
  @override
  bool get isCharging => true;
  @override
  bool get isInSaveMode => false;
  @override
  bool get isDisposed => false;
  @override
  ConnectivityResult get connectivityType => ConnectivityResult.wifi;
  @override
  int get memoryPressureLevel => 0;
  @override
  bool isSafeForHeavyOperation() => true;
  @override
  bool isSafeForDownload() => true;
  @override
  String? unsafeReasonHeavy() => null;
  @override
  String? unsafeReasonDownload() => null;
  @override
  void checkHeavyOperation() {}
  @override
  void checkDownload() {}
  @override
  Stream<bool> get onHealthChanged =>
      Stream<bool>.multi((_) {}, isBroadcast: true);
  @override
  Future<void> init() async {}
  @override
  void dispose() {}
}

void main() {
  const seed = int.fromEnvironment(
    'VITALIS_LIFECYCLE_STRESS_SEED',
    defaultValue: 20261011,
  );
  group('ChatStateController stress (tier 2)', () {
    test(
      '100 generation/completion and acknowledged Stop cycles (seed $seed)',
      () async {
        final ctrl = ChatStateController(sentinel: _MockSentinel());
        final random = Random(seed);
        var completed = 0;
        var cancelled = 0;
        addTearDown(ctrl.close);
        for (var cycle = 0; cycle < 100; cycle++) {
          final repository = _CycleRepository();
          final visible = Completer<void>();
          final text = <String>[];
          var completions = 0;
          ctrl.onToken = (token) {
            text.add(token);
            if (!visible.isCompleted) visible.complete();
          };
          ctrl.onComplete = () => completions++;
          ctrl.onError = (error) => fail('Unexpected cycle error: $error');
          try {
            await ctrl.startGeneration(
              repository: repository,
              messages: [LLMMessage(role: LLMRole.user, content: 'fixture')],
              options: const GenerationOptions(maxTokens: 8),
            );
            expect(ctrl.status, ChatStatus.generating);
            repository.addText('visible-$cycle');
            await visible.future;
            if (random.nextBool()) {
              final stopping = ctrl.cancelInference();
              expect(ctrl.cancelInference(), same(stopping));
              await repository.cancellationStarted.future;
              expect(ctrl.status, ChatStatus.interrupting);
              expect(repository.operationSnapshot.hasNativeWork, isTrue);
              repository.addText('late-$cycle');
              repository.acknowledgeCancellation();
              await stopping;
              expect(repository.cancelCalls, 1);
              expect(completions, 0);
              cancelled++;
            } else {
              await repository.complete();
              expect(completions, 1);
              expect(repository.cancelCalls, 0);
              completed++;
            }
            expect(text, ['visible-$cycle']);
            expect(repository.operationSnapshot.hasNativeWork, isFalse);
          } finally {
            repository.acknowledgeCancellation();
            await ctrl.cancelInference();
            await repository.complete();
          }
          expect(ctrl.status, ChatStatus.idle);
        }
        expect(completed, greaterThan(0));
        expect(cancelled, greaterThan(0));
        expect(completed + cancelled, 100);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      '10K idle cancels do not start work and shutdown settles',
      () async {
        final ctrl = ChatStateController(sentinel: _MockSentinel());
        for (int i = 0; i < 10000; i++) {
          ctrl.cancel();
        }
        expect(ctrl.status, ChatStatus.idle);
        await ctrl.close();
        expect(ctrl.cleanupFailed, isFalse);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test('repeated dispose shares acknowledged shutdown', () async {
      final ctrl = ChatStateController(sentinel: _MockSentinel());
      ctrl.dispose();
      expect(ctrl.isDisposed, true);
      final closing = ctrl.close();
      ctrl.dispose();
      expect(ctrl.close(), same(closing));
      await closing;
      expect(ctrl.isDisposed, true);
      expect(ctrl.cleanupFailed, isFalse);
    });
  });
}

/// Controlled native-event adapter: tests controller races, not native decoding.
class _CycleRepository implements LlamaCppChatRepository {
  final _chunks = StreamController<LLMChunk>();
  final cancellationStarted = Completer<void>();
  final _acknowledgement = Completer<void>();
  bool _working = false;
  int cancelCalls = 0;

  @override
  LlamaCppInferenceMetrics? get lastMetrics => null;

  @override
  RuntimeOperationSnapshot get operationSnapshot => RuntimeOperationSnapshot(
    state: RuntimeReservationState.idle,
    kind: RuntimeOperationKind.interactive,
    ownerId: 1,
    contextOwnerId: 1,
    hasRetainedContext: true,
    sessionGeneration: 1,
    nativeRequestId: _working ? 1 : null,
    cancellationRequested: cancellationStarted.isCompleted,
    recoveryOutcome: null,
    initializationPending: false,
    initializationRecoveryRequired: false,
  );

  @override
  Stream<LLMChunk> streamChatWithGenerationOptions(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    LLMChatOptions? options,
    GenerationOptions? generationOptions,
  }) {
    _working = true;
    return _chunks.stream;
  }

  void addText(String text) => _chunks.add(
    LLMChunk(
      model: 'fixture',
      createdAt: DateTime.utc(2026),
      message: LLMChunkMessage(content: text, role: LLMRole.assistant),
    ),
  );

  void acknowledgeCancellation() {
    if (!_acknowledgement.isCompleted) _acknowledgement.complete();
  }

  @override
  Future<void> cancelActiveInference() async {
    cancelCalls++;
    if (!cancellationStarted.isCompleted) cancellationStarted.complete();
    await _acknowledgement.future;
    await complete();
  }

  Future<void> complete() async {
    _working = false;
    await _chunks.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
