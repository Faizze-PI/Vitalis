/// Vitalis 4pt/8pt spacing and radius system.
/// All widgets import from here — zero EdgeInsets.all(8) in widget files.
class AppMetrics {
  AppMetrics._();

  // Spacing
  static const double spaceXxs = 4;
  static const double spaceXs = 8;
  static const double spaceSm = 12;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;
  static const double spaceXxl = 48;

  // Border radius
  static const double radiusXs = 4;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;

  // Avatar / icon sizes
  static const double avatarRadius = 16;
  static const double iconSizeSm = 16;
  static const double iconSizeMd = 18;
  static const double iconSizeLg = 24;
  static const double iconButtonSize = 28;

  // Input
  static const double inputMinHeight = 48;
  static const double inputBorderRadius = 24;

  // Context bar
  static const double contextBarHeight = 6;
  static const double contextBarRadius = 4;

  // Progress bar
  static const double progressBarHeight = 12;
  static const double progressBarRadius = 8;

  // Chat bubble
  static const double bubbleRadius = 16;
  static const double bubbleTightRadius = 4;

  // Bottom sheet
  static const double sheetRadius = 16;
}
