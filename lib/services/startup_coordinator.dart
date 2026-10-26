import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/startup_capabilities.dart';

/// Ordered, observable application bootstrap that never owns the first frame.
enum StartupState {
  rendering,
  openingDatabase,
  migrating,
  initializingSafety,
  checkingModel,
  ready,
  degraded,
  failed,
}

typedef StartupTask = Future<void> Function();
typedef StartupClock = Duration Function();
typedef StartupTraceSink = void Function(String event);
typedef StartupModelAssessment = Future<StartupModelReadiness> Function();

final class StartupCoordinator extends ChangeNotifier {
  StartupCoordinator({
    required StartupTask openDatabase,
    required StartupTask loadLogger,
    required StartupTask migrateLegacyPreferences,
    required StartupTask initializeSafety,
    StartupModelAssessment? assessModel,
    StartupClock? clock,
    StartupTraceSink? traceSink,
    this.databaseTimeout = const Duration(seconds: 15),
    this.optionalTaskTimeout = const Duration(seconds: 10),
  }) : _openDatabase = openDatabase,
       _loadLogger = loadLogger,
       _migrateLegacyPreferences = migrateLegacyPreferences,
       _initializeSafety = initializeSafety,
       _assessModel = assessModel,
       _clock = clock ?? _defaultClock,
       _traceSink = traceSink;

  final StartupTask _openDatabase;
  final StartupTask _loadLogger;
  final StartupTask _migrateLegacyPreferences;
  final StartupTask _initializeSafety;
  final StartupModelAssessment? _assessModel;
  final StartupClock _clock;
  final StartupTraceSink? _traceSink;
  final Duration databaseTimeout;
  final Duration optionalTaskTimeout;

  StartupState _state = StartupState.rendering;
  String? _failure;
  final List<String> _trace = <String>[];
  Future<void>? _activeStart;
  final Set<Future<void>> _pendingTasks = {};
  bool _disposed = false;
  int _traceSinkFailures = 0;
  int _attempt = 0;
  bool _databaseReady = false;
  bool _migrationReady = false;
  bool _safetyReady = false;
  StartupModelReadiness _modelReadiness = StartupModelReadiness.unknown;

  /// Bootstrap completion alone never establishes verified model readiness.
  StartupCapabilities get capabilities => StartupCapabilities(
    databaseReady: _databaseReady,
    migrationReady: _migrationReady,
    safetyReady: _safetyReady,
    modelReadiness: _modelReadiness,
    disposed: _disposed,
  );

  StartupState get state => _state;
  String? get failure => _failure;
  List<String> get trace => List<String>.unmodifiable(_trace);
  bool get canEnterApp =>
      _state == StartupState.ready || _state == StartupState.degraded;
  bool get canRetry =>
      !_disposed && _activeStart == null && _pendingTasks.isEmpty;
  int get traceSinkFailures => _traceSinkFailures;

  Future<void> start() {
    if (_disposed) return Future.error(StateError('Startup is disposed'));
    final active = _activeStart;
    if (active != null) return active;
    // A timed-out future can still be writing data. Never start a competing
    // attempt until every underlying operation has actually settled.
    if (_pendingTasks.isNotEmpty) return Future.value();
    final completion = Completer<void>();
    _activeStart = completion.future;
    void release() {
      _activeStart = null;
      if (!_disposed) notifyListeners();
    }

    unawaited(
      _start().then(
        (_) {
          release();
          completion.complete();
        },
        onError: (Object error, StackTrace stack) {
          release();
          completion.completeError(error, stack);
        },
      ),
    );
    return completion.future;
  }

  Future<void> _start() async {
    final attempt = ++_attempt;
    _failure = null;
    _trace.clear();
    _databaseReady = false;
    _migrationReady = false;
    _safetyReady = false;
    _modelReadiness = StartupModelReadiness.unknown;
    if (!await _runRequired(
      attempt,
      StartupState.openingDatabase,
      'database',
      _openDatabase,
      databaseTimeout,
    )) {
      return;
    }
    _databaseReady = true;

    var degraded = false;
    degraded |= !await _runOptional(
      attempt,
      StartupState.migrating,
      'logger',
      _loadLogger,
    );
    if (!await _runRequired(
      attempt,
      StartupState.migrating,
      'legacy_migration',
      _migrateLegacyPreferences,
      optionalTaskTimeout,
    ))
      return;
    _migrationReady = true;
    if (!await _runRequired(
      attempt,
      StartupState.initializingSafety,
      'safety',
      _initializeSafety,
      optionalTaskTimeout,
    ))
      return;
    _safetyReady = true;
    degraded |= !await _checkModel(attempt);
    if (attempt != _attempt) return;
    _setState(degraded ? StartupState.degraded : StartupState.ready);
    _record(degraded ? 'startup:degraded' : 'startup:ready');
  }

  Future<bool> _checkModel(int attempt) async {
    final assess = _assessModel;
    // Unconfigured assessment is explicitly unknown, never an implicit model.
    if (assess == null || _disposed || attempt != _attempt) return true;
    _modelReadiness = StartupModelReadiness.checking;
    _setState(StartupState.checkingModel);
    _record('model:start');
    var result = StartupModelReadiness.unknown;
    try {
      await _track(() async {
        result = await assess();
      }).timeout(optionalTaskTimeout);
      if (_disposed || attempt != _attempt) return false;
      _modelReadiness = result;
      _record('model:${result.name}');
      return result == StartupModelReadiness.ready;
    } catch (_) {
      if (!_disposed && attempt == _attempt) {
        _modelReadiness = StartupModelReadiness.unknown;
        _record('model:unverified');
      }
      return false;
    }
  }

  Future<void> _track(StartupTask task) {
    late final Future<void> tracked;
    tracked = Future<void>.sync(task).whenComplete(() {
      _pendingTasks.remove(tracked);
      if (!_disposed) notifyListeners();
    });
    _pendingTasks.add(tracked);
    return tracked;
  }

  Future<bool> _runRequired(
    int attempt,
    StartupState state,
    String name,
    StartupTask task,
    Duration timeout,
  ) async {
    if (_disposed || attempt != _attempt) return false;
    _setState(state);
    _record('$name:start');
    try {
      await _track(task).timeout(timeout);
      if (attempt != _attempt) return false;
      _record('$name:complete');
      return true;
    } on TimeoutException {
      _fail(
        attempt,
        '$name timed out. Waiting for the operation to finish before retrying. No automatic reset will be performed.',
      );
    } catch (_) {
      _fail(
        attempt,
        '$name could not be initialized. Retry after checking diagnostics. No automatic reset will be performed.',
      );
    }
    return false;
  }

  Future<bool> _runOptional(
    int attempt,
    StartupState state,
    String name,
    StartupTask task,
  ) async {
    _setState(state);
    _record('$name:start');
    try {
      await _track(task).timeout(optionalTaskTimeout);
      if (attempt != _attempt) return false;
      _record('$name:complete');
      return true;
    } catch (_) {
      if (attempt == _attempt) _record('$name:deferred');
      return false;
    }
  }

  void _fail(int attempt, String message) {
    if (attempt != _attempt) return;
    _failure = message;
    _setState(StartupState.failed);
    _record('startup:failed');
  }

  void _setState(StartupState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  void _record(String event) {
    if (_disposed) return;
    final value = '${_clock().inMilliseconds}:$event';
    _trace.add(value);
    try {
      _traceSink?.call(value);
    } catch (_) {
      // Diagnostic sinks must not break startup or recursively log failures.
      _traceSinkFailures++;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _attempt++;
    super.dispose();
  }

  static final Stopwatch _stopwatch = Stopwatch()..start();
  static Duration _defaultClock() => _stopwatch.elapsed;
}
