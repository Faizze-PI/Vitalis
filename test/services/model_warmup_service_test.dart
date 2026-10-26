import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_llamacpp/llm_llamacpp.dart';
import 'package:vitalis_app/models/model_descriptor.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/runtime_capabilities.dart';
import 'package:vitalis_app/models/runtime_profile.dart';
import 'package:vitalis_app/services/hardware_sentinel_service.dart';
import 'package:vitalis_app/services/model_registry_service.dart';
import 'package:vitalis_app/services/model_warmup_service.dart';
import 'package:vitalis_app/services/runtime_capabilities_provider.dart';
import 'package:vitalis_app/services/runtime_profile_store.dart';
import 'package:vitalis_app/services/runtime_benchmark_workload.dart';

void main() {
  const model = ModelDescriptor(
    id: 'model-a',
    displayName: 'Model A',
    source: 'fixture',
    compatibilityStatus: 'compatible',
    localPath: 'model-a.gguf',
    sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    contextTrain: 8192,
    chatTemplate: '{{ enable_thinking }} /no_think',
    blockCount: 8,
    supportsThinking: true,
    installationState: 'installed',
  );
  const knownCapabilities = RuntimeCapabilities(
    logicalProcessors: 8,
    performanceProcessors: 4,
    deviceFingerprint: 'fixture-device',
    abis: ['arm64-v8a'],
    packagedBackends: {'cpu', 'vulkan'},
    availableMemoryBytes: 8 * 1024 * 1024 * 1024,
    thermalStatus: 0,
    lowMemory: false,
  );

  ModelWarmupService createService({
    _Sentinel? sentinel,
    List<ModelDescriptor> models = const [model],
    RuntimeCapabilities capabilities = knownCapabilities,
    _ProfileStore? profiles,
    _RepositoryFactory? repositories,
    RuntimeCapabilitiesProvider? capabilitiesProvider,
    AppVersionResolver? appVersionResolver,
    Duration shutdownTimeout = RuntimeWatchdogDefaults.noProgressTimeout,
    RuntimeWatchdogTimerFactory shutdownTimerFactory = Timer.new,
    int Function()? readShutdownMonotonicMicros,
  }) {
    final registry = _Registry(models);
    final factory = repositories ?? _RepositoryFactory();
    return ModelWarmupService(
      sentinel: sentinel ?? _Sentinel(),
      capabilitiesProvider: capabilitiesProvider ?? _Capabilities(capabilities),
      profileStore: profiles ?? _ProfileStore(),
      modelRegistry: registry,
      repositoryFactory: factory.create,
      appVersionResolver: appVersionResolver ?? () async => '1.0.0+1',
      processorCount: 8,
      clock: () => DateTime.utc(2026, 1, 2),
      shutdownTimeout: shutdownTimeout,
      shutdownTimerFactory: shutdownTimerFactory,
      readShutdownMonotonicMicros: readShutdownMonotonicMicros,
    );
  }

  test('warmup skips unsafe devices and missing installed models', () async {
    final unsafe = createService(sentinel: _Sentinel(reason: 'unsafe'));
    final empty = createService(models: const []);
    addTearDown(unsafe.dispose);
    addTearDown(empty.dispose);

    await unsafe.warmup();
    await empty.warmup();

    expect(unsafe.isWarmedUp, isFalse);
    expect(empty.isWarmedUp, isFalse);
    expect(unsafe.isWarmingUp, isFalse);
    expect(empty.isWarmingUp, isFalse);
  });

  test('tuning rejects native prompt-token workload mismatch', () async {
    final profiles = _ProfileStore();
    final repositories = _RepositoryFactory(reportedPromptTokens: 255);
    final service = createService(
      profiles: profiles,
      repositories: repositories,
    );
    addTearDown(service.dispose);
    service.scheduleAutoTune(ModelSettings(modelId: model.id));
    await Future<void>.delayed(Duration.zero);
    expect(service.tuningStatus, RuntimeTuningStatus.failed);
    expect(profiles.writes, isEmpty);
  });
  test(
    'benchmark budgeting and generation use the same thinking configuration',
    () async {
      final repositories = _RepositoryFactory();
      final service = createService(repositories: repositories);
      addTearDown(service.dispose);
      service.scheduleAutoTune(
        ModelSettings(modelId: model.id, thinkingMode: ThinkingMode.on),
      );
      await _waitFor(() => service.tuningStatus == RuntimeTuningStatus.ready);
      expect(
        repositories.created.every(
          (repository) =>
              repository.tokenizeThink == true &&
              repository.generateThink == true,
        ),
        isTrue,
      );
    },
  );

  test('changing only prompt threads replaces the prepared context', () async {
    final repositories = _RepositoryFactory();
    final service = createService(repositories: repositories);
    addTearDown(service.dispose);
    const profile = RuntimeProfile(
      contextSize: 2048,
      reservedOutputTokens: 32,
      generationThreads: 2,
      promptThreads: 2,
      batchSize: 128,
      gpuLayers: 0,
      thinkingMode: ThinkingMode.off,
    );
    final first = await service.ensureProfile(profile, modelId: model.id);
    final second = await service.ensureProfile(
      profile.copyWith(promptThreads: 3),
      modelId: model.id,
    );
    expect(second, isNot(same(first)));
    expect(repositories.created, hasLength(2));
    expect(repositories.created.first.unloadCalls, 1);
    expect(repositories.created.last.promptThreads, 3);
  });

  for (final mismatch in [
    'missing',
    'generation',
    'prompt',
    'context',
    'batch',
  ]) {
    test('tuning rejects $mismatch native configuration evidence', () async {
      final profiles = _ProfileStore();
      final repositories = _RepositoryFactory(reportedMismatch: mismatch);
      final service = createService(
        profiles: profiles,
        repositories: repositories,
      );
      addTearDown(service.close);
      final failed = Completer<void>();
      service.addListener(() {
        if (service.tuningStatus == RuntimeTuningStatus.failed &&
            !failed.isCompleted) {
          failed.complete();
        }
      });
      service.scheduleAutoTune(ModelSettings(modelId: model.id));
      await failed.future.timeout(const Duration(seconds: 10));
      await service.cancelTuning();
      expect(profiles.writeStarted.isCompleted, isFalse);
      expect(repositories.created, hasLength(1));
      expect(
        service.fallbackReason,
        contains('RuntimeBenchmarkConfigurationUnavailable'),
      );
    });
  }

  test(
    'warmup initializes selected model once and dispose is idempotent',
    () async {
      final repositories = _RepositoryFactory();
      final service = createService(repositories: repositories);

      await service.warmup(modelId: model.id);
      await service.warmup();

      expect(service.isWarmedUp, isTrue);
      expect(service.repository, same(repositories.created.single));
      expect(repositories.created.single.prepareCalls, 1);
      expect(
        repositories.created.single.lastPreparationKind,
        RuntimeOperationKind.warmup,
      );
      service
        ..dispose()
        ..dispose();
      expect(service.isDisposed, isTrue);
      await service.close();
      expect(repositories.created.single.disposeCalls, 1);
    },
  );

  test('explicit missing model never loads an installed substitute', () async {
    final repositories = _RepositoryFactory();
    final service = createService(repositories: repositories);
    addTearDown(service.dispose);
    expect(
      await service.warmup(modelId: 'unavailable-model'),
      ModelWarmupOutcome.unavailable,
    );
    expect(repositories.created, isEmpty);
    expect(service.isWarmedUp, isFalse);
    expect(service.isWarmingUp, isFalse);
  });

  test('missing warmup selection preserves an already loaded model', () async {
    final repositories = _RepositoryFactory();
    final service = createService(repositories: repositories);
    addTearDown(service.dispose);
    expect(await service.warmup(modelId: model.id), ModelWarmupOutcome.ready);
    final owner = service.repository;
    expect(
      await service.warmup(modelId: 'unavailable-model'),
      ModelWarmupOutcome.unavailable,
    );
    expect(service.repository, same(owner));
    expect(repositories.created, hasLength(1));
    expect(repositories.created.single.unloadCalls, 0);
    expect(service.isWarmingUp, isFalse);
  });

  test('same-model warmup preserves an existing effective profile', () async {
    final repositories = _RepositoryFactory();
    final service = createService(repositories: repositories);
    addTearDown(service.dispose);
    final profile = await service.resolveProfile(
      ModelSettings(
        modelId: model.id,
        tuningMode: TuningMode.advanced,
        contextSizeOverride: 2048,
        generationThreadsOverride: 1,
        promptThreadsOverride: 1,
        batchSizeOverride: 128,
      ),
    );
    final owner = await service.ensureProfile(profile, modelId: model.id);
    expect(await service.warmup(modelId: model.id), ModelWarmupOutcome.ready);
    expect(service.repository, same(owner));
    expect(repositories.created, hasLength(1));
    expect(service.effectiveProfile?.generationThreads, 1);
  });

  test('advanced overrides bypass cache and expose effective values', () async {
    final profiles = _ProfileStore();
    final service = createService(profiles: profiles);
    addTearDown(service.dispose);

    final profile = await service.resolveProfile(
      ModelSettings(
        modelId: model.id,
        tuningMode: TuningMode.advanced,
        contextSizeOverride: 4096,
        generationThreadsOverride: 3,
        promptThreadsOverride: 2,
        batchSizeOverride: 256,
      ),
    );

    expect(profile.contextSize, 4096);
    expect(profile.generationThreads, 3);
    expect(profile.promptThreads, 2);
    expect(profile.batchSize, 256);
    expect(profiles.reads, 0);
  });

  test(
    'service disposal retains repository until cleanup acknowledges',
    () async {
      final repositories = _RepositoryFactory();
      final service = createService(repositories: repositories);
      await service.warmup(modelId: model.id);
      final repository = repositories.created.single;
      repository.closeAcknowledgement = Completer<void>();
      try {
        service.dispose();
        expect(service.isDisposed, isTrue);
        expect(service.repository, same(repository));
        expect(repository.disposeCalls, 0);
      } finally {
        repository.closeAcknowledgement!.complete();
        await service.close();
      }
    },
  );

  for (final fails in [false, true]) {
    test('service close shares cleanup and retains failure ($fails)', () async {
      final repositories = _RepositoryFactory();
      final service = createService(repositories: repositories);
      await service.warmup(modelId: model.id);
      final repository = repositories.created.single;
      repository.closeAcknowledgement = Completer<void>();
      final first = service.close();
      final second = service.close();
      expect(identical(first, second), isTrue);
      final outcome = fails ? expectLater(first, throwsStateError) : first;
      await repository.closeStarted.future;
      expect(service.repository, same(repository));
      expect(service.isWarmedUp, isFalse);
      expect(repository.unloadCalls, 0);
      await expectLater(
        service.ensureProfile(_stored(gpuLayers: 0).profile, modelId: model.id),
        throwsStateError,
      );
      if (fails) {
        repository.closeAcknowledgement!.completeError(
          StateError('unconfirmed'),
        );
      } else {
        repository.closeAcknowledgement!.complete();
      }
      await outcome;
      expect(service.requiresRecovery, fails);
      expect(service.repository, fails ? same(repository) : isNull);
      expect(repository.unloadCalls, fails ? 0 : 1);
      service.dispose();
      expect(identical(service.close(), first), isTrue);
    });
  }

  test(
    'service close expiry retains its pending cleanup',
    () async {
      final repositories = _RepositoryFactory();
      final timers = <_ShutdownTimer>[];
      void expire() {
        for (final timer in timers.toList()) {
          if (timer.isActive) timer.fire();
        }
      }

      final service = createService(
        repositories: repositories,
        shutdownTimeout: Duration.zero,
        readShutdownMonotonicMicros: () => 0,
        shutdownTimerFactory: (_, callback) {
          final timer = _ShutdownTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      await service.warmup(modelId: model.id);
      final repository = repositories.created.single;
      final acknowledgement = Completer<void>();
      repository.closeAcknowledgement = acknowledgement;
      final original = service.close();
      final expired = expectLater(
        original,
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      await repository.closeStarted.future;
      try {
        expire();
        await expired;
        expect(service.requiresRecovery, isTrue);
        expect(service.repository, same(repository));
        expect(service.close(), same(original));
        final recovery = service.recoverOwnedCleanup();
        expect(service.recoverOwnedCleanup(), same(recovery));
        expire();
        expect(await recovery, RuntimeRecoveryOutcome.terminationUnconfirmed);
        expect(repository.cancelCalls, 1);
      } finally {
        acknowledgement.complete();
        await Future<void>(() {});
      }
      expect(service.requiresRecovery, isTrue);
      expect(service.repository, same(repository));
      expect(
        await service.recoverOwnedCleanup(),
        RuntimeRecoveryOutcome.recovered,
      );
      expect(service.isDisposed, isTrue);
      expect(service.repository, isNull);
      await service.close();
      await expectLater(original, throwsA(isA<InferenceRecoveryRequired>()));
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test('service close drains preparation and rejects late readiness', () async {
    final preparing = Completer<void>();
    final prepared = Completer<void>();
    final repositories = _RepositoryFactory(
      prepareBarrier: prepared,
      prepareStarted: preparing,
    );
    final service = createService(repositories: repositories);
    final profile = _stored(gpuLayers: 0).profile;
    final preparation = service.ensureProfile(profile, modelId: model.id);
    final rejected = expectLater(preparation, throwsStateError);
    await preparing.future;
    await expectLater(
      service.ensureProfile(profile, modelId: model.id),
      throwsA(isA<InferenceRuntimeBusy>()),
    );
    var closed = false;
    final shutdown = service.close().then((_) => closed = true);
    await Future<void>.value();
    expect(closed, isFalse);
    expect(repositories.created, hasLength(1));
    prepared.complete();
    await rejected;
    await shutdown;
    expect(service.repository, isNull);
    expect(service.isWarmedUp, isFalse);
    expect(repositories.created.single.unloadCalls, 1);
  });

  test(
    'service close default timer observes an unacknowledged actor',
    () async {
      final repositories = _RepositoryFactory();
      final service = createService(
        repositories: repositories,
        shutdownTimeout: const Duration(milliseconds: 10),
      );
      await service.warmup(modelId: model.id);
      final owner = repositories.created.single;
      final acknowledgement = Completer<void>();
      owner.closeAcknowledgement = acknowledgement;
      final closing = service.close();
      final expired = expectLater(
        closing,
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      try {
        await owner.closeStarted.future;
        await expired;
        expect(service.repository, same(owner));
        expect(service.requiresRecovery, isTrue);
        expect(owner.cancelCalls, 1);
      } finally {
        acknowledgement.complete();
        await Future<void>(() {});
      }
      expect(
        await service.recoverOwnedCleanup(),
        RuntimeRecoveryOutcome.recovered,
      );
      expect(service.isDisposed, isTrue);
      await service.close();
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test('healthy service cannot recover or retire a ready owner', () async {
    final repositories = _RepositoryFactory();
    final service = createService(repositories: repositories);
    addTearDown(service.close);
    await service.warmup(modelId: model.id);
    final owner = service.repository;
    await expectLater(
      service.recoverOwnedCleanup(),
      throwsA(isA<InferenceRuntimeBusy>()),
    );
    expect(service.repository, same(owner));
    expect(repositories.created.single.recoveryCalls, 0);
  });

  test('disposed service shares owner recovery without revival', () async {
    final repositories = _RepositoryFactory();
    final service = createService(repositories: repositories);
    await service.warmup(modelId: model.id);
    final repository = repositories.created.single;
    repository.closeAcknowledgement = Completer<void>();
    final original = service.close();
    final failure = expectLater(original, throwsStateError);
    await repository.closeStarted.future;
    repository.closeAcknowledgement!.completeError(StateError('unconfirmed'));
    await failure;
    repository.recoveryAcknowledgement = Completer<RuntimeRecoveryOutcome>();
    final first = service.recoverOwnedCleanup();
    expect(service.recoverOwnedCleanup(), same(first));
    await repository.recoveryStarted.future;
    expect(service.repository, same(repository));
    expect(service.requiresRecovery, isTrue);
    repository.recoveryAcknowledgement!.complete(
      RuntimeRecoveryOutcome.terminationUnconfirmed,
    );
    expect(await first, RuntimeRecoveryOutcome.terminationUnconfirmed);
    expect(service.requiresRecovery, isTrue);
    expect(service.close(), same(original));
    repository.recoveryAcknowledgement = Completer<RuntimeRecoveryOutcome>();
    final retry = service.recoverOwnedCleanup();
    expect(service.recoverOwnedCleanup(), same(retry));
    repository.recoveryAcknowledgement!.complete(
      RuntimeRecoveryOutcome.recovered,
    );
    expect(await retry, RuntimeRecoveryOutcome.recovered);
    expect(repository.recoveryCalls, 2);
    expect(service.requiresRecovery, isFalse);
    expect(service.repository, isNull);
    expect(service.isDisposed, isTrue);
    await expectLater(original, throwsStateError);
    await service.close();
    await expectLater(
      service.ensureProfile(_stored(gpuLayers: 0).profile, modelId: model.id),
      throwsStateError,
    );
  });

  test(
    'active service retires failed tuning before next preparation',
    () async {
      final prepared = Completer<void>();
      final preparing = Completer<void>();
      final repositories = _RepositoryFactory(
        prepareBarrier: prepared,
        prepareStarted: preparing,
      );
      final profiles = _ProfileStore();
      final service = createService(
        repositories: repositories,
        profiles: profiles,
      );
      service.scheduleAutoTune(ModelSettings(modelId: model.id));
      await preparing.future;
      final repository = repositories.created.single;
      expect(repository.runtimeOperationKind, RuntimeOperationKind.tuning);
      repository.closeAcknowledgement = Completer<void>();
      final stopped = service.cancelTuning();
      final failed = expectLater(stopped, throwsStateError);
      prepared.complete();
      await repository.closeStarted.future;
      repository.closeAcknowledgement!.completeError(StateError('unconfirmed'));
      await failed;
      expect(service.requiresRecovery, isTrue);
      repository.recoveryAcknowledgement = Completer<RuntimeRecoveryOutcome>();
      final recovering = service.recoverOwnedCleanup();
      await repository.recoveryStarted.future;
      await expectLater(
        service.ensureProfile(_stored(gpuLayers: 0).profile, modelId: model.id),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      service.scheduleAutoTune(ModelSettings(modelId: model.id));
      expect(repositories.created, hasLength(1));
      repository.recoveryAcknowledgement!.complete(
        RuntimeRecoveryOutcome.recovered,
      );
      expect(await recovering, RuntimeRecoveryOutcome.recovered);
      expect(service.requiresRecovery, isFalse);
      expect(service.isDisposed, isFalse);
      expect(profiles.writes, isEmpty);
      await expectLater(stopped, throwsStateError);
      await service.cancelTuning();
      final next = await service.ensureProfile(
        _stored(gpuLayers: 0).profile,
        modelId: model.id,
      );
      expect(next, isNot(same(repository)));
      expect(repositories.created, hasLength(2));
      await service.close();
    },
  );

  test('disposed service rejects profile resolution', () async {
    final service = createService();
    service.dispose();
    await expectLater(
      service.resolveProfile(ModelSettings(modelId: model.id)),
      throwsStateError,
    );
  });

  for (final scenario in [
    (acknowledged: false, expires: false),
    (acknowledged: true, expires: false),
    (acknowledged: true, expires: true),
  ]) {
    final acknowledged = scenario.acknowledged;
    final expires = scenario.expires;
    test(
      'disposal during owner recovery waits for acknowledgement ($acknowledged, expiry: $expires)',
      () async {
        final prepared = Completer<void>();
        final preparing = Completer<void>();
        final repositories = _RepositoryFactory(
          failContextsAbove: 0,
          prepareBarrier: prepared,
          prepareStarted: preparing,
        );
        final timers = <_ShutdownTimer>[];
        final service = createService(
          repositories: repositories,
          shutdownTimeout: expires
              ? Duration.zero
              : RuntimeWatchdogDefaults.noProgressTimeout,
          readShutdownMonotonicMicros: () => 0,
          shutdownTimerFactory: (_, callback) {
            final timer = _ShutdownTimer(callback);
            timers.add(timer);
            return timer;
          },
        );
        final preparation = service.ensureProfile(
          _stored(gpuLayers: 0).profile,
          modelId: model.id,
        );
        final rejected = expectLater(
          preparation,
          throwsA(isA<InferenceRecoveryRequired>()),
        );
        await preparing.future;
        final owner = repositories.created.single;
        owner.closeAcknowledgement = Completer<void>();
        prepared.complete();
        await owner.closeStarted.future;
        owner.closeAcknowledgement!.completeError(StateError('unconfirmed'));
        await rejected;
        owner.recoveryAcknowledgement = Completer<RuntimeRecoveryOutcome>();
        final recovery = service.recoverOwnedCleanup();
        await owner.recoveryStarted.future;
        var settled = false;
        final closing = service.close();
        final closingResult = acknowledged && !expires
            ? closing
            : expectLater(closing, throwsA(isA<InferenceRecoveryRequired>()));
        unawaited(
          closing.then<void>(
            (_) => settled = true,
            onError: (Object _, StackTrace __) => settled = true,
          ),
        );
        expect(service.close(), same(closing));
        expect(service.isDisposed, isTrue);
        expect(service.isRecovering, isTrue);
        await Future<void>.value();
        expect(settled, isFalse);
        if (expires) {
          for (final timer in timers.toList()) {
            if (timer.isActive) timer.fire();
          }
          await closingResult;
          expect(service.requiresRecovery, isTrue);
        }
        owner.recoveryAcknowledgement!.complete(
          acknowledged
              ? RuntimeRecoveryOutcome.recovered
              : RuntimeRecoveryOutcome.terminationUnconfirmed,
        );
        expect(
          await recovery,
          acknowledged && !expires
              ? RuntimeRecoveryOutcome.recovered
              : RuntimeRecoveryOutcome.terminationUnconfirmed,
        );
        await closingResult;
        if (expires && acknowledged) {
          // The original expired observation remains unconfirmed. Join the
          // retained actor explicitly without clearing the newer close failure.
          expect(
            await service.recoverOwnedCleanup(),
            RuntimeRecoveryOutcome.recovered,
          );
        }
        expect(service.isRecovering, isFalse);
        expect(service.requiresRecovery, !acknowledged || expires);
        expect(owner.recoveryCalls, 1);
        if (!acknowledged || expires) {
          owner.recoveryAcknowledgement = Completer<RuntimeRecoveryOutcome>()
            ..complete(RuntimeRecoveryOutcome.recovered);
          expect(
            await service.recoverOwnedCleanup(),
            RuntimeRecoveryOutcome.recovered,
          );
          await service.close();
        }
        expect(service.isDisposed, isTrue);
        expect(repositories.created, hasLength(1));
      },
    );
  }

  test(
    'claimed recovery with continuing owner failure cannot clear quarantine',
    () async {
      final repositories = _RepositoryFactory();
      final service = createService(repositories: repositories);
      await service.warmup(modelId: model.id);
      final owner = repositories.created.single;
      owner.closeAcknowledgement = Completer<void>();
      final closed = service.close();
      final failed = expectLater(closed, throwsStateError);
      await owner.closeStarted.future;
      owner.closeAcknowledgement!.completeError(StateError('unconfirmed'));
      await failed;
      owner.retainFailureAfterRecovery = true;
      owner.recoveryAcknowledgement = Completer<RuntimeRecoveryOutcome>()
        ..complete(RuntimeRecoveryOutcome.recovered);
      expect(
        await service.recoverOwnedCleanup(),
        RuntimeRecoveryOutcome.terminationUnconfirmed,
      );
      expect(service.requiresRecovery, isTrue);
      owner.retainFailureAfterRecovery = false;
      expect(
        await service.recoverOwnedCleanup(),
        RuntimeRecoveryOutcome.recovered,
      );
      await service.close();
    },
  );

  test('new tuning Stop failure survives older recovery', () async {
    final prepared = Completer<void>();
    final preparing = Completer<void>();
    final repositories = _RepositoryFactory(
      failContextsAbove: 0,
      prepareBarrier: prepared,
      prepareStarted: preparing,
    );
    final service = createService(repositories: repositories);
    final preparation = service.ensureProfile(
      _stored(gpuLayers: 0).profile,
      modelId: model.id,
    );
    final rejected = expectLater(
      preparation,
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    await preparing.future;
    final owner = repositories.created.single;
    owner.closeAcknowledgement = Completer<void>();
    prepared.complete();
    await owner.closeStarted.future;
    owner.closeAcknowledgement!.completeError(StateError('unconfirmed'));
    await rejected;
    owner.recoveryAcknowledgement = Completer<RuntimeRecoveryOutcome>();
    final recovery = service.recoverOwnedCleanup();
    await owner.recoveryStarted.future;
    await expectLater(
      service.cancelTuning(),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    owner.recoveryAcknowledgement!.complete(RuntimeRecoveryOutcome.recovered);
    expect(await recovery, RuntimeRecoveryOutcome.recovered);
    expect(service.requiresRecovery, isTrue);
    await expectLater(
      service.ensureProfile(_stored(gpuLayers: 0).profile, modelId: model.id),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    expect(
      await service.recoverOwnedCleanup(),
      RuntimeRecoveryOutcome.recovered,
    );
    expect(service.requiresRecovery, isFalse);
    expect(owner.recoveryCalls, 1);
    expect(repositories.created, hasLength(1));
    await service.close();
  });

  test('recovery expiry retains its native owner and late result', () async {
    final prepared = Completer<void>();
    final preparing = Completer<void>();
    final timers = <_ShutdownTimer>[];
    final repositories = _RepositoryFactory(
      failContextsAbove: 0,
      prepareBarrier: prepared,
      prepareStarted: preparing,
    );
    final service = createService(
      repositories: repositories,
      shutdownTimeout: Duration.zero,
      readShutdownMonotonicMicros: () => 0,
      shutdownTimerFactory: (_, callback) {
        final timer = _ShutdownTimer(callback);
        timers.add(timer);
        return timer;
      },
    );
    final rejected = expectLater(
      service.ensureProfile(_stored(gpuLayers: 0).profile, modelId: model.id),
      throwsA(isA<InferenceRecoveryRequired>()),
    );
    await preparing.future;
    final owner = repositories.created.single;
    owner.closeAcknowledgement = Completer<void>();
    prepared.complete();
    await owner.closeStarted.future;
    owner.closeAcknowledgement!.completeError(StateError('unconfirmed'));
    await rejected;
    owner.recoveryAcknowledgement = Completer<RuntimeRecoveryOutcome>();
    final recovery = service.recoverOwnedCleanup();
    await owner.recoveryStarted.future;
    var observed = false;
    final result = recovery.then((outcome) {
      observed = true;
      return outcome;
    });
    for (final timer in timers.toList()) {
      timer.fire();
    }
    await Future<void>.delayed(Duration.zero);
    try {
      expect(observed, isTrue);
      expect(await result, RuntimeRecoveryOutcome.terminationUnconfirmed);
      expect(service.requiresRecovery, isTrue);
      expect(service.isRecovering, isTrue);
      expect(owner.recoveryCalls, 1);
      final retry = service.recoverOwnedCleanup();
      expect(service.recoverOwnedCleanup(), same(retry));
      for (final timer in timers.toList()) {
        timer.fire();
      }
      expect(await retry, RuntimeRecoveryOutcome.terminationUnconfirmed);
      expect(owner.recoveryCalls, 1);
      await expectLater(
        service.ensureProfile(_stored(gpuLayers: 0).profile, modelId: model.id),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
    } finally {
      owner.recoveryAcknowledgement!.complete(RuntimeRecoveryOutcome.recovered);
      await recovery;
    }
    await Future<void>.delayed(Duration.zero);
    expect(service.requiresRecovery, isTrue);
    expect(
      await service.recoverOwnedCleanup(),
      RuntimeRecoveryOutcome.recovered,
    );
    expect(service.requiresRecovery, isFalse);
    await service.close();
  });

  test('service tuning Stop callers share acknowledgement', () async {
    final prepared = Completer<void>();
    final preparing = Completer<void>();
    final repositories = _RepositoryFactory(
      prepareBarrier: prepared,
      prepareStarted: preparing,
    );
    final service = createService(repositories: repositories);
    addTearDown(service.dispose);
    service.scheduleAutoTune(ModelSettings(modelId: model.id));
    await preparing.future;
    final first = service.cancelTuning();
    final second = service.cancelTuning();
    try {
      expect(identical(first, second), isTrue);
      expect(repositories.created.single.cancelCalls, 1);
    } finally {
      prepared.complete();
      await Future.wait([first, second]);
    }
  });

  test(
    'service retains failed tuning cleanup and blocks replacement',
    () async {
      final prepared = Completer<void>();
      final preparing = Completer<void>();
      final repositories = _RepositoryFactory(
        prepareBarrier: prepared,
        prepareStarted: preparing,
      );
      final service = createService(repositories: repositories);
      service.scheduleAutoTune(ModelSettings(modelId: model.id));
      await preparing.future;
      final repository = repositories.created.single;
      repository.closeAcknowledgement = Completer<void>();
      final stopped = service.cancelTuning();
      final failed = expectLater(stopped, throwsStateError);
      prepared.complete();
      await repository.closeStarted.future;
      repository.closeAcknowledgement!.completeError(StateError('unconfirmed'));
      await failed;
      expect(service.requiresRecovery, isTrue);
      await expectLater(
        service.ensureProfile(_stored(gpuLayers: 0).profile, modelId: model.id),
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      service.scheduleAutoTune(ModelSettings(modelId: model.id));
      expect(repositories.created, hasLength(1));
      await expectLater(service.close(), throwsStateError);
      expect(repository.unloadCalls, 0);
    },
  );

  test(
    'tuning Stop expiry retains preparation until explicit recovery',
    () async {
      final prepared = Completer<void>();
      final preparing = Completer<void>();
      final timers = <_ShutdownTimer>[];
      final profiles = _ProfileStore();
      final repositories = _RepositoryFactory(
        prepareBarrier: prepared,
        prepareStarted: preparing,
      );
      final service = createService(
        repositories: repositories,
        profiles: profiles,
        shutdownTimeout: Duration.zero,
        readShutdownMonotonicMicros: () => 0,
        shutdownTimerFactory: (_, callback) {
          final timer = _ShutdownTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      void expire() {
        for (final timer in timers.toList()) {
          if (timer.isActive) timer.fire();
        }
      }

      service.scheduleAutoTune(ModelSettings(modelId: model.id));
      await preparing.future;
      final owner = repositories.created.single;
      final stopped = service.cancelTuning();
      Object? failure;
      unawaited(
        stopped.then<void>(
          (_) {},
          onError: (Object error, StackTrace _) {
            failure = error;
          },
        ),
      );
      try {
        expect(service.cancelTuning(), same(stopped));
        expire();
        await Future<void>(() {});
        expect(service.requiresRecovery, isTrue);
        expect(failure, isA<InferenceRecoveryRequired>());
        await expectLater(
          service.ensureProfile(
            _stored(gpuLayers: 0).profile,
            modelId: model.id,
          ),
          throwsA(isA<InferenceRecoveryRequired>()),
        );
        final recovery = service.recoverOwnedCleanup();
        expect(service.recoverOwnedCleanup(), same(recovery));
        expire();
        expect(await recovery, RuntimeRecoveryOutcome.terminationUnconfirmed);
        expect(owner.cancelCalls, 1);
        expect(owner.generationCalls, 0);
        expect(profiles.writes, isEmpty);
      } finally {
        prepared.complete();
        try {
          await stopped;
        } catch (_) {
          // Original failure remains observable; retirement is checked separately.
        }
        await Future<void>(() {});
        if (service.requiresRecovery) {
          expect(
            await service.recoverOwnedCleanup(),
            RuntimeRecoveryOutcome.recovered,
          );
        }
        await service.close();
      }
      expect(owner.generationCalls, 0);
      expect(profiles.writes, isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test('service disposal rejects delayed profiles without notifying', () async {
    final capabilities = _PendingCapabilities();
    final service = createService(capabilitiesProvider: capabilities);
    var notifications = 0;
    service.addListener(() => notifications++);
    final profile = service.resolveProfile(ModelSettings(modelId: model.id));
    final rejected = expectLater(profile, throwsStateError);
    await capabilities.started.future;
    await service.close();
    capabilities.result.complete(knownCapabilities);
    await rejected;
    expect(service.effectiveProfile, isNull);
    expect(notifications, 0);
  });

  test(
    'pre-context tuning expiry recovers after discovery settles',
    () async {
      final capabilities = _PendingCapabilities();
      final repositories = _RepositoryFactory();
      final profiles = _ProfileStore();
      final timers = <_ShutdownTimer>[];
      final service = createService(
        repositories: repositories,
        profiles: profiles,
        capabilitiesProvider: capabilities,
        shutdownTimeout: Duration.zero,
        readShutdownMonotonicMicros: () => 0,
        shutdownTimerFactory: (_, callback) {
          final timer = _ShutdownTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      service.scheduleAutoTune(ModelSettings(modelId: model.id));
      await capabilities.started.future;
      final stopped = service.cancelTuning();
      final expired = expectLater(
        stopped,
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      for (final timer in timers.toList()) {
        if (timer.isActive) timer.fire();
      }
      await expired;
      expect(service.requiresRecovery, isTrue);
      capabilities.result.complete(knownCapabilities);
      await Future<void>(() {});
      try {
        expect(
          await service.recoverOwnedCleanup(),
          RuntimeRecoveryOutcome.recovered,
        );
        expect(service.requiresRecovery, isFalse);
        expect(repositories.created, isEmpty);
        expect(profiles.writes, isEmpty);
      } finally {
        service.dispose();
        try {
          await service.close();
        } catch (_) {
          // Preserve an unconfirmed test outcome; no native owner was created.
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'close during retained tuning drain never waits on itself',
    () async {
      final prepared = Completer<void>();
      final preparing = Completer<void>();
      final repositories = _RepositoryFactory(
        prepareBarrier: prepared,
        prepareStarted: preparing,
      );
      final timers = <_ShutdownTimer>[];
      final service = createService(
        repositories: repositories,
        shutdownTimeout: Duration.zero,
        readShutdownMonotonicMicros: () => 0,
        shutdownTimerFactory: (_, callback) {
          final timer = _ShutdownTimer(callback);
          timers.add(timer);
          return timer;
        },
      );
      service.scheduleAutoTune(ModelSettings(modelId: model.id));
      await preparing.future;
      final stopped = service.cancelTuning();
      final expired = expectLater(
        stopped,
        throwsA(isA<InferenceRecoveryRequired>()),
      );
      for (final timer in timers.toList()) {
        if (timer.isActive) timer.fire();
      }
      await expired;
      final recovery = service.recoverOwnedCleanup();
      final closing = service.close();
      prepared.complete();
      expect(await recovery, RuntimeRecoveryOutcome.recovered);
      await closing;
      expect(service.isDisposed, isTrue);
      expect(service.requiresRecovery, isFalse);
      expect(service.repository, isNull);
      expect(repositories.created.single.generationCalls, 0);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test('unknown telemetry selects conservative scheduled profile', () async {
    const unknown = RuntimeCapabilities(
      logicalProcessors: 8,
      deviceFingerprint: 'unknown-device',
      abis: [],
      packagedBackends: {'cpu'},
    );
    final service = createService(capabilities: unknown);
    addTearDown(service.dispose);

    final profile = await service.resolveProfile(
      ModelSettings(modelId: model.id),
    );

    expect(profile.generationThreads, 1);
    expect(profile.promptThreads, 1);
    expect(profile.batchSize, 128);
    expect(profile.gpuLayers, 0);
    expect(service.tuningStatus, RuntimeTuningStatus.scheduled);
    expect(service.fallbackReason, contains('telemetry'));
  });

  test('cached CPU and Vulkan profiles are restored by complete key', () async {
    final profiles = _ProfileStore(
      cpu: _stored(gpuLayers: 0),
      vulkan: _stored(gpuLayers: 3),
    );
    final service = createService(profiles: profiles);
    addTearDown(service.dispose);

    final cpu = await service.resolveProfile(ModelSettings(modelId: model.id));
    final gpu = await service.resolveProfile(
      ModelSettings(
        modelId: model.id,
        accelerationPreference: AccelerationPreference.experimentalGpu,
        maxTokens: 99,
        thinkingMode: ThinkingMode.on,
      ),
    );

    expect(cpu.gpuLayers, 0);
    expect(gpu.gpuLayers, 3);
    expect(gpu.reservedOutputTokens, 99);
    expect(gpu.thinkingMode, ThinkingMode.on);
    expect(service.tuningStatus, RuntimeTuningStatus.ready);
    expect(service.lastTunedAt, DateTime.utc(2025));
  });

  test(
    'context allocation probes downward and reuses matching runtime',
    () async {
      final repositories = _RepositoryFactory(failContextsAbove: 2048);
      final service = createService(repositories: repositories);
      addTearDown(service.dispose);
      const profile = RuntimeProfile(
        contextSize: 4096,
        reservedOutputTokens: 64,
        generationThreads: 2,
        promptThreads: 2,
        batchSize: 128,
        gpuLayers: 0,
        thinkingMode: ThinkingMode.off,
      );

      final first = await service.ensureProfile(profile, modelId: model.id);
      final second = await service.ensureProfile(
        profile.copyWith(contextSize: 2048),
        modelId: model.id,
      );

      expect(service.effectiveContextSize, 2048);
      expect(first, same(second));
      expect(
        repositories.created.last.prepareCalls,
        2,
        reason:
            'A cached repository does not prove its recovered context is loaded',
      );
      expect(repositories.created.map((repo) => repo.contextSize), [
        4096,
        2048,
      ]);
      expect(repositories.created.map((repo) => repo.disposeCalls), [1, 0]);
    },
  );

  for (final fails in [false, true]) {
    test(
      'profile handoff awaits close acknowledgement (failure: $fails)',
      () async {
        final repositories = _RepositoryFactory();
        final service = createService(repositories: repositories);
        addTearDown(service.dispose);
        final profile = await service.resolveProfile(
          ModelSettings(modelId: model.id),
        );
        await service.ensureProfile(profile, modelId: model.id);
        final original = repositories.created.single;
        original.closeAcknowledgement = Completer<void>();
        final replacement = service.ensureProfile(
          profile.copyWith(batchSize: 256),
          modelId: model.id,
        );
        final expected = fails
            ? expectLater(replacement, throwsStateError)
            : null;
        await original.closeStarted.future;
        expect(repositories.created, hasLength(1));
        expect(service.repository, same(original));
        if (fails) {
          original.closeAcknowledgement!.completeError(
            StateError('fixture unload failure'),
          );
          await expected;
          expect(repositories.created, hasLength(1));
          expect(service.repository, same(original));
        } else {
          original.closeAcknowledgement!.complete();
          await replacement;
          expect(repositories.created, hasLength(2));
          expect(service.repository, same(repositories.created.last));
        }
      },
    );
  }

  test('GPU prepare failure falls back to a clean CPU runtime', () async {
    final repositories = _RepositoryFactory(failGpu: true);
    final service = createService(repositories: repositories);
    addTearDown(service.dispose);
    const profile = RuntimeProfile(
      contextSize: 1024,
      reservedOutputTokens: 32,
      generationThreads: 2,
      promptThreads: 2,
      batchSize: 128,
      gpuLayers: 4,
      thinkingMode: ThinkingMode.off,
    );

    final result = await service.ensureProfile(profile, modelId: model.id);

    expect(result.nGpuLayers, 0);
    expect(service.effectiveProfile?.gpuLayers, 0);
    expect(repositories.created.map((repo) => repo.nGpuLayers), [4, 0]);
  });

  test(
    'all failed allocation probes surface an error and leave no runtime',
    () async {
      final repositories = _RepositoryFactory(failContextsAbove: 0);
      final service = createService(repositories: repositories);
      addTearDown(service.dispose);

      await expectLater(
        service.ensureProfile(
          const RuntimeProfile(
            contextSize: 2048,
            reservedOutputTokens: 32,
            generationThreads: 1,
            promptThreads: 1,
            batchSize: 128,
            gpuLayers: 0,
            thinkingMode: ThinkingMode.off,
          ),
          modelId: model.id,
        ),
        throwsStateError,
      );
      expect(service.repository, isNull);
    },
  );

  test(
    'unload affects only active model and waits for native cancellation',
    () async {
      final repositories = _RepositoryFactory();
      final service = createService(repositories: repositories);
      addTearDown(service.dispose);
      final profile = await service.resolveProfile(
        ModelSettings(modelId: model.id),
      );
      await service.ensureProfile(profile, modelId: model.id);

      await service.unloadModel('different');
      expect(service.isWarmedUp, isTrue);
      await service.unloadModel(model.id);

      expect(service.isWarmedUp, isFalse);
      expect(repositories.created.single.cancelCalls, 1);
      expect(repositories.created.single.unloadCalls, 1);
    },
  );

  test('unload reserves handoff before asynchronous cleanup', () async {
    final repositories = _RepositoryFactory();
    final service = createService(repositories: repositories);
    addTearDown(service.dispose);
    final profile = await service.resolveProfile(
      ModelSettings(modelId: model.id),
    );
    await service.ensureProfile(profile, modelId: model.id);
    final repository = repositories.created.single;
    final acknowledgement = Completer<void>();
    repository.closeAcknowledgement = acknowledgement;
    final unloading = service.unloadModel(model.id);
    final competing = service.ensureProfile(profile, modelId: model.id);
    final rejected = expectLater(
      competing,
      throwsA(isA<InferenceRuntimeBusy>()),
    );
    acknowledgement.complete();
    await unloading;
    await rejected;
    expect(service.repository, isNull);
    expect(repositories.created, hasLength(1));
    await service.ensureProfile(profile, modelId: model.id);
    expect(repositories.created, hasLength(2));
  });

  test(
    'disposal waits for unload and tuning cannot enter its handoff',
    () async {
      final repositories = _RepositoryFactory();
      final service = createService(repositories: repositories);
      final settings = ModelSettings(modelId: model.id);
      final profile = await service.resolveProfile(settings);
      await service.ensureProfile(profile, modelId: model.id);
      final repository = repositories.created.single;
      final acknowledgement = Completer<void>();
      repository.closeAcknowledgement = acknowledgement;
      final unloading = service.unloadModel(model.id);
      service.scheduleAutoTune(settings);
      await repository.closeStarted.future;
      expect(repositories.created, hasLength(1));
      final duplicate = expectLater(
        service.unloadModel(model.id),
        throwsA(isA<InferenceRuntimeBusy>()),
      );
      var closed = false;
      final closing = service.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      expect(service.repository, same(repository));
      acknowledgement.complete();
      await unloading;
      await duplicate;
      await closing;
      expect(service.repository, isNull);
      expect(repository.unloadCalls, 1);
    },
  );

  test('reset invalidates current key and schedules tuning', () async {
    final profiles = _ProfileStore(cpu: _stored(gpuLayers: 0));
    final service = createService(profiles: profiles);
    addTearDown(service.dispose);
    final settings = ModelSettings(modelId: model.id);
    await service.resolveProfile(settings);

    await service.resetAutoProfile(settings);

    expect(profiles.invalidated, hasLength(1));
    expect(service.lastTunedAt, isNull);
    expect(service.tuningStatus, RuntimeTuningStatus.scheduled);
  });

  test('automatic tuning benchmarks candidates and persists winner', () async {
    final profiles = _ProfileStore();
    final repositories = _RepositoryFactory();
    final service = createService(
      profiles: profiles,
      repositories: repositories,
    );
    addTearDown(service.dispose);
    final settings = ModelSettings(modelId: model.id);
    await service.resolveProfile(settings);

    service.scheduleAutoTune(settings);
    await _waitFor(() => service.tuningStatus == RuntimeTuningStatus.ready);

    expect(profiles.writes, isNotEmpty);
    expect(service.lastTunedAt, DateTime.utc(2026, 1, 2));
    expect(service.fallbackReason, isNull);
    expect(
      repositories.created
          .map((repository) => repository.benchmarkPrompt)
          .toSet(),
      hasLength(1),
    );
    expect(
      repositories.created.every(
        (repository) => repository.requestedOutput == 32,
      ),
      isTrue,
    );
  });

  test('schedule ignores advanced mode and post-disposal requests', () async {
    final service = createService();
    service.scheduleAutoTune(
      ModelSettings(modelId: model.id, tuningMode: TuningMode.advanced),
    );
    expect(service.tuningStatus, RuntimeTuningStatus.idle);
    service.dispose();
    service.scheduleAutoTune(ModelSettings(modelId: model.id));
    expect(service.tuningStatus, RuntimeTuningStatus.idle);
  });

  test(
    'cancellation during capability discovery prevents benchmarks',
    () async {
      final capabilities = _PendingCapabilities();
      final repositories = _RepositoryFactory();
      final profiles = _ProfileStore();
      final service = createService(
        capabilitiesProvider: capabilities,
        repositories: repositories,
        profiles: profiles,
      );
      addTearDown(service.dispose);
      service.scheduleAutoTune(ModelSettings(modelId: model.id));
      await capabilities.started.future;
      final stopped = service.cancelTuning();
      capabilities.result.complete(knownCapabilities);
      await stopped;
      expect(repositories.created, isEmpty);
      expect(profiles.writes, isEmpty);
      expect(service.tuningStatus, RuntimeTuningStatus.cancelled);
    },
  );

  test('cancellation during profile key resolution prevents caching', () async {
    final keyStarted = Completer<void>();
    final version = Completer<String>();
    final profiles = _ProfileStore();
    final service = createService(
      profiles: profiles,
      appVersionResolver: () {
        keyStarted.complete();
        return version.future;
      },
    );
    addTearDown(service.dispose);
    service.scheduleAutoTune(ModelSettings(modelId: model.id));
    await keyStarted.future;
    final stopped = service.cancelTuning();
    version.complete('1.0.0+1');
    await stopped;
    expect(profiles.writes, isEmpty);
    expect(service.tuningStatus, RuntimeTuningStatus.cancelled);
    expect(service.lastTunedAt, isNull);
  });

  test('cancellation during preparation never starts decoding', () async {
    final prepared = Completer<void>();
    final preparing = Completer<void>();
    final repositories = _RepositoryFactory(
      prepareBarrier: prepared,
      prepareStarted: preparing,
    );
    final service = createService(repositories: repositories);
    addTearDown(service.dispose);
    service.scheduleAutoTune(ModelSettings(modelId: model.id));
    await preparing.future;
    final stopped = service.cancelTuning();
    prepared.complete();
    await stopped;
    expect(repositories.created, hasLength(1));
    expect(repositories.created.single.generationCalls, 0);
    expect(repositories.created.single.unloadCalls, 1);
    expect(service.tuningStatus, RuntimeTuningStatus.cancelled);
  });

  test(
    'cancellation during persistence rejects result without invalidating prior cache',
    () async {
      final persisted = Completer<void>();
      final profiles = _ProfileStore(writeBarrier: persisted);
      final service = createService(profiles: profiles);
      addTearDown(service.dispose);
      service.scheduleAutoTune(ModelSettings(modelId: model.id));
      await profiles.writeStarted.future;
      final stopped = service.cancelTuning();
      persisted.complete();
      await stopped;
      expect(profiles.invalidated, isEmpty);
      expect(profiles.writes, isEmpty);
      expect(service.lastTunedAt, isNull);
      expect(service.tuningStatus, RuntimeTuningStatus.cancelled);
    },
  );

  test(
    'unsafe health event requests Stop while tuning preparation is blocked',
    () async {
      final health = StreamController<bool>.broadcast(sync: true);
      addTearDown(health.close);
      final sentinel = _Sentinel(health: health.stream);
      final prepared = Completer<void>();
      final started = Completer<void>();
      final repositories = _RepositoryFactory(
        prepareBarrier: prepared,
        prepareStarted: started,
      );
      final profiles = _ProfileStore();
      final service = createService(
        sentinel: sentinel,
        repositories: repositories,
        profiles: profiles,
      );
      addTearDown(service.dispose);
      service.scheduleAutoTune(ModelSettings(modelId: model.id));
      await started.future;
      sentinel.reason = 'critical pressure';
      health.add(false);
      await Future<void>.delayed(Duration.zero);
      try {
        expect(repositories.created.single.cancelCalls, greaterThan(0));
      } finally {
        final stopped = service.cancelTuning();
        prepared.complete();
        await stopped;
      }
      expect(repositories.created.single.generationCalls, 0);
      expect(profiles.writes, isEmpty);
      expect(service.tuningStatus, RuntimeTuningStatus.cancelled);
      expect(health.hasListener, isFalse);
    },
  );

  test(
    'unsafe state during persistence cannot publish a tuning profile',
    () async {
      final sentinel = _Sentinel();
      final persisted = Completer<void>();
      final profiles = _ProfileStore(writeBarrier: persisted);
      final service = createService(sentinel: sentinel, profiles: profiles);
      addTearDown(service.dispose);
      service.scheduleAutoTune(ModelSettings(modelId: model.id));
      await profiles.writeStarted.future;
      sentinel.reason = 'critical pressure';
      persisted.complete();
      await Future<void>.delayed(Duration.zero);
      try {
        expect(profiles.writes, isEmpty);
        expect(service.lastTunedAt, isNull);
        expect(service.tuningStatus, isNot(RuntimeTuningStatus.ready));
      } finally {
        await service.cancelTuning();
      }
    },
  );
  test('closed safety stream interrupts blocked tuning preparation', () async {
    final health = StreamController<bool>.broadcast(sync: true);
    addTearDown(health.close);
    final prepared = Completer<void>();
    final started = Completer<void>();
    final repositories = _RepositoryFactory(
      prepareBarrier: prepared,
      prepareStarted: started,
    );
    final profiles = _ProfileStore();
    final service = createService(
      sentinel: _Sentinel(health: health.stream),
      repositories: repositories,
      profiles: profiles,
    );
    addTearDown(service.dispose);
    service.scheduleAutoTune(ModelSettings(modelId: model.id));
    await started.future;
    await health.close();
    await Future<void>(() {});
    try {
      expect(repositories.created.single.cancelCalls, 1);
      expect(profiles.writes, isEmpty);
    } finally {
      final stopped = service.cancelTuning();
      prepared.complete();
      await stopped;
    }
    expect(service.tuningStatus, RuntimeTuningStatus.cancelled);
    expect(service.lastTunedAt, isNull);
    expect(repositories.created.single.closed, isTrue);
  });

  for (final telemetryError in [false, true]) {
    test(
      'active tuning safety Stop drains generation (telemetry error: $telemetryError)',
      () async {
        final health = StreamController<bool>.broadcast(sync: true);
        addTearDown(health.close);
        final sentinel = _Sentinel(health: health.stream);
        final generated = Completer<void>();
        final started = Completer<void>();
        final repositories = _RepositoryFactory(
          generationBarrier: generated,
          generationStarted: started,
        );
        final profiles = _ProfileStore();
        final service = createService(
          sentinel: sentinel,
          repositories: repositories,
          profiles: profiles,
        );
        addTearDown(service.dispose);
        service.scheduleAutoTune(ModelSettings(modelId: model.id));
        await started.future;
        if (telemetryError) {
          health.addError(StateError('sensor unavailable'));
        } else {
          sentinel.reason = 'critical pressure';
          health.add(false);
          health.add(true); // Recovery cannot revive the cancelled operation.
          health.add(false);
        }
        final stopped = service.cancelTuning();
        expect(service.cancelTuning(), same(stopped));
        var acknowledged = false;
        final observed = stopped.then((_) => acknowledged = true);
        await Future<void>.delayed(Duration.zero);
        try {
          expect(repositories.created.single.cancelCalls, 1);
          expect(acknowledged, isFalse);
          expect(profiles.writes, isEmpty);
        } finally {
          generated.complete();
          await observed;
        }
        expect(service.tuningStatus, RuntimeTuningStatus.cancelled);
        expect(service.lastTunedAt, isNull);
        expect(profiles.writes, isEmpty);
        expect(repositories.created.single.closed, isTrue);
        expect(health.hasListener, isFalse);
      },
    );
  }
}

class _ShutdownTimer implements Timer {
  _ShutdownTimer(this.callback);
  final void Function() callback;
  bool _active = true;
  @override
  bool get isActive => _active;
  @override
  int get tick => _active ? 0 : 1;
  @override
  void cancel() => _active = false;
  void fire() {
    _active = false;
    callback();
  }
}

StoredRuntimeProfile _stored({required int gpuLayers}) => StoredRuntimeProfile(
  profile: RuntimeProfile(
    contextSize: 2048,
    reservedOutputTokens: 32,
    generationThreads: 2,
    promptThreads: 2,
    batchSize: 128,
    gpuLayers: gpuLayers,
    thinkingMode: ThinkingMode.off,
  ),
  tunedAt: DateTime.utc(2025),
);

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100 && !condition(); attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(condition(), isTrue);
}

final class _Capabilities implements RuntimeCapabilitiesProvider {
  const _Capabilities(this.value);
  final RuntimeCapabilities value;
  @override
  Future<RuntimeCapabilities> snapshot() async => value;
}

final class _PendingCapabilities implements RuntimeCapabilitiesProvider {
  final started = Completer<void>();
  final result = Completer<RuntimeCapabilities>();
  @override
  Future<RuntimeCapabilities> snapshot() {
    started.complete();
    return result.future;
  }
}

final class _ProfileStore implements RuntimeProfileStore {
  _ProfileStore({this.cpu, this.vulkan, this.writeBarrier});
  final Completer<void>? writeBarrier;
  final writeStarted = Completer<void>();
  final StoredRuntimeProfile? cpu;
  final StoredRuntimeProfile? vulkan;
  int reads = 0;
  final List<RuntimeProfileKey> invalidated = [];
  final List<RuntimeProfile> writes = [];

  @override
  Future<bool> writeIfCurrent(
    RuntimeProfileKey key,
    RuntimeProfile profile, {
    required bool Function() isCurrent,
    String? fallbackReason,
  }) async {
    if (!isCurrent()) return false;
    if (!writeStarted.isCompleted) writeStarted.complete();
    await writeBarrier?.future;
    if (!isCurrent()) return false;
    writes.add(profile);
    return true;
  }

  @override
  Future<StoredRuntimeProfile?> read(RuntimeProfileKey key) async {
    reads++;
    return key.backend == 'vulkan' ? vulkan : cpu;
  }

  @override
  Future<void> write(
    RuntimeProfileKey key,
    RuntimeProfile profile, {
    String? fallbackReason,
  }) async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    await writeBarrier?.future;
    writes.add(profile);
  }

  @override
  Future<void> invalidate(RuntimeProfileKey key) async => invalidated.add(key);
  @override
  Future<void> invalidateModel(String modelSha256) async {}
}

final class _Registry implements ModelRegistryService {
  _Registry(this.models);
  final List<ModelDescriptor> models;

  @override
  Future<List<ModelDescriptor>> listModels() async => models;
  @override
  Future<ModelDescriptor?> findById(String id) async {
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }

  @override
  Future<ModelDescriptor?> findByPath(String path) async {
    for (final model in models) {
      if (model.localPath == path) return model;
    }
    return null;
  }

  @override
  Future<ModelDescriptor> requireInstalled(String id) async {
    final value = await findById(id);
    if (value == null || !value.isInstalled) throw StateError('not installed');
    return value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RepositoryFactory {
  _RepositoryFactory({
    this.failContextsAbove,
    this.failGpu = false,
    this.prepareBarrier,
    this.prepareStarted,
    this.reportedMismatch,
    this.generationBarrier,
    this.generationStarted,
    this.reportedPromptTokens = 256,
  });
  final Completer<void>? prepareBarrier;
  final Completer<void>? prepareStarted;
  final int? failContextsAbove;
  final bool failGpu;
  final String? reportedMismatch;
  final Completer<void>? generationBarrier;
  final Completer<void>? generationStarted;
  final int reportedPromptTokens;
  final List<_Repository> created = [];

  LlamaCppChatRepository create({
    required String modelPath,
    required int contextSize,
    required int batchSize,
    required int threads,
    required int promptThreads,
    required int gpuLayers,
    required bool supportsThinking,
    required RuntimeOperationKind runtimeOperationKind,
  }) {
    final repository = _Repository(
      contextSizeValue: contextSize,
      batchSizeValue: batchSize,
      threadsValue: threads,
      promptThreadsValue: promptThreads,
      reportedMismatch: reportedMismatch,
      gpuLayersValue: gpuLayers,
      runtimeOperationKindValue: runtimeOperationKind,
      prepareBarrier: prepareBarrier,
      prepareStarted: prepareStarted,
      generationBarrier: generationBarrier,
      generationStarted: generationStarted,
      reportedPromptTokens: reportedPromptTokens,
      failPrepare:
          (failContextsAbove != null && contextSize > failContextsAbove!) ||
          (failGpu && gpuLayers > 0),
    );
    created.add(repository);
    return repository;
  }
}

final class _Repository implements LlamaCppChatRepository {
  _Repository({
    required this.contextSizeValue,
    required this.batchSizeValue,
    required this.threadsValue,
    required this.promptThreadsValue,
    required this.gpuLayersValue,
    required this.runtimeOperationKindValue,
    required this.failPrepare,
    this.prepareBarrier,
    this.prepareStarted,
    this.reportedMismatch,
    this.generationBarrier,
    this.generationStarted,
    this.reportedPromptTokens = 256,
  });

  final Completer<void>? prepareBarrier;
  final Completer<void>? prepareStarted;
  final String? reportedMismatch;
  final Completer<void>? generationBarrier;
  final Completer<void>? generationStarted;
  final int reportedPromptTokens;
  int generationCalls = 0;
  String? benchmarkPrompt;
  int? requestedOutput;
  bool? tokenizeThink;
  bool? generateThink;

  final int contextSizeValue;
  final int batchSizeValue;
  final int threadsValue;
  final int promptThreadsValue;
  final int gpuLayersValue;
  final RuntimeOperationKind runtimeOperationKindValue;
  RuntimeOperationKind? lastPreparationKind;
  final bool failPrepare;
  int prepareCalls = 0;
  int cancelCalls = 0;
  int unloadCalls = 0;
  int disposeCalls = 0;
  bool closed = false;
  bool _cleanupFailed = false;
  int recoveryCalls = 0;
  bool retainFailureAfterRecovery = false;
  Completer<RuntimeRecoveryOutcome>? recoveryAcknowledgement;
  final recoveryStarted = Completer<void>();
  Completer<void>? closeAcknowledgement;
  final closeStarted = Completer<void>();
  Future<void>? _closeFuture;
  @override
  bool get isDisposed => closed;
  @override
  bool get cleanupFailed => _cleanupFailed;

  @override
  int get contextSize => contextSizeValue;
  @override
  int get batchSize => batchSizeValue;
  @override
  int? get threads => threadsValue;
  @override
  int? get promptThreads => promptThreadsValue;
  @override
  int get nGpuLayers => gpuLayersValue;
  @override
  RuntimeOperationKind get runtimeOperationKind => runtimeOperationKindValue;
  @override
  LlamaCppInferenceMetrics get lastMetrics => LlamaCppInferenceMetrics(
    configuration: reportedMismatch == 'missing'
        ? null
        : InferenceRuntimeConfiguration(
            contextSize:
                contextSizeValue + (reportedMismatch == 'context' ? 1 : 0),
            batchSize: batchSizeValue + (reportedMismatch == 'batch' ? 1 : 0),
            generationThreads:
                threadsValue + (reportedMismatch == 'generation' ? 1 : 0),
            promptThreads:
                promptThreadsValue + (reportedMismatch == 'prompt' ? 1 : 0),
          ),
    promptTokens: reportedPromptTokens,
    generatedTokens: 32,
    modelLoadMicros: 1,
    contextInitMicros: 1,
    promptEvalMicros: 1000000,
    generationMicros: 1000000,
    timeToFirstTokenMicros: 1,
    completionReason: 'output_limit',
  );

  @override
  Future<void> prepare({RuntimeOperationKind? kind}) async {
    prepareCalls++;
    lastPreparationKind = kind ?? runtimeOperationKind;
    if (prepareStarted != null && !prepareStarted!.isCompleted) {
      prepareStarted!.complete();
    }
    await prepareBarrier?.future;
    if (failPrepare) throw StateError('allocation failed');
  }

  @override
  Future<void> cancelActiveInference() async => cancelCalls++;
  @override
  Future<void> unloadPersistentModel() async => unloadCalls++;
  @override
  void dispose() => disposeCalls++;
  @override
  Future<void> close() => _closeFuture ??= _finishClose();

  Future<void> _finishClose() async {
    closed = true;
    if (!closeStarted.isCompleted) closeStarted.complete();
    cancelCalls++;
    try {
      await closeAcknowledgement?.future;
    } catch (_) {
      _cleanupFailed = true;
      rethrow;
    }
    unloadCalls++;
    disposeCalls++;
  }

  @override
  Future<RuntimeRecoveryOutcome> recoverAfterClose() async {
    recoveryCalls++;
    if (!recoveryStarted.isCompleted) recoveryStarted.complete();
    final result = await recoveryAcknowledgement!.future;
    if (result == RuntimeRecoveryOutcome.recovered &&
        !retainFailureAfterRecovery) {
      _cleanupFailed = false;
      _closeFuture = Future<void>.value();
      unloadCalls++;
      disposeCalls++;
    }
    return result;
  }

  @override
  Future<int> countChatTokens(
    List<LLMMessage> messages, {
    bool think = false,
  }) async {
    tokenizeThink = think;
    final content = messages.last.content!;
    if (content.startsWith(RuntimeBenchmarkPolicy.instruction)) {
      return 32 +
          content.substring(RuntimeBenchmarkPolicy.instruction.length).length ~/
              RuntimeBenchmarkPolicy.paddingUnit.length;
    }
    return 128;
  }

  @override
  Stream<LLMChunk> streamChatWithGenerationOptions(
    String model, {
    required List<LLMMessage> messages,
    bool think = false,
    List<LLMTool> tools = const [],
    dynamic extra,
    LLMChatOptions? options,
    GenerationOptions? generationOptions,
  }) async* {
    generationCalls++;
    generateThink = think;
    benchmarkPrompt = messages.last.content;
    requestedOutput = generationOptions?.maxTokens;
    if (generationStarted != null && !generationStarted!.isCompleted)
      generationStarted!.complete();
    await generationBarrier?.future;
    yield LLMChunk(
      model: model,
      createdAt: DateTime.utc(2026),
      message: LLMChunkMessage(content: 'ok', role: LLMRole.assistant),
      done: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Sentinel implements HardwareSentinelService {
  _Sentinel({this.reason, Stream<bool>? health})
    : health = health ?? Stream<bool>.multi((_) {}, isBroadcast: true);
  String? reason;
  final Stream<bool> health;
  @override
  bool isSafeForHeavyOperation() => reason == null;
  @override
  String? unsafeReasonHeavy() => reason;
  @override
  Stream<bool> get onHealthChanged => health;
  @override
  bool get isDisposed => false;
  @override
  int? get currentLevel => 100;
  @override
  bool? get isCharging => true;
  @override
  bool? get isInSaveMode => false;
  @override
  ConnectivityResult? get connectivityType => ConnectivityResult.wifi;
  @override
  int get memoryPressureLevel => 0;
  @override
  bool isSafeForDownload() => reason == null;
  @override
  String? unsafeReasonDownload() => reason;
  @override
  void checkHeavyOperation() {}
  @override
  void checkDownload() {}
  @override
  Future<void> init() async {}
  @override
  void dispose() {}
}
