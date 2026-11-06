import 'package:flutter_test/flutter_test.dart';
import 'package:who_pays/features/stats/domain/streak.dart';

void main() {
  final now = DateTime(2026, 11, 6, 21, 30);
  DateTime daysAgo(int n, {int hour = 20}) =>
      DateTime(2026, 11, 6 - n, hour, 15);

  group('computeStreak', () {
    test('no history means no streak', () {
      final streak = computeStreak([], now: now);
      expect(streak.current, 0);
      expect(streak.best, 0);
      expect(streak.isAlive, isFalse);
      expect(streak.playedToday, isFalse);
    });

    test('counts consecutive days ending today', () {
      final streak = computeStreak(
        [daysAgo(0), daysAgo(1), daysAgo(2)],
        now: now,
      );
      expect(streak.current, 3);
      expect(streak.playedToday, isTrue);
    });

    test('several rounds in one night count as one day', () {
      final streak = computeStreak(
        [daysAgo(0, hour: 19), daysAgo(0, hour: 20), daysAgo(0, hour: 22)],
        now: now,
      );
      expect(streak.current, 1,
          reason: 'three games at one dinner is still one night out');
    });

    test('a streak survives until the end of the next day', () {
      // Played yesterday, not yet today — still alive.
      final streak = computeStreak([daysAgo(1), daysAgo(2)], now: now);
      expect(streak.current, 2);
      expect(streak.playedToday, isFalse);
    });

    test('a two-day gap breaks the streak', () {
      final streak = computeStreak([daysAgo(2), daysAgo(3)], now: now);
      expect(streak.current, 0);
      expect(streak.isAlive, isFalse);
    });

    test('remembers the best run even after the current one dies', () {
      final streak = computeStreak(
        [daysAgo(10), daysAgo(11), daysAgo(12), daysAgo(13)],
        now: now,
      );
      expect(streak.current, 0);
      expect(streak.best, 4);
    });

    test('best is never lower than the current streak', () {
      final streak = computeStreak([daysAgo(0), daysAgo(1)], now: now);
      expect(streak.best, greaterThanOrEqualTo(streak.current));
    });

    test('ignores the order the days arrive in', () {
      final streak = computeStreak(
        [daysAgo(2), daysAgo(0), daysAgo(1)],
        now: now,
      );
      expect(streak.current, 3);
    });

    test('a single round today is a streak of one', () {
      expect(computeStreak([daysAgo(0)], now: now).current, 1);
    });
  });

  group('dayOf', () {
    test('strips the time', () {
      expect(dayOf(DateTime(2026, 11, 6, 23, 59)), DateTime(2026, 11, 6));
      expect(dayOf(DateTime(2026, 11, 6, 0, 1)), DateTime(2026, 11, 6));
    });
  });
}
