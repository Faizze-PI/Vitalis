// SECURITY: AppLogger applies best-effort regex masking and privacy mode.
// Callers must exclude private content; regex masking is a secondary defense.
// Privacy mode (default: ON) suppresses INFO-level writes entirely.
// Log deletion uses best-effort overwrite before deletion. Flash storage and
// filesystem wear levelling mean this is not a cryptographic erasure claim.
// Files are rotated at 2MB and pruned after 7 days.
import 'dart:async';
import 'dart:io';
import 'package:intl/intl.dart';
import '../services/application_private_directory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'async_mutex.dart';
import 'log_sanitizer.dart';
import '../models/diagnostics_policy.dart';

final class LogCleanupResult {
  const LogCleanupResult({
    required this.removedFiles,
    required this.failedOperations,
  });
  final int removedFiles;
  final int failedOperations;
  bool get complete => failedOperations == 0;
}

/// Privacy-first local logger that writes timestamped, severity-tagged entries
/// to rotating daily files under [applicationPrivateDirectory]/logs/.
/// Files older than 7 days are pruned automatically.
/// Writes are serialized through [AsyncMutex] and passed through [LogSanitizer].
/// Regex masking cannot guarantee removal of arbitrary private content.
class AppLogger {
  static final AppLogger instance = AppLogger._();
  AppLogger._({
    Future<Directory> Function()? directoryResolver,
    Future<bool?> Function()? privacyLoader,
    Future<void> Function(bool)? privacySaver,
    DateTime Function()? clock,
    Future<bool> Function(File)? fileRemover,
  }) : _directoryResolver = directoryResolver ?? applicationPrivateDirectory,
       _privacyLoader = privacyLoader ?? _loadPrivacyPreference,
       _privacySaver = privacySaver ?? _savePrivacyPreference,
       _clock = clock ?? DateTime.now,
       _fileRemover = fileRemover;

  factory AppLogger.forTesting({
    required Future<Directory> Function() directoryResolver,
    required Future<bool?> Function() privacyLoader,
    required Future<void> Function(bool) privacySaver,
    required DateTime Function() clock,
    Future<bool> Function(File)? fileRemover,
  }) => AppLogger._(
    directoryResolver: directoryResolver,
    privacyLoader: privacyLoader,
    privacySaver: privacySaver,
    clock: clock,
    fileRemover: fileRemover,
  );

  static const String _logDirName = 'logs'; // hardcode: HC-014
  static const String _privacyModeKey = 'privacy_mode'; // hardcode: HC-046

  final AsyncMutex _mutex = AsyncMutex();
  final Future<Directory> Function() _directoryResolver;
  final Future<bool?> Function() _privacyLoader;
  final Future<void> Function(bool) _privacySaver;
  final DateTime Function() _clock;
  final Future<bool> Function(File)? _fileRemover;
  Directory? _logDir;
  final List<String> _recentLines = [];
  bool _privacyMode = true;
  int _sinkFailureCount = 0;
  Future<void> _privacyWriteTail = Future<void>.value();
  int _privacyRevision = 0;

  bool get isPrivacyMode => _privacyMode;
  int get sinkFailureCount => _sinkFailureCount;

  Future<void> loadPersistedState() async {
    final revision = _privacyRevision;
    try {
      final value = await _privacyLoader() ?? true;
      if (revision == _privacyRevision) _privacyMode = value;
    } catch (_) {
      _sinkFailureCount++;
      if (revision == _privacyRevision) _privacyMode = true;
    }
  }

  Future<Directory> _ensureLogDir() async {
    if (_logDir != null) return _logDir!;
    final appDir = await _directoryResolver();
    _logDir = Directory('${appDir.path}/$_logDirName');
    if (!await _logDir!.exists()) {
      await _logDir!.create(recursive: true);
    }
    return _logDir!;
  }

  File _dailyFile(Directory dir) {
    final date = DateFormat('yyyy-MM-dd').format(_clock());
    return File('${dir.path}/log_$date.txt');
  }

  Future<void> setPrivacyMode(bool value) {
    final revision = ++_privacyRevision;
    // Enabling protection is immediate; disabling requires durable acknowledgement.
    if (value) _privacyMode = true;
    final operation = _privacyWriteTail.then((_) async {
      try {
        await _privacySaver(value);
        if (revision == _privacyRevision) _privacyMode = value;
      } catch (_) {
        _sinkFailureCount++;
        throw StateError('The privacy preference could not be saved.');
      }
    });
    _privacyWriteTail = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<void> _write(String level, String message) async {
    if (_privacyMode && level == 'INFO') return;
    final now = _clock();
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final sanitized = LogSanitizer.sanitize(message);
    final line = '[$timestamp] [$level] $sanitized';

    _recentLines.add(line);
    if (_recentLines.length > DiagnosticsPolicy.maximumInMemoryLines) {
      _recentLines.removeAt(0);
    }

    await _mutex.synchronize(() async {
      try {
        final dir = await _ensureLogDir();
        final file = _dailyFile(dir);

        if (await file.exists() &&
            await file.length() > DiagnosticsPolicy.maximumFileBytes) {
          final rotated = File('${file.path}.1');
          await file.rename(rotated.path);
        }

        await file.writeAsString('$line\n', mode: FileMode.append);

        // Prune every 10 writes.
        if (_recentLines.length % DiagnosticsPolicy.pruneEveryWrites == 0) {
          await _prune();
        }
      } catch (_) {
        _sinkFailureCount++;
      }
    });
  }

  Future<void> info(String message) => _write('INFO', message);
  Future<void> warning(String message) => _write('WARN', message);
  Future<void> error(String message) => _write('ERROR', message);

  /// Use a trusted operation label; exception messages and stacks stay excluded.
  Future<void> warningFailure(String operation, Object failure) =>
      warning('$operation (${failure.runtimeType})');

  Future<void> errorFailure(String operation, Object failure) =>
      error('$operation (${failure.runtimeType})');

  void errorFailureSync(String operation, Object failure) =>
      errorSync('$operation (${failure.runtimeType})');

  /// Waits for disk operations queued before this call. Tests and shutdown
  /// owners must use this barrier before removing or closing log storage.
  Future<void> flush() => _mutex.synchronize(() async {});

  void infoSync(String message) {
    if (_privacyMode) return;
    final now = _clock();
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final sanitized = LogSanitizer.sanitize(message);
    final line = '[$timestamp] [INFO] $sanitized';
    _recentLines.add(line);
    if (_recentLines.length > DiagnosticsPolicy.maximumInMemoryLines) {
      _recentLines.removeAt(0);
    }
    // Fire-and-forget flush to disk (async barrier).
    unawaited(_writeSyncFlush(line));
  }

  void errorSync(String message) {
    final now = _clock();
    final timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    final sanitized = LogSanitizer.sanitize(message);
    final line = '[$timestamp] [ERROR] $sanitized';
    _recentLines.add(line);
    if (_recentLines.length > DiagnosticsPolicy.maximumInMemoryLines) {
      _recentLines.removeAt(0);
    }
    unawaited(_writeSyncFlush(line));
  }

  Future<void> _writeSyncFlush(String line) async {
    await _mutex.synchronize(() async {
      try {
        final dir = await _ensureLogDir();
        final file = _dailyFile(dir);
        await file.writeAsString('$line\n', mode: FileMode.append);
      } catch (_) {
        _sinkFailureCount++;
      }
    });
  }

  Future<void> _prune() async {
    try {
      final dir = await _ensureLogDir();
      final entities = await dir.list().toList();
      final cutoff = _clock().subtract(
        const Duration(days: DiagnosticsPolicy.retentionDays),
      );

      for (final entity in entities) {
        if (entity is File) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await _secureDelete(entity);
          }
        }
      }
    } catch (_) {
      _sinkFailureCount++;
    }
  }

  Future<String> getLogs({int maxLines = 50}) async {
    if (_recentLines.length >= maxLines) {
      return _recentLines.sublist(_recentLines.length - maxLines).join('\n');
    }
    return _recentLines.join('\n');
  }

  Future<LogCleanupResult> clearLogs() => _mutex.synchronize(() async {
    var removed = 0;
    var failed = 0;
    try {
      final dir = await _ensureLogDir();
      await for (final entity in dir.list()) {
        if (entity is File) {
          if (await (_fileRemover?.call(entity) ?? _secureDelete(entity))) {
            removed++;
          } else {
            failed++;
          }
        }
      }
    } catch (_) {
      _sinkFailureCount++;
      failed++;
    }
    if (failed == 0) _recentLines.clear();
    return LogCleanupResult(removedFiles: removed, failedOperations: failed);
  });

  Future<bool> _secureDelete(File file) async {
    try {
      final length = await file.length();
      if (length > 0) {
        final sink = file.openWrite(mode: FileMode.write);
        sink.add(List.filled(length, 0));
        await sink.flush();
        await sink.close();
      }
      await file.delete();
      return true;
    } catch (_) {
      _sinkFailureCount++;
      return false;
    }
  }

  static Future<bool?> _loadPrivacyPreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_privacyModeKey);
  }

  static Future<void> _savePrivacyPreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_privacyModeKey, value)) {
      // SharedPreferences updates its in-memory cache even on failed persistence.
      await prefs.reload();
      throw StateError('Privacy persistence was not acknowledged.');
    }
  }
}
