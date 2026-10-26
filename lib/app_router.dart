import 'package:flutter/material.dart';
import 'screens/setup_screen.dart';
import 'screens/home_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/model_library_screen.dart';
import 'ui/debug_settings_screen.dart';
import 'utils/debug_state.dart';

/// Named route constants.
class AppRoutes {
  AppRoutes._();
  static const String setup = '/'; // hardcode: HC-043
  static const String home = '/home'; // hardcode: HC-043
  static const String chat = '/chat'; // hardcode: HC-043
  static const String chatSettings = '/chat-settings'; // hardcode: HC-043
  static const String settings = '/settings'; // hardcode: HC-043
  static const String debug = '/debug'; // hardcode: HC-043
  static const String modelLibrary = '/models'; // hardcode: HC-043
}

/// Single-source-of-truth route generator.
/// Replaces the inline `routes:` map in main.dart.
Route<dynamic>? onGenerateRoute(RouteSettings routeSettings) {
  switch (routeSettings.name) {
    case AppRoutes.setup:
      return MaterialPageRoute(
        builder: (_) => const SetupScreen(),
        settings: routeSettings,
      );
    case AppRoutes.home:
      return MaterialPageRoute(
        builder: (_) => const HomeScreen(),
        settings: routeSettings,
      );
    case AppRoutes.chat:
      return MaterialPageRoute(
        builder: (_) => const ChatScreen(),
        settings: routeSettings,
      );
    case AppRoutes.chatSettings:
      return MaterialPageRoute(
        builder: (_) => const SettingsScreen.chat(),
        settings: routeSettings,
      );
    case AppRoutes.settings:
      return MaterialPageRoute(
        builder: (_) => const SettingsScreen(),
        settings: routeSettings,
      );
    case AppRoutes.debug:
      return MaterialPageRoute(
        builder: (_) => const DebugSettingsScreen(),
        settings: routeSettings,
      );
    case AppRoutes.modelLibrary:
      return MaterialPageRoute(
        builder: (_) => const ModelLibraryScreen(),
        settings: routeSettings,
      );
    default:
      return MaterialPageRoute(
        builder: (_) => const SetupScreen(),
        settings: routeSettings,
      );
  }
}

/// Checks debug-mode before navigating to /debug.
/// Returns true if route should proceed.
Future<bool> canNavigateToDebug(BuildContext context) async {
  final enabled = await DebugState.instance.isEnabled();
  if (!enabled && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Developer mode not enabled')));
  }
  return enabled;
}
