import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_app/services/backup/relative_time.dart';

void main() {
  // Sunday 9:42 AM, so the weekday branch has a name worth asserting on.
  final now = DateTime(2026, 8, 16, 9, 42);

  group('relativeAge', () {
    test('under a minute is "just now"', () {
      expect(relativeAge(now.subtract(const Duration(seconds: 59)), now),
          'just now');
    });

    test('a future timestamp reads "just now", never a negative age', () {
      expect(relativeAge(now.add(const Duration(minutes: 5)), now), 'just now');
    });

    test('exactly one minute crosses into the minutes ladder, singular', () {
      expect(relativeAge(now.subtract(const Duration(seconds: 60)), now),
          '1 minute ago');
    });

    test('59 minutes stays in minutes', () {
      expect(relativeAge(now.subtract(const Duration(minutes: 59)), now),
          '59 minutes ago');
    });

    test('exactly 60 minutes crosses into hours, singular', () {
      expect(relativeAge(now.subtract(const Duration(minutes: 60)), now),
          '1 hour ago');
    });

    test('23h59m stays in hours', () {
      expect(
          relativeAge(
              now.subtract(const Duration(hours: 23, minutes: 59)), now),
          '23 hours ago');
    });

    test('exactly 24 hours crosses into the weekday ladder', () {
      expect(relativeAge(now.subtract(const Duration(hours: 24)), now),
          'Saturday 9:42 AM');
    });

    test('6d23h stays on the weekday ladder', () {
      expect(
          relativeAge(now.subtract(const Duration(days: 6, hours: 23)), now),
          'Sunday 10:42 AM');
    });

    test('exactly 7 days crosses to the absolute date', () {
      expect(relativeAge(now.subtract(const Duration(days: 7)), now),
          '9 Aug, 9:42 AM');
    });

    test('midnight and noon render as 12, not 0', () {
      expect(relativeAge(DateTime(2026, 8, 1, 0, 5), now), '1 Aug, 12:05 AM');
      expect(relativeAge(DateTime(2026, 8, 1, 12, 5), now), '1 Aug, 12:05 PM');
    });
  });

  group('compactAge', () {
    test('ladders at the same boundaries in fewer characters', () {
      expect(compactAge(now.subtract(const Duration(seconds: 59)), now),
          'just now');
      expect(
          compactAge(now.subtract(const Duration(minutes: 59)), now), '59m ago');
      expect(compactAge(now.subtract(const Duration(minutes: 60)), now), '1h ago');
      expect(compactAge(now.subtract(const Duration(hours: 23)), now), '23h ago');
      expect(compactAge(now.subtract(const Duration(hours: 24)), now), '1d ago');
      expect(compactAge(now.subtract(const Duration(days: 6)), now), '6d ago');
      expect(compactAge(now.subtract(const Duration(days: 7)), now), 'on 9 Aug');
    });
  });
}
