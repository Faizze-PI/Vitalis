import 'dart:async';
import 'package:flutter/services.dart';
import '../models/device_safety_policy.dart';
import '../utils/app_logger.dart';

/// Listens to Android system memory pressure events via
/// SystemChannels.systemEvent for `trimMemoryLevel`.
///
/// Exposes a stream of memory pressure levels. Levels >= 80 indicate
/// critical memory pressure where heavy operations should be avoided.
class MemoryPressureService {
  MemoryPressureService({
    DeviceSafetyPolicy policy = const DeviceSafetyPolicy(),
    Stream<dynamic> Function()? eventStream,
    AppLogger? logger,
  }) : _policy = policy,
       _logger = logger ?? AppLogger.instance,
       _eventStream =
           eventStream ??
           (() => const EventChannel(
             'vitalis/device_events',
           ).receiveBroadcastStream());

  final DeviceSafetyPolicy _policy;
  final AppLogger _logger;
  final Stream<dynamic> Function() _eventStream;
  StreamSubscription<dynamic>? _subscription;
  final StreamController<int> _controller = StreamController<int>.broadcast();
  int _currentLevel = 0;

  int get currentLevel => _currentLevel;
  bool get isCritical => _currentLevel >= _policy.criticalTrimMemoryLevel;
  Stream<int> get onMemoryPressure => _controller.stream;

  void startListening() {
    try {
      _subscription = _eventStream().listen(
        (event) {
          if (event is Map && event.containsKey('trimMemoryLevel')) {
            final level = event['trimMemoryLevel'] as int? ?? 0;
            _currentLevel = level;
            _controller.add(level);
            if (level >= _policy.criticalTrimMemoryLevel) {
              _logger.warning('Critical memory pressure: level $level');
            }
          }
        },
        onError: (error) {
          _logger.error(
            'Memory pressure listener error (${error.runtimeType})',
          );
        },
      );
    } catch (e) {
      _logger.error(
        'Failed to start memory pressure listener (${e.runtimeType})',
      );
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _controller.close();
  }
}
