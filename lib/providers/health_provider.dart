import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/hardware_sentinel_service.dart';
import '../utils/memory_monitor.dart';

class HealthProvider extends ChangeNotifier {
  final HardwareSentinelService _sentinel;
  Timer? _timer;
  int _rssMb = 0;

  HealthProvider({required HardwareSentinelService sentinel})
    : _sentinel = sentinel {
    // 5-second interval balances CPU wakeups vs. battery reporting accuracy.
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    _refresh();
  }

  int get rssMb => _rssMb;
  int get batteryLevel => _sentinel.currentLevel ?? 0;
  bool get batteryKnown => _sentinel.currentLevel != null;
  bool get isSafeForHeavy => _sentinel.isSafeForHeavyOperation();
  bool get isSafeForDownload => _sentinel.isSafeForDownload();
  bool? get isCharging => _sentinel.isCharging;
  bool? get batterySaver => _sentinel.isInSaveMode;

  Future<void> _refresh() async {
    final rss = await MemoryMonitor.getRssMb();
    if (rss != _rssMb) {
      _rssMb = rss < 0 ? 0 : rss;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
