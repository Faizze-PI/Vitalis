import 'package:flutter_test/flutter_test.dart';
import 'package:vitalis_app/utils/date_formatter.dart';

void main() {
  group('DateFormatter', () {
    test('formatRelative returns justNow for recent timestamps', () {
      final now = DateTime.now();
      expect(DateFormatter.formatRelative(now), 'just now');
      expect(
        DateFormatter.formatRelative(now.subtract(const Duration(seconds: 30))),
        'just now',
      );
    });

    test(
      'formatRelative returns minutes ago for timestamps within an hour',
      () {
        final now = DateTime.now();
        expect(
          DateFormatter.formatRelative(
            now.subtract(const Duration(minutes: 5)),
          ),
          '5m ago',
        );
        expect(
          DateFormatter.formatRelative(
            now.subtract(const Duration(minutes: 59)),
          ),
          '59m ago',
        );
      },
    );

    test('formatRelative returns hours ago for timestamps within a day', () {
      final now = DateTime.now();
      expect(
        DateFormatter.formatRelative(now.subtract(const Duration(hours: 3))),
        '3h ago',
      );
      expect(
        DateFormatter.formatRelative(now.subtract(const Duration(hours: 23))),
        '23h ago',
      );
    });

    test('formatRelative returns date for older timestamps', () {
      final now = DateTime.now();
      final twoDaysAgo = now.subtract(const Duration(days: 2));
      final result = DateFormatter.formatRelative(twoDaysAgo);
      expect(result, contains('/'));
      expect(result, contains(':'));
    });

    test('formatChatDate returns justNow for very recent timestamps', () {
      final now = DateTime.now();
      expect(DateFormatter.formatChatDate(now), 'just now');
    });

    test('formatChatDate returns minutes ago', () {
      final now = DateTime.now();
      final result = DateFormatter.formatChatDate(
        now.subtract(const Duration(minutes: 15)),
      );
      expect(result, contains('m ago'));
    });

    test('formatChatDate returns hours ago', () {
      final now = DateTime.now();
      final result = DateFormatter.formatChatDate(
        now.subtract(const Duration(hours: 5)),
      );
      expect(result, contains('h ago'));
    });

    test('formatChatDate returns days ago', () {
      final now = DateTime.now();
      final result = DateFormatter.formatChatDate(
        now.subtract(const Duration(days: 3)),
      );
      expect(result, contains('d ago'));
    });
  });
}
