// FILE: lib/utils/async_mutex.dart
// PURPOSE: Lightweight asynchronous mutex — no external dependencies
// STATUS: PRODUCTION-HARDENED

import 'dart:async';

/// A lightweight async mutex using a [Completer] queue.
/// [acquire] returns a future that completes when the lock is obtained.
/// [release] signals the next waiter. Safe for single-threaded async Dart.
class AsyncMutex {
  Completer<void>? _current;

  /// Acquires the mutex. Returns immediately if free; otherwise waits
  /// until the current holder calls [release].
  Future<void> acquire() async {
    while (_current != null) {
      await _current!.future;
    }
    _current = Completer<void>();
  }

  /// Releases the mutex, allowing the next waiting [acquire] to proceed.
  void release() {
    final c = _current;
    if (c != null) {
      _current = null;
      c.complete();
    }
  }

  /// Runs [fn] under the mutex and returns its result.
  Future<T> synchronize<T>(Future<T> Function() fn) async {
    await acquire();
    try {
      return await fn();
    } finally {
      release();
    }
  }
}
