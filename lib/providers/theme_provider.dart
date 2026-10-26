import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class ThemePreferenceManifest {
  static const modeKey = 'theme_mode'; // hardcode: HC-046
}

class ThemeProvider extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.light;
  bool _disposed = false;
  int _revision = 0;
  final Future<SharedPreferences> Function() _preferencesLoader;
  Future<void> _writeTail = Future<void>.value();
  int _persistenceFailures = 0;
  int _settledWriteFailures = 0;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;
  int get persistenceFailures => _persistenceFailures;
  int get settledWriteFailures => _settledWriteFailures;

  ThemeProvider({Future<SharedPreferences> Function()? preferencesLoader})
    : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance {
    _load();
  }

  Future<void> _load() async {
    final revision = _revision;
    try {
      final prefs = await _preferencesLoader();
      if (_disposed || revision != _revision) return;
      final val = prefs.getInt(ThemePreferenceManifest.modeKey) ?? 0;
      _mode = ThemeMode.values[val.clamp(0, ThemeMode.values.length - 1)];
      notifyListeners();
    } catch (_) {
      // Preference loading is non-destructive; retain the display fallback.
      _persistenceFailures++;
    }
  }

  Future<void> setMode(ThemeMode mode) => _saveMode(() => mode);

  Future<void> _saveMode(ThemeMode Function() selectMode) async {
    if (_disposed) throw StateError('Theme provider is disposed');
    _revision++;
    final pending = _writeTail.then<void>((_) async {
      try {
        final mode = selectMode();
        final prefs = await _preferencesLoader();
        if (!await prefs.setInt(ThemePreferenceManifest.modeKey, mode.index)) {
          throw StateError('Theme preference was not acknowledged');
        }
        if (_disposed) return;
        _mode = mode;
        notifyListeners();
      } catch (_) {
        _persistenceFailures++;
        throw StateError('Theme preference could not be saved');
      }
    });
    // Keep later writes ordered while the original caller observes failure.
    _writeTail = pending.then<void>(
      (_) {},
      onError: (Object error) {
        _settledWriteFailures++;
      },
    );
    await pending;
  }

  Future<void> toggle() => _saveMode(
    () => _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
  );

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
