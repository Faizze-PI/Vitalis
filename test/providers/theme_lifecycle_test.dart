import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vitalis_app/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'theme load failure retains fallback and a later save can recover',
    () async {
      var loads = 0;
      final preferences = _Preferences();
      final provider = ThemeProvider(
        preferencesLoader: () async {
          if (++loads == 1) throw StateError('/private/token=secret');
          return preferences;
        },
      );
      addTearDown(provider.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(provider.mode, ThemeMode.light);
      expect(provider.persistenceFailures, 1);
      await provider.setMode(ThemeMode.dark);
      expect(provider.mode, ThemeMode.dark);
      expect(preferences.saved, ThemeMode.dark.index);
    },
  );

  test(
    'queued toggle uses committed state after preceding failed save',
    () async {
      final preferences = _Preferences();
      final provider = ThemeProvider(
        preferencesLoader: () async => preferences,
      );
      addTearDown(provider.dispose);
      await Future<void>.delayed(Duration.zero);
      await provider.setMode(ThemeMode.light);
      preferences.acknowledgements.addAll([false, true]);
      final failed = provider.setMode(ThemeMode.dark);
      final rejection = expectLater(failed, throwsStateError);
      final toggle = provider.toggle();
      await rejection;
      await toggle;
      expect(provider.mode, ThemeMode.dark);
      expect(preferences.saved, ThemeMode.dark.index);
      expect(provider.persistenceFailures, 1);
    },
  );

  test('two admitted theme toggles preserve their ordered intent', () async {
    final preferences = _Preferences();
    final provider = ThemeProvider(preferencesLoader: () async => preferences);
    addTearDown(provider.dispose);
    await Future<void>.delayed(Duration.zero);
    await provider.setMode(ThemeMode.light);
    final first = provider.toggle();
    final second = provider.toggle();
    await Future.wait([first, second]);
    expect(provider.mode, ThemeMode.light);
    expect(preferences.saved, ThemeMode.light.index);
  });

  test('theme publishes only after storage acknowledges the write', () async {
    final preferences = _Preferences()..writeGate = Completer<bool>();
    final provider = ThemeProvider(preferencesLoader: () async => preferences);
    addTearDown(provider.dispose);
    await Future<void>.delayed(Duration.zero);
    final committed = provider.mode;
    final saving = provider.setMode(ThemeMode.dark);
    await preferences.entered.future;
    expect(provider.mode, committed);
    preferences.writeGate!.complete(true);
    await saving;
    expect(provider.mode, ThemeMode.dark);
  });

  test('failed theme acknowledgement preserves committed state', () async {
    final preferences = _Preferences()..acknowledged = false;
    final provider = ThemeProvider(preferencesLoader: () async => preferences);
    addTearDown(provider.dispose);
    await Future<void>.delayed(Duration.zero);
    final committed = provider.mode;
    await expectLater(provider.setMode(ThemeMode.dark), throwsStateError);
    expect(provider.mode, committed);
    expect(provider.persistenceFailures, 1);
    expect(provider.settledWriteFailures, 1);
  });

  test('theme writer can recover after a redacted storage failure', () async {
    final preferences = _Preferences()
      ..failure = StateError('/private/preferences token=secret');
    final provider = ThemeProvider(preferencesLoader: () async => preferences);
    addTearDown(provider.dispose);
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      provider.setMode(ThemeMode.dark),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'redacted message',
          isNot(contains('token=secret')),
        ),
      ),
    );
    preferences.failure = null;
    await provider.setMode(ThemeMode.dark);
    expect(provider.mode, ThemeMode.dark);
    expect(preferences.attempts, 2);
    expect(provider.persistenceFailures, 1);
  });

  test(
    'an admitted theme save settles without publishing after disposal',
    () async {
      final preferences = _Preferences()..writeGate = Completer<bool>();
      final provider = ThemeProvider(
        preferencesLoader: () async => preferences,
      );
      await Future<void>.delayed(Duration.zero);
      final committed = provider.mode;
      var notifications = 0;
      provider.addListener(() => notifications++);
      final saving = provider.setMode(ThemeMode.dark);
      await preferences.entered.future;
      provider.dispose();
      preferences.writeGate!.complete(true);
      await saving;
      expect(provider.mode, committed);
      expect(notifications, 0);
      expect(preferences.saved, ThemeMode.dark.index);
    },
  );

  test(
    'theme disposal suppresses the pending initial preference notification',
    () async {
      SharedPreferences.setMockInitialValues({
        ThemePreferenceManifest.modeKey: 2,
      });
      final provider = ThemeProvider();
      var notifications = 0;
      provider.addListener(() => notifications++);
      provider.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 0);
      expect(provider.mode, ThemeMode.light);
    },
  );

  test(
    'disposed theme rejects new writes with a typed lifecycle error',
    () async {
      final provider = ThemeProvider();
      await Future<void>.delayed(Duration.zero);
      final committed = provider.mode;
      provider.dispose();
      await expectLater(
        provider.setMode(ThemeMode.dark),
        throwsA(isA<StateError>()),
      );
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey(ThemePreferenceManifest.modeKey), isFalse);
      expect(provider.mode, committed);
    },
  );
}

final class _Preferences implements SharedPreferences {
  final entered = Completer<void>();
  Completer<bool>? writeGate;
  Object? failure;
  bool acknowledged = true;
  int? saved;
  int attempts = 0;
  final acknowledgements = <bool>[];

  @override
  int? getInt(String key) => saved;

  @override
  Future<bool> setInt(String key, int value) async {
    attempts++;
    if (!entered.isCompleted) entered.complete();
    final accepted =
        await (writeGate?.future ??
            Future.value(
              acknowledgements.isEmpty
                  ? acknowledged
                  : acknowledgements.removeAt(0),
            ));
    if (failure case final Object error) throw error;
    if (accepted) saved = value;
    return accepted;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected preference access in lifecycle fixture');
}
