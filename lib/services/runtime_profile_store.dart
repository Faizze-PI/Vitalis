import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/runtime_capabilities.dart';
import '../models/runtime_profile.dart';

class StoredRuntimeProfile {
  const StoredRuntimeProfile({
    required this.profile,
    required this.tunedAt,
    this.fallbackReason,
  });

  final RuntimeProfile profile;
  final DateTime tunedAt;
  final String? fallbackReason;
}

abstract interface class RuntimeProfileStore {
  Future<StoredRuntimeProfile?> read(RuntimeProfileKey key);
  Future<void> write(
    RuntimeProfileKey key,
    RuntimeProfile profile, {
    String? fallbackReason,
  });

  /// Commits only while the owning operation remains current. Readers cannot
  /// observe a rejected candidate, including cancellation during persistence.
  Future<bool> writeIfCurrent(
    RuntimeProfileKey key,
    RuntimeProfile profile, {
    required bool Function() isCurrent,
    String? fallbackReason,
  });
  Future<void> invalidate(RuntimeProfileKey key);
  Future<void> invalidateModel(String modelSha256);
}

abstract final class RuntimeProfileStoreManifest {
  static const preferencePrefix = 'runtime_profile_v1_'; // hardcode: HC-032
}

class SharedPreferencesRuntimeProfileStore implements RuntimeProfileStore {
  SharedPreferencesRuntimeProfileStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferencesLoader;
  // SharedPreferences updates its isolate-local cache before platform ack.
  // All instances in this isolate must share the same commit boundary.
  static Future<void> _pending = Future<void>.value();
  static final _quarantinedKeys = <String>{};

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _pending = _pending.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  @override
  Future<StoredRuntimeProfile?> read(RuntimeProfileKey key) => _serialized(
    () async {
      final preferences = await _preferencesLoader();
      final preferenceKey =
          '${RuntimeProfileStoreManifest.preferencePrefix}${key.storageKey}';
      if (_quarantinedKeys.contains(preferenceKey)) {
        throw const RuntimeProfilePersistenceFailure(recoveryRequired: true);
      }
      final encoded = preferences.getString(
        '${RuntimeProfileStoreManifest.preferencePrefix}${key.storageKey}',
      );
      if (encoded == null) return null;
      try {
        final json = jsonDecode(encoded) as Map<String, dynamic>;
        return StoredRuntimeProfile(
          profile: RuntimeProfile.fromJson(
            (json['profile'] as Map).cast<String, Object?>(),
          ),
          tunedAt: DateTime.parse(json['tunedAt']! as String),
          fallbackReason: json['fallbackReason'] as String?,
        );
      } catch (_) {
        if (!await preferences.remove(preferenceKey)) {
          _quarantinedKeys.add(preferenceKey);
          throw const RuntimeProfilePersistenceFailure(recoveryRequired: true);
        }
        return null;
      }
    },
  );

  @override
  Future<void> write(
    RuntimeProfileKey key,
    RuntimeProfile profile, {
    String? fallbackReason,
  }) async {
    await writeIfCurrent(
      key,
      profile,
      isCurrent: () => true,
      fallbackReason: fallbackReason,
    );
  }

  @override
  Future<bool> writeIfCurrent(
    RuntimeProfileKey key,
    RuntimeProfile profile, {
    required bool Function() isCurrent,
    String? fallbackReason,
  }) => _serialized(() async {
    if (!isCurrent()) return false;
    final preferences = await _preferencesLoader();
    if (!isCurrent()) return false;
    final preferenceKey =
        '${RuntimeProfileStoreManifest.preferencePrefix}${key.storageKey}';
    if (_quarantinedKeys.contains(preferenceKey)) {
      throw const RuntimeProfilePersistenceFailure(recoveryRequired: true);
    }
    final previous = preferences.getString(preferenceKey);
    var cancelled = false;
    try {
      final acknowledged = await preferences.setString(
        preferenceKey,
        jsonEncode({
          'profile': profile.toJson(),
          'tunedAt': DateTime.now().toUtc().toIso8601String(),
          'fallbackReason': fallbackReason,
        }),
      );
      if (!acknowledged) throw const RuntimeProfilePersistenceFailure();
      if (!isCurrent()) {
        cancelled = true;
        throw const RuntimeProfilePersistenceFailure();
      }
    } catch (_) {
      try {
        final restored = previous == null
            ? await preferences.remove(preferenceKey)
            : await preferences.setString(preferenceKey, previous);
        if (!restored) throw const RuntimeProfilePersistenceFailure();
      } catch (_) {
        _quarantinedKeys.add(preferenceKey);
        throw const RuntimeProfilePersistenceFailure(recoveryRequired: true);
      }
      if (cancelled) return false;
      throw const RuntimeProfilePersistenceFailure();
    }
    return true;
  });

  @override
  Future<void> invalidate(RuntimeProfileKey key) => _serialized(() async {
    final preferences = await _preferencesLoader();
    final preferenceKey =
        '${RuntimeProfileStoreManifest.preferencePrefix}${key.storageKey}';
    if (!await preferences.remove(preferenceKey)) {
      _quarantinedKeys.add(preferenceKey);
      throw const RuntimeProfilePersistenceFailure(recoveryRequired: true);
    }
    _quarantinedKeys.remove(preferenceKey);
  });

  @override
  Future<void> invalidateModel(String modelSha256) => _serialized(() async {
    final preferences = await _preferencesLoader();
    final matching = preferences
        .getKeys()
        .where((key) {
          if (!key.startsWith(RuntimeProfileStoreManifest.preferencePrefix)) {
            return false;
          }
          try {
            final storageKey = key.substring(
              RuntimeProfileStoreManifest.preferencePrefix.length,
            );
            final components = utf8
                .decode(base64Url.decode(storageKey))
                .split('|');
            return components.length == 6 && components[1] == modelSha256;
          } on FormatException {
            return false;
          }
        })
        .toList(growable: false);
    for (final key in matching) {
      if (!await preferences.remove(key)) {
        _quarantinedKeys.add(key);
        throw const RuntimeProfilePersistenceFailure(recoveryRequired: true);
      }
      _quarantinedKeys.remove(key);
    }
  });
}

class RuntimeProfilePersistenceFailure implements Exception {
  const RuntimeProfilePersistenceFailure({this.recoveryRequired = false});
  final bool recoveryRequired;
  @override
  String toString() => recoveryRequired
      ? 'Runtime profile persistence requires recovery'
      : 'Runtime profile persistence was not acknowledged';
}
