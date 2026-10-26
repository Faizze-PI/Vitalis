import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences-backed flag that persists the developer debug mode toggle.
/// Follows the Android "Developer Options" pattern: a 5-tap gesture enables it,
/// and once enabled the Debug menu item stays visible across restarts.
class DebugState {
  static final DebugState instance = DebugState._();
  DebugState._();

  static const String _key = 'is_debug_mode_enabled'; // hardcode: HC-046
  bool _cached = false;
  bool _loaded = false;

  Future<bool> isEnabled() async {
    if (!_loaded) {
      final prefs = await SharedPreferences.getInstance();
      _cached = prefs.getBool(_key) ?? false;
      _loaded = true;
    }
    return _cached;
  }

  Future<void> enable() async {
    _cached = true;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }

  Future<void> disable() async {
    _cached = false;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, false);
  }
}
