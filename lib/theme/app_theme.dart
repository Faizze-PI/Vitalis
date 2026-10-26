import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_metrics.dart';
import '../constants/app_typography.dart';

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colors =
        ColorScheme.fromSeed(
          seedColor: AppColors.seed,
          brightness: brightness,
        ).copyWith(
          surface: brightness == Brightness.dark
              ? const Color(0xFF111514)
              : const Color(0xFFFAFAF8),
        );
    final base = ThemeData(useMaterial3: true, colorScheme: colors);
    final text = base.textTheme
        .merge(
          brightness == Brightness.dark
              ? AppTypography.dark
              : AppTypography.light,
        )
        .apply(bodyColor: colors.onSurface, displayColor: colors.onSurface);
    const outline = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppMetrics.radiusLg)),
    );
    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: colors.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceContainerLow,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: AppMetrics.spaceXs),
        shape: outline.copyWith(side: BorderSide(color: colors.outlineVariant)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLow,
        contentPadding: const EdgeInsets.all(AppMetrics.spaceMd),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppMetrics.radiusLg),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppMetrics.spaceMd,
          vertical: AppMetrics.spaceXxs,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(AppMetrics.inputMinHeight),
          foregroundColor: colors.onSurfaceVariant,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(
            AppMetrics.inputMinHeight,
            AppMetrics.inputMinHeight,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, AppMetrics.inputMinHeight),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceContainerLow,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppMetrics.sheetRadius),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceContainerLow,
        indicatorColor: colors.secondaryContainer,
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
