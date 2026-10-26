import 'package:flutter/foundation.dart';
import '../models/startup_capabilities.dart';

/// Serializes read-only assessments; never loads or substitutes a model.
final class SelectedModelReadiness extends ChangeNotifier {
  SelectedModelReadiness(this.inspect);
  final Future<StartupModelReadiness> Function(String) inspect;
  String? _modelId;
  StartupModelReadiness _readiness = StartupModelReadiness.unknown;
  Future<void>? _pending;
  int _epoch = 0;
  bool _disposed = false;

  String? get modelId => _modelId;
  StartupModelReadiness get readiness => _readiness;

  /// Bootstrap owns its file read but cannot publish selected-chat readiness.
  /// A timed-out bootstrap waiter may finish later; a subsequent selection waits
  /// for that reader and performs its own assessment before enabling inference.
  Future<StartupModelReadiness> assessForBootstrap(String id) {
    if (_disposed)
      return Future.error(StateError('Model readiness is disposed'));
    final previous = _pending;
    var result = StartupModelReadiness.unknown;
    late final Future<void> operation;
    operation = _inspectBootstrap(previous, id)
        .then<void>((value) {
          result = value;
        })
        .whenComplete(() {
          if (identical(_pending, operation)) _pending = null;
        });
    _pending = operation;
    return operation.then((_) => result);
  }

  Future<StartupModelReadiness> _inspectBootstrap(
    Future<void>? previous,
    String id,
  ) async {
    await previous;
    if (_disposed) return StartupModelReadiness.unknown;
    try {
      final result = await inspect(id);
      return _disposed ? StartupModelReadiness.unknown : result;
    } catch (_) {
      return StartupModelReadiness.unknown;
    }
  }

  void invalidate() {
    if (_disposed) return;
    _epoch++;
    _readiness = StartupModelReadiness.unknown;
    notifyListeners();
  }

  Future<void> select(String id, {bool refresh = false}) {
    if (_disposed)
      return Future.error(StateError('Model readiness is disposed'));
    if (!refresh &&
        id == _modelId &&
        (_readiness == StartupModelReadiness.ready ||
            _readiness == StartupModelReadiness.checking)) {
      return _pending ?? Future.value();
    }
    final epoch = ++_epoch;
    _modelId = id;
    _readiness = StartupModelReadiness.checking;
    final previous = _pending;
    final operation = _assess(previous, id, epoch);
    _pending = operation;
    notifyListeners();
    return operation;
  }

  Future<void> _assess(Future<void>? previous, String id, int epoch) async {
    // Waiting retains the prior file-reader operation; no overlapping retries.
    await previous;
    if (_disposed || epoch != _epoch) return;
    var result = StartupModelReadiness.unknown;
    try {
      result = await inspect(id);
    } catch (_) {
      // Unreadable assessment is unknown, not permission or model corruption.
      result = StartupModelReadiness.unknown;
    }
    if (_disposed || epoch != _epoch) return;
    _readiness = result;
    _pending = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _readiness = StartupModelReadiness.unknown;
    super.dispose();
  }
}
