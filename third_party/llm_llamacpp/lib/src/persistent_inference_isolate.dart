import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:llm_llamacpp/src/backend_initializer.dart';
import 'package:llm_llamacpp/src/exceptions.dart';
import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';
import 'package:llm_llamacpp/src/bindings/llama_bindings_compat.dart';
import 'package:llm_llamacpp/src/generation_options.dart';
import 'package:llm_llamacpp/src/isolate_messages.dart';
import 'package:llm_llamacpp/src/loader/loader.dart';
import 'package:llm_llamacpp/src/native_log.dart';
import 'package:llm_llamacpp/src/native_runtime_bridge.dart';
import 'package:llm_llamacpp/src/prompt_batching.dart';
import 'package:llm_llamacpp/src/runtime_session_reservation.dart';
import 'package:llm_llamacpp/src/runtime_initialization_guard.dart';
import 'package:llm_llamacpp/src/runtime_progress.dart';
import 'package:llm_llamacpp/src/runtime_cancellation_control.dart';
import 'package:llm_llamacpp/src/runtime_request_finalizer.dart';
import 'package:llm_llamacpp/src/runtime_cleanup_quarantine.dart';
import 'package:llm_llamacpp/src/runtime_cleanup_fault.dart';
import 'package:llm_llamacpp/src/runtime_watchdog_policy.dart';
import 'package:llm_llamacpp/src/runtime_native_termination.dart';
import 'package:llm_llamacpp/src/runtime_shutdown_waiter.dart';
import 'package:llm_llamacpp/src/native_template_applier.dart';
import 'package:llm_llamacpp/src/stop_sequence_prefix.dart';
import 'package:llm_llamacpp/src/inference_output_timing.dart';

part 'inference_isolate_handler.dart';
part 'inference_isolate_messages.dart';
part 'inference_sampler_config.dart';
part 'inference_token_generator.dart';

/// Manages a persistent inference isolate for running LLM inference.
///
/// This follows the pattern used by fllama: a single persistent isolate
/// handles all inference requests, avoiding the issues caused by
/// re-initializing the library in multiple isolates.
///
/// The isolate is lazily initialized on first use and stays alive for the
/// lifetime of the application. This is important because:
/// 1. Native library state (backends) is shared across the process
/// 2. Re-loading libraries in separate isolates causes FFI issues on Android
/// 3. A persistent isolate avoids the overhead of spawning new isolates
class PersistentInferenceIsolate {
  PersistentInferenceIsolate._();

  static final PersistentInferenceIsolate _instance =
      PersistentInferenceIsolate._();
  static PersistentInferenceIsolate get instance => _instance;

  SendPort? _helperSendPort;
  Isolate? _helperIsolate;
  ReceivePort? _mainReceivePort;
  RuntimeInitializationGuard _initialization = RuntimeInitializationGuard(
    timeout: NativeRuntimePolicy.initializationTimeout,
  );

  /// Mapping from request IDs to response controllers
  final Map<int, StreamController<dynamic>> _pendingRequests = {};
  final Map<int, Object?> _requestOwners = {};
  final _nativeTerminations = RuntimeNativeTermination();
  late final _cleanupQuarantine = RuntimeCleanupQuarantine(
    releaseHandle: _cancellations.finish,
  );
  final _cancellationClock = Stopwatch()..start();
  late final _cancellations = RuntimeCancellationControl(
    readMonotonicMicros: () => _cancellationClock.elapsedMicroseconds,
    requestCancel: (address) => _nativeControl.requestCancel(
      ffi.Pointer<ffi.Void>.fromAddress(address),
    ),
    releaseHandle: (address) => _nativeControl.destroyCancelToken(
      ffi.Pointer<ffi.Void>.fromAddress(address),
    ),
  );
  int _nextRequestId = 0;
  int _helperGeneration = 0;
  final _preparationGuards = <int, RuntimeInitializationGuard>{};
  final _preparationOwners = <int, Object?>{};
  final _preparationAdmissions = <int, _PreparationAdmission>{};
  final _preparationKinds = <int, RuntimeOperationKind>{};
  final _requestKinds = <int, RuntimeOperationKind>{};
  int? _activeRequestId;
  final _reservation = RuntimeSessionReservation();
  final _closedOwners = Expando<bool>();
  final Set<int> _unloadRequests = {};

  Future<void> releaseOwnedContext(Object owner) async {
    await drainOwner(owner);
    if (_reservation.needsRecovery ||
        _nativeTerminations.needsRecovery ||
        _preparationGuards.values.any((guard) => guard.needsRecovery)) {
      if (!_reservation.requireOwnedRecovery(owner))
        throw InferenceRecoveryRequired();
      if (await recover(owner) != RuntimeRecoveryOutcome.recovered) {
        throw InferenceRecoveryRequired();
      }
      return;
    }
    if (_reservation.ownsContext(owner)) await unload(owner: owner);
  }

  void revokeOwner(Object owner) => _closedOwners[owner] = true;

  Future<void> drainOwner(Object owner) => _nativeTerminations.drain(owner);

  RuntimeReservationState get reservationState => _reservation.state;

  bool requireOwnedRecovery(Object owner) =>
      _reservation.requireOwnedRecovery(owner);

  RuntimeOperationSnapshot get operationSnapshot {
    final requestId =
        _activeRequestId ??
        (_pendingRequests.isNotEmpty
            ? _pendingRequests.keys.first
            : _preparationOwners.isNotEmpty
            ? _preparationOwners.keys.first
            : _cleanupQuarantine.firstRequestId);
    return _reservation.snapshot(
      nativeRequestId: requestId,
      activeOwner: requestId == null
          ? null
          : _requestOwners[requestId] ?? _preparationOwners[requestId],
      activeKind: requestId == null
          ? null
          : _requestKinds[requestId] ?? _preparationKinds[requestId],
      cancellationRequested:
          requestId != null && _cancellations.isRequested(requestId),
      cancellationHandleAvailable:
          requestId != null && _cancellations.hasHandle(requestId),
      initializationPending:
          _initialization.isPending ||
          _preparationAdmissions.isNotEmpty ||
          _preparationGuards.values.any((guard) => guard.isPending),
      initializationRecoveryRequired:
          _initialization.needsRecovery ||
          _preparationGuards.values.any((guard) => guard.needsRecovery),
      cancellationRecoveryRequired: _nativeTerminations.needsRecovery,
    );
  }

  bool canAccess(Object? owner) =>
      _reservation.canAccess(owner) &&
      _requestOwners.values.every((candidate) => identical(candidate, owner)) &&
      _cleanupQuarantine.canAccess(owner) &&
      _nativeTerminations.canAccessRecovery(owner) &&
      _preparationOwners.values.every(
        (candidate) => identical(candidate, owner),
      );

  void _checkOwner(Object? owner) {
    if (!canAccess(owner)) throw InferenceRuntimeBusy();
  }

  void _checkOperation(Object? owner) {
    if (owner != null && _closedOwners[owner] == true) {
      throw InferenceRepositoryDisposed();
    }
    _checkOwner(owner);
    if (_initialization.needsRecovery) throw InferenceRecoveryRequired();
    if (_reservation.needsRecovery) throw InferenceRecoveryRequired();
    if (_nativeTerminations.needsRecovery) throw InferenceRecoveryRequired();
    if (_cleanupQuarantine.hasRequests) throw InferenceRecoveryRequired();
    if (_preparationGuards.values.any((guard) => guard.needsRecovery))
      throw InferenceRecoveryRequired();
  }

  /// Reserve the single context across prepare/tokenize/generate/cleanup.
  /// Acquisition never queues behind an existing request or reservation.
  Future<T> withExclusiveSession<T>(
    Object owner,
    Future<T> Function() action, {
    RuntimeOperationKind kind = RuntimeOperationKind.interactive,
  }) async {
    _checkOperation(owner);
    if (_pendingRequests.isNotEmpty) {
      throw InferenceRuntimeBusy();
    }
    _reservation.acquire(owner, kind);
    try {
      return await action();
    } finally {
      // Keep ownership on failed cleanup while native requests remain alive.
      _reservation.finish(
        owner,
        terminationConfirmed:
            _pendingRequests.isEmpty &&
            !_nativeTerminations.needsRecovery &&
            !_cleanupQuarantine.hasRequests &&
            !_preparationGuards.values.any(
              (guard) => guard.isPending || guard.needsRecovery,
            ) &&
            !_initialization.isPending &&
            !_initialization.needsRecovery,
      );
    }
  }

  Future<RuntimeRecoveryOutcome> recover(Object owner) =>
      _reservation.recover(owner, () async {
        _checkOwner(owner);
        // A stopped Dart waiter is not evidence of native termination. Retain
        // the reservation until every owned response has reached its terminal
        // event, then require native context destruction to acknowledge too.
        await cancel(null, owner);
        await _nativeTerminations.drain(owner);
        await unload(owner: owner);
        return _pendingRequests.isEmpty && !_cleanupQuarantine.hasRequests;
      });

  NativeRuntimeBridge? _controlBridge;

  NativeRuntimeBridge get _nativeControl {
    return _controlBridge ??= NativeRuntimeBridge(
      Platform.isAndroid
          ? ffi.DynamicLibrary.open('libllama.so')
          : loadLlamaLibrary(),
    );
  }

  /// Initialize the persistent isolate if not already running.
  Future<void> _ensureInitialized() =>
      _initialization.ensure(_initializeHelper);

  Future<void> _initializeHelper() async {
    final generation = ++_helperGeneration;
    final completer = Completer<Object>();
    _mainReceivePort = ReceivePort();

    _mainReceivePort!.listen((message) {
      if (generation != _helperGeneration) return;
      if (message is _InitializationProgress) {
        _initialization.observeProgress(message.progress);
        return;
      }
      if (message is SendPort || message is _InitializationFailure) {
        if (!completer.isCompleted) completer.complete(message);
        return;
      }

      // Handle responses from the helper isolate
      if (message is _IsolateResponse) {
        if (message.payload is _CancellationHandle) {
          _cancellations.attachHandle(
            message.requestId,
            (message.payload as _CancellationHandle).address,
          );
          return;
        }
        final controller = _pendingRequests[message.requestId];
        if (controller != null) {
          if (message.isComplete && !message.cleanupConfirmed) {
            final owner = _requestOwners[message.requestId];
            _cleanupQuarantine.retain(message.requestId, owner);
            if (owner != null) _reservation.requireOwnedRecovery(owner);
          }
          final cancellationMicros =
              message.isComplete && message.cleanupConfirmed
              ? _cancellations.finish(message.requestId)
              : null;
          final payload = message.payload is InferenceCancelled
              ? (message.payload as InferenceCancelled).withAcknowledgement(
                  cancellationMicros ?? 0,
                )
              : message.payload;
          var deliveredPayload = payload;
          if (message.isComplete) {
            final outcome = _nativeTerminations.acknowledge(
              message.requestId,
              cleanupConfirmed: message.cleanupConfirmed,
              payload: payload,
            );
            if (outcome == NativeTerminationOutcome.observerFailed) {
              final owner = _requestOwners[message.requestId];
              _cleanupQuarantine.retain(message.requestId, owner);
              if (owner != null) _reservation.requireOwnedRecovery(owner);
              deliveredPayload = InferenceCleanupRequired('terminal_observer');
            }
          }
          if (message.isComplete &&
              _unloadRequests.contains(message.requestId) &&
              (!message.cleanupConfirmed || deliveredPayload is! _Prepared)) {
            // A terminal reply is not necessarily proof of context destruction.
            // Failed/malformed unload receipts retain the same owner until an
            // explicit successful retry, never "anything except an error".
            final owner = _requestOwners[message.requestId];
            _cleanupQuarantine.retain(message.requestId, owner);
            if (owner != null) _reservation.requireOwnedRecovery(owner);
            if (deliveredPayload is! InferenceError) {
              deliveredPayload = InferenceCleanupRequired(
                'unload_acknowledgement',
              );
            }
          }
          controller.add(deliveredPayload);
          if (message.isComplete) {
            if (_unloadRequests.remove(message.requestId) &&
                message.cleanupConfirmed &&
                deliveredPayload is _Prepared) {
              final owner = _requestOwners[message.requestId];
              for (final id in _cleanupQuarantine.confirmOwnerUnload(owner)) {
                _preparationGuards.remove(id);
                _preparationOwners.remove(id);
                _preparationKinds.remove(id);
                if (_activeRequestId == id) _activeRequestId = null;
              }
              for (final id in _preparationOwners.keys.toList()) {
                if (identical(_preparationOwners[id], owner)) {
                  _preparationGuards.remove(id);
                  _preparationOwners.remove(id);
                  _preparationKinds.remove(id);
                }
              }
              if (_reservation.ownsContext(owner))
                _reservation.releaseContext(owner);
            }
            controller.close();
            _pendingRequests.remove(message.requestId);
            _requestOwners.remove(message.requestId);
            _requestKinds.remove(message.requestId);
            if (message.cleanupConfirmed &&
                _activeRequestId == message.requestId) {
              _activeRequestId = null;
            }
          }
        }
      }
    });

    NativeLog.debug('[PersistentInferenceIsolate] Spawning helper isolate...');
    _helperIsolate = await Isolate.spawn(
      _isolateMain,
      _HelperStart(_mainReceivePort!.sendPort, generation),
    );

    try {
      final handshake = await completer.future;
      if (handshake is _InitializationFailure) {
        throw StateError(handshake.message);
      }
      _helperSendPort = handshake as SendPort;
      NativeLog.debug('[PersistentInferenceIsolate] Helper isolate ready');
    } catch (_) {
      // Only an explicit initialization failure reaches this branch. A waiting
      // timeout is handled by the guard without killing or forgetting native work.
      _mainReceivePort?.close();
      _mainReceivePort = null;
      rethrow;
    }
  }

  /// Run inference and return a stream of responses.
  ///
  /// Verified thinking templates use the locked upstream Jinja renderer.
  /// Other messages use the native predefined-template API; absent messages
  /// use the caller's pre-formatted [prompt].
  Stream<dynamic> runInference({
    required String modelPath,
    required String prompt,
    required List<String> stopTokens,
    required int contextSize,
    required int batchSize,
    required int nGpuLayers,
    required GenerationOptions options,
    Object? owner,
    int? threads,
    int? promptThreads,
    String? loraPath,
    double loraScale = 1.0,
    List<IsolateMessage>? messages,
    bool? thinking,
    RuntimeCleanupFault? cleanupFault,
    void Function(Object?)? onTerminal,
    RuntimeOperationKind kind = RuntimeOperationKind.interactive,
  }) async* {
    options.validate();
    cleanupFault?.validate();
    _checkOperation(owner);
    _reservation.claimContext(owner);
    if (_pendingRequests.isNotEmpty || _preparationAdmissions.isNotEmpty) {
      throw InferenceRuntimeBusy();
    }

    final requestId = _nextRequestId++;
    _activeRequestId = requestId;
    // ignore: close_sinks
    final controller = StreamController<dynamic>();
    _pendingRequests[requestId] = controller;
    _requestOwners[requestId] = owner;
    _requestKinds[requestId] = kind;
    _cancellations.register(requestId);
    final admission = _PreparationAdmission();
    _preparationAdmissions[requestId] = admission;
    _preparationOwners[requestId] = owner;
    _preparationKinds[requestId] = kind;

    var cancelledDuringInitialization = false;
    var cancellationAcknowledgementMicros = 0;
    try {
      // Admit and identify the request before helper initialization. Stop can
      // now wait on this exact operation instead of seeing anonymous startup.
      await _ensureInitialized();
      if (_cancellations.isRequested(requestId)) {
        cancellationAcknowledgementMicros =
            _cancellations.finish(requestId) ?? 0;
        _finishAdmission(requestId, admission, finishCancellation: false);
        _discardUnstartedRequest(requestId, controller);
        cancelledDuringInitialization = true;
      } else {
        _checkOperation(owner);
        _leaveInitializationAdmission(requestId, admission);
        _nativeTerminations.register(requestId, owner, onTerminal: onTerminal);
      }
    } catch (_) {
      _retainOrFinishAdmission(requestId, admission);
      unawaited(
        admission.initializationSettled.future.then<void>((_) async {
          _finishAdmission(requestId, admission);
          _discardUnstartedRequest(requestId, controller);
        }),
      );
      rethrow;
    }
    if (cancelledDuringInitialization) {
      unawaited(controller.close());
      yield InferenceCancelled(
        acknowledgementMicros: cancellationAcknowledgementMicros,
      );
      return;
    }

    // Send the request to the helper isolate
    _helperSendPort!.send(
      _InferenceRequestMessage(
        requestId: requestId,
        modelPath: modelPath,
        prompt: prompt,
        stopTokens: stopTokens,
        contextSize: contextSize,
        batchSize: batchSize,
        nGpuLayers: nGpuLayers,
        options: options,
        threads: threads,
        promptThreads: promptThreads,
        loraPath: loraPath,
        loraScale: loraScale,
        messages: messages,
        thinking: thinking,
        cleanupFault: cleanupFault,
      ),
    );

    try {
      yield* controller.stream;
    } finally {
      // Stream cancellation must stop native work; dropping the Dart
      // subscription alone is not cancellation.
      if (_pendingRequests.containsKey(requestId)) {
        unawaited(
          cancel(requestId, owner).then<void>(
            (_) {},
            onError: (Object _, StackTrace __) {
              // Detached stream cleanup cannot discard a failed Stop. Keep
              // the typed diagnostic in the snapshot, without private logs.
              _nativeTerminations.retainUnconfirmed(requestId, owner);
            },
          ),
        );
      }
    }
  }

  Future<void> prepare({
    required String modelPath,
    required int contextSize,
    required int batchSize,
    required int nGpuLayers,
    RuntimeWatchdogPolicy watchdogPolicy =
        RuntimeWatchdogPolicy.modelPreparation,
    Object? owner,
    int? threads,
    int? promptThreads,
    RuntimeOperationKind kind = RuntimeOperationKind.warmup,
  }) async {
    watchdogPolicy.validate();
    _checkOperation(owner);
    _reservation.claimContext(owner);
    if (_pendingRequests.isNotEmpty || _preparationOwners.isNotEmpty) {
      throw InferenceRuntimeBusy();
    }
    final requestId = _nextRequestId++;
    final admission = _PreparationAdmission();
    _preparationAdmissions[requestId] = admission;
    _preparationOwners[requestId] = owner;
    _preparationKinds[requestId] = kind;
    _cancellations.register(requestId);
    try {
      await _ensureInitialized();
      if (_cancellations.isRequested(requestId)) {
        throw InferencePreparationCancelled();
      }
      admission.settleInitialization();
      _preparationAdmissions.remove(requestId);
      _checkOperation(owner);
      if (_pendingRequests.isNotEmpty) {
        throw InferenceRuntimeBusy();
      }
    } catch (_) {
      _retainOrFinishAdmission(requestId, admission);
      rethrow;
    }
    // ignore: close_sinks
    final controller = StreamController<dynamic>();
    _pendingRequests[requestId] = controller;
    _requestOwners[requestId] = owner;
    _requestKinds[requestId] = kind;
    _nativeTerminations.register(requestId, owner);
    final guard = RuntimeInitializationGuard(
      timeout: watchdogPolicy.noProgressTimeout,
      maximumDuration: watchdogPolicy.maximumDuration,
      onRecoveryRequired: () {
        _cleanupQuarantine.retain(requestId, owner);
        if (owner != null) _reservation.requireOwnedRecovery(owner);
        _cancellations.request(requestId);
      },
    );
    _preparationGuards[requestId] = guard;
    _preparationOwners[requestId] = owner;
    var dispatched = false;
    final events = controller.stream.forEach((event) {
      if (event is RuntimeProgress) guard.observeProgress(event);
      if (event is InferenceError) throw StateError(event.error);
      if (event is InferenceCancelled) throw InferencePreparationCancelled();
    });
    final waiting = guard.ensure(() {
      _helperSendPort!.send(
        _PrepareRequestMessage(
          requestId: requestId,
          modelPath: modelPath,
          contextSize: contextSize,
          batchSize: batchSize,
          nGpuLayers: nGpuLayers,
          threads: threads,
          promptThreads: promptThreads,
        ),
      );
      dispatched = true;
      return events;
    });
    unawaited(
      guard
          .settleForCleanup(() => events)
          .then<void>(
            (_) {
              if (!guard.needsRecovery &&
                  identical(_preparationGuards[requestId], guard)) {
                _preparationGuards.remove(requestId);
                _preparationOwners.remove(requestId);
                _preparationKinds.remove(requestId);
              }
            },
            onError: (Object error, StackTrace stack) {
              // Failure is retained by the guard and quarantine. If dispatch never
              // happened, no native writer exists; retire only the unused waiter.
              if (!dispatched) {
                // No native writer was started; do not strand its receipt.
                _nativeTerminations.acknowledge(
                  requestId,
                  cleanupConfirmed: true,
                );
                _pendingRequests.remove(requestId);
                _requestOwners.remove(requestId);
                _requestKinds.remove(requestId);
                unawaited(controller.close());
              }
            },
          ),
    );
    await waiting;
  }

  Future<void> cancel([int? requestId, Object? owner]) async {
    _checkOwner(owner);
    final preparations = _preparationOwners.entries.where(
      (entry) => identical(entry.value, owner),
    );
    final id =
        requestId ??
        _activeRequestId ??
        (preparations.isEmpty ? null : preparations.first.key);
    if (id == null) return;
    if (_requestOwners.containsKey(id) &&
        !identical(_requestOwners[id], owner)) {
      throw InferenceRuntimeBusy();
    }
    if (!_nativeTerminations.contains(id)) {
      final admission = _preparationAdmissions[id];
      if (admission == null) return;
      if (!_cancellations.isRequested(id)) _cancellations.request(id);
      final waiter = admission.cancellationWaiter ??= RuntimeShutdownWaiter(
        timeout: RuntimeWatchdogDefaults.noProgressTimeout,
        onUnconfirmed: () {
          if (owner != null) _reservation.requireOwnedRecovery(owner);
        },
        shutdown: () => admission.initializationSettled.future,
      );
      await waiter.wait();
      return;
    }
    // Observe native terminal acknowledgement, never stream delivery. An
    // await-for consumer may itself be paused awaiting this cancellation.
    final acknowledgement = _nativeTerminations.waitFor(id, owner);
    if (!_cancellations.isRequested(id)) {
      _cancellations.request(id);
      _helperSendPort?.send(_CancelRequestMessage(id));
    }
    await acknowledgement;
    // Preparation expiry retains context quarantine until unload. A confirmed
    // terminal receipt still proves decoding/loading stopped; do not prevent
    // its owner from progressing to that acknowledged unload.
    if (_cleanupQuarantine.contains(id) &&
        !_preparationGuards.containsKey(id)) {
      throw InferenceRecoveryRequired();
    }
  }

  void _retainOrFinishAdmission(
    int requestId,
    _PreparationAdmission admission,
  ) {
    if (!identical(_preparationAdmissions[requestId], admission)) return;
    if (!_initialization.isPending) {
      _finishAdmission(requestId, admission);
      return;
    }
    final initialization = _initialization.settleForCleanup(_initializeHelper);
    unawaited(
      initialization.then<void>(
        (_) => _finishAdmission(requestId, admission),
        onError: (Object _, StackTrace __) =>
            _finishAdmission(requestId, admission),
      ),
    );
  }

  void _leaveInitializationAdmission(
    int requestId,
    _PreparationAdmission admission,
  ) {
    if (!identical(_preparationAdmissions.remove(requestId), admission)) return;
    _preparationOwners.remove(requestId);
    _preparationKinds.remove(requestId);
    admission.settleInitialization();
  }

  void _finishAdmission(
    int requestId,
    _PreparationAdmission admission, {
    bool finishCancellation = true,
  }) {
    if (!identical(_preparationAdmissions.remove(requestId), admission)) return;
    _preparationOwners.remove(requestId);
    _preparationKinds.remove(requestId);
    if (finishCancellation) _cancellations.finish(requestId);
    admission.settleInitialization();
  }

  void _discardUnstartedRequest(
    int requestId,
    StreamController<dynamic> controller,
  ) {
    if (identical(_pendingRequests[requestId], controller)) {
      _pendingRequests.remove(requestId);
    }
    _requestOwners.remove(requestId);
    _requestKinds.remove(requestId);
    if (_activeRequestId == requestId) _activeRequestId = null;
    unawaited(controller.close());
  }

  Future<void> unload({
    Object? owner,
    RuntimeOperationKind kind = RuntimeOperationKind.disposal,
  }) async {
    _checkOwner(owner);
    await _initialization.settleForCleanup(_initializeHelper);
    _checkOwner(owner);
    await cancel(null, owner);
    _checkOwner(owner);
    if (_pendingRequests.isNotEmpty) throw InferenceRuntimeBusy();
    final requestId = _nextRequestId++;
    // ignore: close_sinks
    final controller = StreamController<dynamic>();
    _pendingRequests[requestId] = controller;
    _requestOwners[requestId] = owner;
    _requestKinds[requestId] = kind;
    _nativeTerminations.register(requestId, owner);
    _unloadRequests.add(requestId);
    _helperSendPort!.send(_UnloadRequestMessage(requestId));
    var acknowledged = false;
    await for (final event in controller.stream) {
      if (event is! _Prepared) throw InferenceRecoveryRequired();
      acknowledged = true;
    }
    if (!acknowledged) throw InferenceRecoveryRequired();
    _initialization.confirmCleanup();
    _nativeTerminations.confirmRecovery(owner);
  }

  Future<int> countChatTokens(
    List<IsolateMessage> messages, {
    bool? thinking,
    Object? owner,
    RuntimeOperationKind kind = RuntimeOperationKind.interactive,
  }) async {
    _checkOperation(owner);
    _reservation.claimContext(owner);
    if (_pendingRequests.isNotEmpty || _preparationAdmissions.isNotEmpty) {
      throw InferenceRuntimeBusy();
    }
    final requestId = _nextRequestId++;
    // ignore: close_sinks
    final controller = StreamController<dynamic>();
    _pendingRequests[requestId] = controller;
    _activeRequestId = requestId;
    _requestOwners[requestId] = owner;
    _requestKinds[requestId] = kind;
    _cancellations.register(requestId);
    final admission = _PreparationAdmission();
    _preparationAdmissions[requestId] = admission;
    _preparationOwners[requestId] = owner;
    _preparationKinds[requestId] = kind;
    try {
      await _ensureInitialized();
      if (_cancellations.isRequested(requestId)) {
        _cancellations.finish(requestId);
        _finishAdmission(requestId, admission, finishCancellation: false);
        _discardUnstartedRequest(requestId, controller);
        throw InferencePreparationCancelled();
      }
      _checkOperation(owner);
      _leaveInitializationAdmission(requestId, admission);
    } catch (_) {
      _retainOrFinishAdmission(requestId, admission);
      unawaited(
        admission.initializationSettled.future.then<void>((_) {
          _finishAdmission(requestId, admission);
          _discardUnstartedRequest(requestId, controller);
        }),
      );
      rethrow;
    }
    _nativeTerminations.register(requestId, owner);
    _helperSendPort!.send(
      _TokenizeRequestMessage(
        requestId: requestId,
        messages: messages,
        thinking: thinking,
      ),
    );
    await for (final event in controller.stream) {
      if (event is _TokenCount) return event.value;
      if (event is InferenceError) throw StateError(event.error);
    }
    throw StateError('Tokenizer returned no result');
  }

  /// Shutdown the persistent isolate.
  void dispose() {
    _checkOperation(null);
    if (_initialization.isPending ||
        _pendingRequests.isNotEmpty ||
        _nativeTerminations.hasPending ||
        _nativeTerminations.needsRecovery) {
      throw InferenceRuntimeBusy();
    }
    _helperGeneration++;
    _helperIsolate?.kill();
    _helperIsolate = null;
    _mainReceivePort?.close();
    _mainReceivePort = null;
    _helperSendPort = null;
    for (final controller in _pendingRequests.values) {
      // ignore: unawaited_futures
      controller.close();
    }
    _pendingRequests.clear();
    _requestOwners.clear();
    _requestKinds.clear();
    _preparationKinds.clear();
    _cancellations.clear();
    _activeRequestId = null;
    _controlBridge = null;
    _initialization = RuntimeInitializationGuard(
      timeout: NativeRuntimePolicy.initializationTimeout,
    );
  }
}

abstract final class NativeRuntimePolicy {
  static const initializationTimeout =
      RuntimeWatchdogDefaults.backendInitializationTimeout;
}

class _PreparationAdmission {
  final initializationSettled = Completer<void>();
  RuntimeShutdownWaiter? cancellationWaiter;

  void settleInitialization() {
    if (!initializationSettled.isCompleted) initializationSettled.complete();
  }
}

class _HelperStart {
  const _HelperStart(this.port, this.generation);
  final SendPort port;
  final int generation;
}

class _InitializationProgress {
  const _InitializationProgress(this.progress);
  final RuntimeProgress progress;
}

class _InitializationFailure {
  const _InitializationFailure(this.message);

  final String message;
}

/// The main entry point for the helper isolate.
void _isolateMain(_HelperStart start) {
  final mainSendPort = start.port;
  final clock = Stopwatch()..start();
  void progress(int units) => mainSendPort.send(
    _InitializationProgress(
      RuntimeProgress(
        requestId: start.generation,
        phase: RuntimeProgressPhase.backendInitializing,
        completedUnits: units,
        elapsedMicroseconds: clock.elapsedMicroseconds,
      ),
    ),
  );
  progress(0);
  // ignore: avoid_print
  NativeLog.debug('[InferenceHelperIsolate] Starting...');

  // Initialize the library in this isolate
  // Since the main isolate no longer calls any llama.cpp functions (using withModelPath),
  // we need to do FULL initialization here including loading all backends.
  late final ffi.DynamicLibrary lib;
  late final LlamaBindings bindings;

  try {
    // ignore: avoid_print
    NativeLog.debug(
      '[InferenceHelperIsolate] Initializing backend (full initialization)...',
    );
    // Use full initialization since main isolate does NO FFI calls
    final result = BackendInitializer.initializeBackend(
      onProgress: (phase) => progress(phase.index + 1),
    );
    lib = result.$1;
    bindings = result.$2;
    // ignore: avoid_print
    NativeLog.debug(
      '[InferenceHelperIsolate] Backend initialized successfully',
    );
  } catch (e) {
    NativeLog.debug('[InferenceHelperIsolate] ERROR initializing backend: $e');
    mainSendPort.send(
      _InitializationFailure(
        'Native backend initialization failed: ${NativeLog.redact('$e')}',
      ),
    );
    return;
  }

  // Create receive port for requests from main isolate
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  final session = _NativeInferenceSession(bindings, NativeRuntimeBridge(lib));

  receivePort.listen((message) {
    if (message is _InferenceRequestMessage) {
      _handleInferenceRequest(message, mainSendPort, lib, bindings, session);
    } else if (message is _PrepareRequestMessage) {
      _handlePrepareRequest(message, mainSendPort, session);
    } else if (message is _UnloadRequestMessage) {
      try {
        session.dispose();
        mainSendPort.send(
          _IsolateResponse(
            requestId: message.requestId,
            payload: _Prepared(modelLoadMicros: 0, contextInitMicros: 0),
            isComplete: true,
          ),
        );
      } catch (_) {
        mainSendPort.send(
          _IsolateResponse(
            requestId: message.requestId,
            payload: InferenceError(
              'Native context cleanup remains unconfirmed',
            ),
            isComplete: true,
            cleanupConfirmed: false,
          ),
        );
      }
    } else if (message is _TokenizeRequestMessage) {
      _handleTokenizeRequest(message, mainSendPort, session);
    } else if (message is _CancelRequestMessage) {
      session.cancel(message.requestId);
    }
  });

  // ignore: avoid_print
  NativeLog.debug('[InferenceHelperIsolate] Ready to accept requests');
}
