import 'package:flutter_test/flutter_test.dart';
import 'package:who_pays/data/remote/duel_repository.dart';
import 'package:who_pays/features/duel/domain/duel_models.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 7, 9);
  const duel = Duel(code: 'ABCD', name: 'Flat 3B');

  DuelScore score(
    String name, {
    required String device,
    required int seconds,
    int postedMinutesIn = 0,
  }) {
    return DuelScore(
      deviceId: device,
      name: name,
      best: Duration(seconds: seconds),
      day: t0,
      updatedAt: t0.add(Duration(minutes: postedMinutesIn)),
    );
  }

  group('ranking', () {
    test('longest round leads', () {
      final board = DuelBoard(duel: duel, scores: [
        score('Short', device: 'a', seconds: 120),
        score('Long', device: 'b', seconds: 900),
        score('Middle', device: 'c', seconds: 400),
      ]);

      expect(board.ranked.map((s) => s.name), ['Long', 'Middle', 'Short']);
      expect(board.leader?.name, 'Long');
    });

    test('a tie goes to whoever got there first', () {
      final board = DuelBoard(duel: duel, scores: [
        score('Later', device: 'a', seconds: 600, postedMinutesIn: 90),
        score('Earlier', device: 'b', seconds: 600, postedMinutesIn: 10),
      ]);

      expect(board.leader?.name, 'Earlier',
          reason: 'a draw must still produce one winner, not an argument');
    });

    test('an empty board has no leader and says so', () {
      const board = DuelBoard(duel: duel, scores: []);
      expect(board.leader, isNull);
      expect(board.nobodyHasPlayed, isTrue);
    });
  });

  group('where you stand', () {
    test('the leader has no gap', () {
      final board = DuelBoard(duel: duel, scores: [
        score('Me', device: 'me', seconds: 900),
        score('Them', device: 'them', seconds: 300),
      ]);
      expect(board.gapFor('me'), isNull);
    });

    test('a trailing player sees how far behind they are', () {
      final board = DuelBoard(duel: duel, scores: [
        score('Me', device: 'me', seconds: 300),
        score('Them', device: 'them', seconds: 900),
      ]);
      expect(board.gapFor('me'), const Duration(seconds: 600));
    });

    test('someone who has not played has no gap to show', () {
      final board = DuelBoard(duel: duel, scores: [
        score('Them', device: 'them', seconds: 900),
      ]);
      expect(board.gapFor('me'), isNull);
      expect(board.scoreFor('me'), isNull);
    });
  });

  group('beatsToday', () {
    test('a first round of the day always counts', () {
      expect(beatsToday(const Duration(seconds: 5), null), isTrue);
    });

    test('only a longer round replaces the day\'s best', () {
      const best = Duration(minutes: 10);
      expect(beatsToday(const Duration(minutes: 11), best), isTrue);
      expect(beatsToday(const Duration(minutes: 9), best), isFalse);
      expect(beatsToday(best, best), isFalse,
          reason: 'an equal round is not an improvement');
    });
  });

  group('todayKey', () {
    test('is the local calendar day, zero padded', () {
      expect(DuelRepository.todayKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(DuelRepository.todayKey(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('uses local time, not UTC', () {
      // Late evening local is already the next day in UTC in India. The duel
      // is "who lasted longest today", and today must mean the player's day.
      final lateEvening = DateTime(2026, 11, 7, 23, 30);
      expect(DuelRepository.todayKey(lateEvening), '2026-11-07');
    });
  });
}
