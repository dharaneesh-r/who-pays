import 'package:flutter_test/flutter_test.dart';
import 'package:who_pays/features/stats/domain/tally.dart';

void main() {
  final now = DateTime(2026, 11, 6, 21);

  PlayerAppearance a(
    String name, {
    required int seconds,
    bool first = false,
    int daysAgo = 0,
  }) {
    return PlayerAppearance(
      name: name,
      lasted: Duration(seconds: seconds),
      crackedFirst: first,
      playedAt: now.subtract(Duration(days: daysAgo)),
    );
  }

  group('buildTallies', () {
    test('returns nothing for no history', () {
      expect(buildTallies([]), isEmpty);
    });

    test('counts rounds, first-cracks and the personal best', () {
      final tallies = buildTallies([
        a('Ramesh', seconds: 100, first: true),
        a('Ramesh', seconds: 400),
        a('Priya', seconds: 300),
      ]);

      final ramesh = tallies.firstWhere((t) => t.name == 'Ramesh');
      expect(ramesh.rounds, 2);
      expect(ramesh.firstCracks, 1);
      expect(ramesh.best, const Duration(seconds: 400));

      final priya = tallies.firstWhere((t) => t.name == 'Priya');
      expect(priya.firstCracks, 0);
      expect(priya.crackRate, 0);
    });

    test('puts the worst offender first', () {
      final tallies = buildTallies([
        a('Priya', seconds: 10, first: true),
        a('Ramesh', seconds: 10, first: true),
        a('Ramesh', seconds: 10, first: true),
        a('Arjun', seconds: 900),
      ]);

      expect(tallies.first.name, 'Ramesh');
      expect(tallies.last.name, 'Arjun');
    });

    test('breaks a tie on crack rate, then on name, so order never jitters', () {
      // Both cracked twice, but Priya did it in fewer rounds.
      final tallies = buildTallies([
        a('Priya', seconds: 10, first: true),
        a('Priya', seconds: 10, first: true),
        a('Ramesh', seconds: 10, first: true),
        a('Ramesh', seconds: 10, first: true),
        a('Ramesh', seconds: 500),
      ]);

      expect(tallies.map((t) => t.name).toList(), ['Priya', 'Ramesh']);
      expect(buildTallies([a('zoe', seconds: 5), a('Adam', seconds: 5)])
          .map((t) => t.name)
          .toList(),
          ['Adam', 'zoe']);
    });

    test('crackRate is a fraction of rounds played', () {
      final tallies = buildTallies([
        a('Ramesh', seconds: 10, first: true),
        a('Ramesh', seconds: 10, first: true),
        a('Ramesh', seconds: 10),
        a('Ramesh', seconds: 10),
      ]);
      expect(tallies.single.crackRate, 0.5);
    });
  });

  group('within', () {
    test('drops rounds older than the window', () {
      final appearances = [
        a('Ramesh', seconds: 10, daysAgo: 2),
        a('Ramesh', seconds: 10, daysAgo: 45),
      ];

      final recent =
          withinWindow(appearances, const Duration(days: 30), now: now).toList();
      expect(recent, hasLength(1));
    });

    test('keeps a round exactly on the boundary', () {
      final appearances = [a('Ramesh', seconds: 10, daysAgo: 30)];
      expect(withinWindow(appearances, const Duration(days: 30), now: now), hasLength(1));
    });
  });

  group('headline', () {
    test('says nothing until someone has cracked twice', () {
      expect(headline([]), isNull);
      expect(headline(buildTallies([a('Ramesh', seconds: 10, first: true)])),
          isNull);
    });

    test('conjugates for the fallback name, which is a pronoun', () {
      // "You has cracked first" is how this read before.
      final tallies = buildTallies([
        a('You', seconds: 10, first: true),
        a('You', seconds: 10, first: true),
      ]);
      expect(headline(tallies), 'You have cracked first 2 times');
    });

    test('names the worst offender once there is a pattern', () {
      final tallies = buildTallies([
        a('Ramesh', seconds: 10, first: true),
        a('Ramesh', seconds: 10, first: true),
        a('Ramesh', seconds: 10, first: true),
      ]);
      expect(headline(tallies), 'Ramesh has cracked first 3 times');
    });
  });
}
