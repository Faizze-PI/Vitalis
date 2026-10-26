import 'package:flutter/material.dart';

/// Vitalis Material 3 color palette.
/// All widgets import from here — zero hardcoded hex in widget files.
class AppColors {
  AppColors._();

  // Seed
  static const Color seed = Color(0xFF6C63FF);

  // Health status colors (used across chat_screen, health bar, debug)
  static const Color healthGreen = Color(0xFF4CAF50);
  static const Color healthOrange = Color(0xFFFF9800);
  static const Color healthRed = Color(0xFFF44336);

  // Semantic aliases for readability
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorLight = Color(0xFFFFF0F0);
  static const Color warningBg = Color(0xFFFFF8E1);
  static const Color noteBarBg = Color(0xFFFFF8E1);

  // Message chat colors (used in message_bubble)
  static const Color userBubble = Color(0xFF6C63FF);
  static const Color userText = Colors.white;
  static const Color assistantBubbleLight = Color(0xFFF0F0F0);
  static const Color assistantTextLight = Color(0xFF1C1B1F);
  static const Color assistantBubbleDark = Color(0xFF2D2D2D);
  static const Color assistantTextDark = Color(0xFFE0E0E0);

  // Debug / log view
  static const Color logBg = Color(0x1F000000);

  // Context bar
  static Color contextBarBg(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? Colors.grey.shade800
      : Colors.grey.shade200;
  static Color contextBarText(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? Colors.grey.shade400
      : Colors.grey.shade600;
}
