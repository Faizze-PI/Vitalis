import '../constants/app_strings.dart';

class DateFormatter {
  static String formatRelative(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return AppStrings.justNow;
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  static String formatChatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return AppStrings.justNow;
    if (diff.inHours < 1)
      return AppStrings.minutesAgo.replaceFirst('{count}', '${diff.inMinutes}');
    if (diff.inDays < 1)
      return AppStrings.hoursAgo.replaceFirst('{count}', '${diff.inHours}');
    return AppStrings.daysAgo.replaceFirst('{count}', '${diff.inDays}');
  }
}
