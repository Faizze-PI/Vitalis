// FILE: lib/utils/memory_monitor.dart
// PURPOSE: /proc/self/statm RSS reader with runtime page-size detection
// STATUS: PRODUCTION-HARDENED

import 'dart:io';

import 'app_logger.dart';

/// Reads the Android process RSS from /proc/self/statm.
/// Page size is detected at runtime from /proc/self/auxv (AT_PAGESZ=6)
/// to support 4KB, 16KB, and 64KB page configurations.
class MemoryMonitor {
  static int _pageSize = 0;

  static Future<int> _detectPageSize() async {
    if (_pageSize > 0) return _pageSize;
    try {
      final auxv = File('/proc/self/auxv');
      if (await auxv.exists()) {
        final bytes = await auxv.readAsBytes();
        // auxv entries are (type: u64, value: u64) pairs, 16 bytes each.
        // AT_PAGESZ type = 6.
        for (int i = 0; i + 16 <= bytes.length; i += 16) {
          final type = _readUint64LE(bytes, i);
          if (type == 6) {
            _pageSize = _readUint64LE(bytes, i + 8).toInt();
            return _pageSize;
          }
        }
      }
    } catch (error) {
      AppLogger.instance.warningFailure(
        'Runtime page-size telemetry unavailable; using conservative fallback',
        error,
      );
    }
    _pageSize = 4096;
    return _pageSize;
  }

  static int _readUint64LE(List<int> bytes, int offset) {
    // Dart VM is little-endian on Android.
    int result = 0;
    for (int i = 0; i < 8; i++) {
      result |= (bytes[offset + i] << (8 * i));
    }
    return result;
  }

  /// Returns RSS in megabytes, or -1 on failure.
  /// Returns 0 if the process has no resident pages (should not happen).
  static Future<int> getRssMb() async {
    try {
      final file = File('/proc/self/statm');
      if (!await file.exists()) return -1;

      final content = await file.readAsString();
      final parts = content.split(' ');
      if (parts.length < 2) return -1;

      final rssPages = int.tryParse(parts[1]);
      if (rssPages == null || rssPages < 0) return -1;

      final pageSize = await _detectPageSize();
      final rssBytes = rssPages * pageSize;
      return (rssBytes / 1024 / 1024).round();
    } catch (_) {
      return -1;
    }
  }
}
