import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/models/message.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/runtime_profile.dart';
import 'package:vitalis_app/providers/generation_provider.dart';
import 'package:vitalis_app/services/chat_state_controller.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';
import 'package:vitalis_app/services/model_warmup_service.dart';

void main() {
  late _RecoveryController controller;
  late _RecoveryWarmup warmup;
  late GenerationProvider provider;
  late List<_RecoveryTimer> timers;
  setUp(() {
    controller = _RecoveryController();
    warmup = _RecoveryWarmup();
    timers = [];
    provider = GenerationProvider(
      controller: controller,
      warmup: warmup,
      shutdownTimeout: Duration.zero,
      readShutdownMonotonicMicros: () => 0,
      shutdownTimerFactory: (_, callback) {
        final timer = _RecoveryTimer(callback);
        timers.add(timer);
        return timer;
      },
    );
    addTearDown(provider.dispose);
  });
  Future<void> start() => provider.startGeneration(
    messages: [Message(chatId: 1, role: MessageRole.user, content: 'fixture')],
    settings: ModelSettings(),
  );
  Future<void> failStop() => expectLater(
    provider.stopSending(),
    throwsA(isA<InferenceRecoveryRequired>()),
  );

  test('healthy provider cannot invoke failed-owner recovery', () async {
    await expectLater(
      provider.recoverOwnedCleanup(),
      throwsA(isA<InferenceRuntimeBusy>()),
    );
    expect(controller.recoveryCalls, 0);
  });

  test('provider recovery deadline retains the unfinished owner', () async {
    await start();
    await failStop();
    final recovery = provider.recoverOwnedCleanup();
    await Future<void>.delayed(Duration.zero);
    var settled = false;
    final result = recovery.then((outcome) {
      settled = true;
      return outcome;
    });
    for (final timer in timers.toList()) {
      timer.fire();
    }
    await Future<void>.delayed(Duration.zero);
    try {
      expect(settled, isTrue);
      expect(await result, RuntimeRecoveryOutcome.terminationUnconfirmed);
      expect(provider.isRecovering, isTrue);
      expect(provider.requiresRecovery, isTrue);
      expect(controller.recoveryCalls, 1);
      final retry = provider.recoverOwnedCleanup();
      expect(provider.recoverOwnedCleanup(), same(retry));
      for (final timer in timers.toList()) {
        timer.fire();
      }
      expect(await retry, RuntimeRecoveryOutcome.terminationUnconfirmed);
      expect(controller.recoveryCalls, 1);
    } finally {
      controller.recovery.complete(RuntimeRecoveryOutcome.recovered);
      await recovery;
    }
    await Future<void>.delayed(Duration.zero);
    expect(provider.requiresRecovery, isTrue);
    await expectLater(
      provider.prepareModel(ModelSettings()),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    await expectLater(
      provider.unloadModel('fixture'),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    expect(
      await provider.recoverOwnedCleanup(),
      RuntimeRecoveryOutcome.recovered,
    );
    expect(provider.requiresRecovery, isFalse);
  });

  test('late recovery cannot clear a newer expired close', () async {
    await start();
    await failStop();
    final recovery = provider.recoverOwnedCleanup();
    final closing = provider.close();
    final failedClose = expectLater(
      closing,
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    for (final timer in timers.toList()) {
      timer.fire();
    }
    try {
      expect(await recovery, RuntimeRecoveryOutcome.terminationUnconfirmed);
      await failedClose;
      expect(provider.requiresRecovery, isTrue);
    } finally {
      controller.recovery.complete(RuntimeRecoveryOutcome.recovered);
    }
    await Future<void>.delayed(Duration.zero);
    expect(provider.requiresRecovery, isTrue);
    // First confirm the older retained recovery result, not the newer close.
    expect(
      await provider.recoverOwnedCleanup(),
      RuntimeRecoveryOutcome.recovered,
    );
    expect(provider.requiresRecovery, isTrue);
    // Explicitly confirm the newer close's settled actor as a separate scope.
    expect(
      await provider.recoverOwnedCleanup(),
      RuntimeRecoveryOutcome.recovered,
    );
    expect(provider.requiresRecovery, isFalse);
    await provider.close();
    await expectLater(closing, throwsA(isA<InferenceRecoveryRequired>()));
    await expectLater(provider.prepareModel(ModelSettings()), throwsStateError);
    expect(controller.recoveryCalls, 1);
  });

  test(
    'shared recovery preserves failure then permits a new request after acknowledgement',
    () async {
      await start();
      final failedStop = provider.stopSending();
      await expectLater(failedStop, throwsA(isA<InferenceRecoveryRequired>()));
      final recovering = provider.recoverOwnedCleanup();
      expect(provider.recoverOwnedCleanup(), same(recovering));
      controller.recovery.complete(
        RuntimeRecoveryOutcome.terminationUnconfirmed,
      );
      expect(await recovering, RuntimeRecoveryOutcome.terminationUnconfirmed);
      expect(provider.requiresRecovery, isTrue);
      controller.recovery = Completer();
      final retry = provider.recoverOwnedCleanup();
      await expectLater(
        provider.prepareModel(ModelSettings()),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      controller.recovery.complete(RuntimeRecoveryOutcome.recovered);
      expect(await retry, RuntimeRecoveryOutcome.recovered);
      expect(provider.requiresRecovery, isFalse);
      expect(provider.isSending, isFalse);
      await expectLater(failedStop, throwsA(isA<InferenceRecoveryRequired>()));
      await start();
      expect(controller.requests, 2);
    },
  );

  test(
    'claimed recovery with retained controller failure remains unavailable',
    () async {
      await start();
      await failStop();
      controller.rejectClaim = true;
      final recovering = provider.recoverOwnedCleanup();
      controller.recovery.complete(RuntimeRecoveryOutcome.recovered);
      expect(await recovering, RuntimeRecoveryOutcome.terminationUnconfirmed);
      expect(provider.requiresRecovery, isTrue);
      await expectLater(
        provider.prepareModel(ModelSettings()),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
    },
  );

  test('recovery drains preparation before clearing failed Stop', () async {
    warmup.waitForTuning = Completer();
    final preparing = provider.prepareModel(ModelSettings());
    await failStop();
    final recovering = provider.recoverOwnedCleanup();
    controller.recovery.complete(RuntimeRecoveryOutcome.recovered);
    await Future<void>(() {});
    expect(provider.isRecovering, isTrue);
    expect(provider.requiresRecovery, isTrue);
    warmup.waitForTuning!.complete();
    await preparing;
    expect(await recovering, RuntimeRecoveryOutcome.recovered);
    expect(warmup.resolveCalls, 0);
  });

  test(
    'close during recovery waits for the same attempt and never revives disposal',
    () async {
      await start();
      await failStop();
      final recovering = provider.recoverOwnedCleanup();
      final closing = provider.close();
      expect(provider.close(), same(closing));
      await expectLater(
        provider.prepareModel(ModelSettings()),
        throwsStateError,
      );
      controller.recovery.complete(RuntimeRecoveryOutcome.recovered);
      expect(await recovering, RuntimeRecoveryOutcome.recovered);
      await closing;
      expect(provider.requiresRecovery, isFalse);
      await expectLater(
        provider.prepareModel(ModelSettings()),
        throwsStateError,
      );
    },
  );

  test(
    'adapter failure retains quarantine without exposing its details',
    () async {
      await start();
      await failStop();
      final recovering = provider.recoverOwnedCleanup();
      controller.recovery.completeError(StateError('private adapter detail'));
      expect(await recovering, RuntimeRecoveryOutcome.terminationUnconfirmed);
      expect(provider.requiresRecovery, isTrue);
      expect(provider.errorMessage, isNot(contains('private adapter detail')));
    },
  );

  test('failed recovery also fails a concurrent close', () async {
    await start();
    await failStop();
    final recovering = provider.recoverOwnedCleanup();
    final closing = expectLater(
      provider.close(),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    controller.recovery.complete(RuntimeRecoveryOutcome.terminationUnconfirmed);
    expect(await recovering, RuntimeRecoveryOutcome.terminationUnconfirmed);
    await closing;
    expect(provider.requiresRecovery, isTrue);
  });

  test(
    'recovery after failed close does not revive a disposed provider',
    () async {
      await start();
      await failStop();
      final failedClose = provider.close();
      await expectLater(failedClose, throwsA(isA<InferenceRecoveryRequired>()));
      final recovering = provider.recoverOwnedCleanup();
      controller.recovery.complete(RuntimeRecoveryOutcome.recovered);
      expect(await recovering, RuntimeRecoveryOutcome.recovered);
      await provider.close();
      await expectLater(failedClose, throwsA(isA<InferenceRecoveryRequired>()));
      await expectLater(
        provider.prepareModel(ModelSettings()),
        throwsStateError,
      );
    },
  );

  test('failure without an identifiable owner is not recovery proof', () async {
    await start();
    await failStop();
    controller.failed = false;
    expect(
      await provider.recoverOwnedCleanup(),
      RuntimeRecoveryOutcome.terminationUnconfirmed,
    );
    expect(provider.requiresRecovery, isTrue);
  });

  test('model-service cleanup must also acknowledge recovery', () async {
    await start();
    await failStop();
    warmup.failedCleanup = true;
    final recovering = provider.recoverOwnedCleanup();
    controller.recovery.complete(RuntimeRecoveryOutcome.recovered);
    expect(await recovering, RuntimeRecoveryOutcome.terminationUnconfirmed);
    expect(provider.requiresRecovery, isTrue);
    warmup.outcome = RuntimeRecoveryOutcome.recovered;
    expect(
      await provider.recoverOwnedCleanup(),
      RuntimeRecoveryOutcome.recovered,
    );
    expect(warmup.recoveryCalls, 2);
  });
}

class _RecoveryController extends ChatStateController {
  _RecoveryController() : super(sentinel: _Sentinel());
  bool failed = false;
  bool rejectClaim = false;
  int requests = 0;
  int recoveryCalls = 0;
  Completer<RuntimeRecoveryOutcome> recovery = Completer();
  @override
  bool get cleanupFailed => failed;
  @override
  Future<void> startGeneration({
    required LlamaCppChatRepository repository,
    required List<LLMMessage> messages,
    required GenerationOptions options,
    bool think = false,
  }) async => requests++;
  @override
  Future<void> cancelInference() async {
    failed = true;
    failureCode = ChatFailureCode.cancellationUnacknowledged;
  }

  @override
  Future<RuntimeRecoveryOutcome> recoverOwnedCleanup() {
    recoveryCalls++;
    return recovery.future.then((outcome) {
      if (outcome == RuntimeRecoveryOutcome.recovered && !rejectClaim)
        failed = false;
      return outcome;
    });
  }
}

class _RecoveryWarmup implements ModelWarmupService {
  Completer<void>? waitForTuning;
  bool failedCleanup = false;
  int recoveryCalls = 0;
  int resolveCalls = 0;
  RuntimeRecoveryOutcome outcome =
      RuntimeRecoveryOutcome.terminationUnconfirmed;
  @override
  bool get requiresRecovery => failedCleanup;
  @override
  Future<RuntimeRecoveryOutcome> recoverOwnedCleanup() async {
    recoveryCalls++;
    if (outcome == RuntimeRecoveryOutcome.recovered) failedCleanup = false;
    return outcome;
  }

  @override
  Future<void> cancelTuning() => waitForTuning?.future ?? Future.value();
  @override
  Future<RuntimeProfile> resolveProfile(ModelSettings settings) async {
    resolveCalls++;
    return RuntimeProfile.forSettings(settings, processorCount: 2);
  }

  @override
  Future<LlamaCppChatRepository> ensureProfile(
    RuntimeProfile profile, {
    required String modelId,
  }) async => _Counter();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Counter implements LlamaCppChatRepository {
  @override
  Future<int> countChatTokens(
    List<LLMMessage> messages, {
    bool think = false,
  }) async => messages.length;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sentinel implements HardwareSentinelService {
  @override
  String? unsafeReasonHeavy() => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecoveryTimer implements Timer {
  _RecoveryTimer(this.callback);
  final void Function() callback;
  bool _active = true;
  @override
  bool get isActive => _active;
  @override
  int get tick => _active ? 0 : 1;
  @override
  void cancel() => _active = false;
  void fire() {
    if (!_active) return;
    _active = false;
    callback();
  }
}
