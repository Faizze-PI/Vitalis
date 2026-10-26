import 'package:flutter/material.dart';

/// Vitalis typography scale.
/// Applied via ThemeData textTheme overrides in main.dart.
class AppTypography {
  AppTypography._();

  /// Light-mode TextTheme based on default Material 3 with size/weight tweaks.
  static TextTheme get light => const TextTheme(
    displayLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
    headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
    headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
    headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
    titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
    bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
  );

  /// Dark-mode TextTheme — identical size/weight, color handled by ThemeData.
  static TextTheme get dark => light;
}
