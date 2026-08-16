import 'package:app/util/clock_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 16, 14, 30);

  String isoAgo(Duration age) => now.subtract(age).toIso8601String();

  group('formatRelativeTime', () {
    test('empty and unparseable are blank', () {
      expect(formatRelativeTime(null, now: now), '');
      expect(formatRelativeTime('', now: now), '');
      expect(formatRelativeTime('not-a-date', now: now), '');
    });

    test('age 0m is local HH:MM, not now', () {
      expect(formatRelativeTime(isoAgo(Duration.zero), now: now), '14:30');
    });

    test('age 23h59 is local HH:MM of the received timestamp', () {
      expect(
        formatRelativeTime(
          isoAgo(const Duration(hours: 23, minutes: 59)),
          now: now,
        ),
        '14:31',
      );
    });

    test('age 24h is 1d', () {
      expect(
        formatRelativeTime(isoAgo(const Duration(hours: 24)), now: now),
        '1d',
      );
    });

    test('age 2d is 2d', () {
      expect(
        formatRelativeTime(isoAgo(const Duration(days: 2)), now: now),
        '2d',
      );
    });

    test('age 6d is 6d', () {
      expect(
        formatRelativeTime(isoAgo(const Duration(days: 6)), now: now),
        '6d',
      );
    });

    test('age 7d is 1w', () {
      expect(
        formatRelativeTime(isoAgo(const Duration(days: 7)), now: now),
        '1w',
      );
    });

    test('age 30d is 1m (months, not minutes)', () {
      expect(
        formatRelativeTime(isoAgo(const Duration(days: 30)), now: now),
        '1m',
      );
    });

    test('never emits yday, yesterday, now, or minute-m', () {
      for (final age in [
        Duration.zero,
        const Duration(minutes: 2),
        const Duration(hours: 23, minutes: 59),
        const Duration(hours: 24),
        const Duration(days: 1),
      ]) {
        final label = formatRelativeTime(isoAgo(age), now: now);
        expect(label, isNot(anyOf('now', 'yday', 'yesterday', '2m')));
      }
    });
  });
}
