import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitalis_app/models/model_settings.dart';
import 'package:vitalis_app/models/runtime_capabilities.dart';
import 'package:vitalis_app/models/runtime_profile.dart';
import 'package:vitalis_app/services/runtime_profile_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = RuntimeProfileKey(
    appVersion: '1.0+1',
    modelSha256: 'abc',
    deviceFingerprint: 'device',
    backendVersion: 'native',
    backend: 'cpu',
    templateFingerprint: 'template',
  );
  const profile = RuntimeProfile(
    contextSize: 8192,
    reservedOutputTokens: 1024,
    generationThreads: 4,
    promptThreads: 4,
    batchSize: 256,
    gpuLayers: 0,
    thinkingMode: ThinkingMode.off,
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'another store cannot read a profile before write acknowledgement',
    () async {
      final preferences = _HeldPreferences();
      final writer = SharedPreferencesRuntimeProfileStore(
        preferencesLoader: () async => preferences,
      );
      final reader = SharedPreferencesRuntimeProfileStore(
        preferencesLoader: () async => preferences,
      );
      final writing = writer.write(key, profile);
      await preferences.writeStarted.future;
      var readCompleted = false;
      final reading = reader.read(key).then((value) {
        readCompleted = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);
      try {
        expect(
          readCompleted,
          isFalse,
          reason: 'Candidate is not acknowledged yet',
        );
      } finally {
        preferences.writeAcknowledgement.complete(true);
        await writing;
        await reading;
      }
    },
  );

  test('profile round-trips and invalidates by complete key', () async {
    final store = SharedPreferencesRuntimeProfileStore();
    await store.write(key, profile);
    final restored = await store.read(key);
    expect(restored, isNotNull);
    expect(restored!.profile.contextSize, 8192);
    expect(restored.profile.batchSize, 256);

    const changedBackend = RuntimeProfileKey(
      appVersion: '1.0+1',
      modelSha256: 'abc',
      deviceFingerprint: 'device',
      backendVersion: 'native',
      backend: 'vulkan',
      templateFingerprint: 'template',
    );
    expect(await store.read(changedBackend), isNull);
    await store.invalidate(key);
    expect(await store.read(key), isNull);
  });

  test(
    'rejected save restores previous profile before readers resume',
    () async {
      final preferences = _HeldPreferences();
      final store = SharedPreferencesRuntimeProfileStore(
        preferencesLoader: () async => preferences,
      );
      final preferenceKey =
          '${RuntimeProfileStoreManifest.preferencePrefix}${key.storageKey}';
      // An existing acknowledged record must survive the rejected replacement.
      final priorStore = SharedPreferencesRuntimeProfileStore();
      await priorStore.write(key, profile);
      final priorPreferences = await SharedPreferences.getInstance();
      final previous = priorPreferences.getString(preferenceKey)!;
      preferences.values[preferenceKey] = previous;
      final writing = store.write(key, profile, fallbackReason: 'replacement');
      final failure = expectLater(
        writing,
        throwsA(isA<RuntimeProfilePersistenceFailure>()),
      );
      await preferences.writeStarted.future;
      final reading = store.read(key);
      preferences.writeAcknowledgement.complete(false);
      await failure;
      expect((await reading)!.fallbackReason, isNull);
      expect(preferences.values[preferenceKey], previous);
      // A failed commit must not poison later operations.
      await store.write(key, profile, fallbackReason: 'acknowledged');
      expect((await store.read(key))!.fallbackReason, 'acknowledged');
    },
  );

  test('rejected first save leaves no candidate in the cache', () async {
    final preferences = _HeldPreferences();
    final store = SharedPreferencesRuntimeProfileStore(
      preferencesLoader: () async => preferences,
    );
    final writing = store.write(key, profile);
    final failure = expectLater(
      writing,
      throwsA(isA<RuntimeProfilePersistenceFailure>()),
    );
    await preferences.writeStarted.future;
    final reading = store.read(key);
    preferences.writeAcknowledgement.complete(false);
    await failure;
    expect(await reading, isNull);
    expect(preferences.values, isEmpty);
  });

  test(
    'cancelled commit restores old profile before another store reads',
    () async {
      final preferences = _HeldPreferences();
      final store = SharedPreferencesRuntimeProfileStore(
        preferencesLoader: () async => preferences,
      );
      final preferenceKey =
          '${RuntimeProfileStoreManifest.preferencePrefix}${key.storageKey}';
      final priorStore = SharedPreferencesRuntimeProfileStore();
      await priorStore.write(
        key,
        profile,
        fallbackReason: 'previous verified profile',
      );
      preferences.values[preferenceKey] =
          (await SharedPreferences.getInstance()).getString(preferenceKey)!;
      var current = true;
      final writing = store.writeIfCurrent(
        key,
        profile,
        isCurrent: () => current,
      );
      await preferences.writeStarted.future;
      final reading = SharedPreferencesRuntimeProfileStore(
        preferencesLoader: () async => preferences,
      ).read(key);
      current = false;
      preferences.writeAcknowledgement.complete(true);
      expect(await writing, isFalse);
      expect((await reading)!.fallbackReason, 'previous verified profile');
    },
  );

  test('already cancelled commit does not touch preferences', () async {
    final preferences = _HeldPreferences();
    final store = SharedPreferencesRuntimeProfileStore(
      preferencesLoader: () async => preferences,
    );
    expect(
      await store.writeIfCurrent(key, profile, isCurrent: () => false),
      isFalse,
    );
    expect(preferences.writeStarted.isCompleted, isFalse);
    expect(preferences.values, isEmpty);
  });

  test(
    'failed rollback quarantines candidate until acknowledged invalidation',
    () async {
      final preferences = _HeldPreferences()..rejectRemoval = true;
      final store = SharedPreferencesRuntimeProfileStore(
        preferencesLoader: () async => preferences,
      );
      final writing = store.write(key, profile);
      final failure = expectLater(
        writing,
        throwsA(
          isA<RuntimeProfilePersistenceFailure>().having(
            (error) => error.recoveryRequired,
            'recovery required',
            isTrue,
          ),
        ),
      );
      await preferences.writeStarted.future;
      preferences.writeAcknowledgement.complete(false);
      await failure;
      try {
        await expectLater(
          store.read(key),
          throwsA(isA<RuntimeProfilePersistenceFailure>()),
        );
        await expectLater(
          store.write(key, profile),
          throwsA(isA<RuntimeProfilePersistenceFailure>()),
        );
      } finally {
        preferences.rejectRemoval = false;
        await store.invalidate(key);
      }
      expect(await store.read(key), isNull);
      await store.write(key, profile);
      expect(await store.read(key), isNotNull);
    },
  );

  test(
    'model invalidation removes every backend profile for only that hash',
    () async {
      final store = SharedPreferencesRuntimeProfileStore();
      const vulkanKey = RuntimeProfileKey(
        appVersion: '1.0+1',
        modelSha256: 'abc',
        deviceFingerprint: 'device',
        backendVersion: 'native',
        backend: 'vulkan',
        templateFingerprint: 'template',
      );
      const otherModelKey = RuntimeProfileKey(
        appVersion: '1.0+1',
        modelSha256: 'different',
        deviceFingerprint: 'device',
        backendVersion: 'native',
        backend: 'cpu',
        templateFingerprint: 'template',
      );
      await store.write(key, profile);
      await store.write(vulkanKey, profile);
      await store.write(otherModelKey, profile);

      await store.invalidateModel('abc');

      expect(await store.read(key), isNull);
      expect(await store.read(vulkanKey), isNull);
      expect(await store.read(otherModelKey), isNotNull);
    },
  );
}

class _HeldPreferences implements SharedPreferences {
  bool rejectRemoval = false;
  final values = <String, String>{};
  final writeStarted = Completer<void>();
  final writeAcknowledgement = Completer<bool>();
  @override
  String? getString(String key) => values[key];
  @override
  Set<String> getKeys() => values.keys.toSet();
  @override
  Future<bool> setString(String key, String value) {
    values[key] = value;
    if (!writeStarted.isCompleted) {
      writeStarted.complete();
      return writeAcknowledgement.future;
    }
    return Future.value(true);
  }

  @override
  Future<bool> remove(String key) async {
    if (rejectRemoval) return false;
    values.remove(key);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
