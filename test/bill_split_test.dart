import 'package:flutter_test/flutter_test.dart';
import 'package:who_pays/features/bill/domain/bill_split.dart';
import 'package:who_pays/features/game/domain/game_models.dart';

void main() {
  // The worked example from VENUES.md §15: four people, ₹2,400, Bala cracked.
  const table = ['Asha', 'Bala', 'Chitra', 'Dev'];
  const bill = 240000; // ₹2,400 in paise

  int owed(BillSplit split, String name) =>
      split.shares.firstWhere((s) => s.name == name).amountMinor;

  group('stake was the bill', () {
    test('the loser owes everything and nobody else owes a paisa', () {
      final split = BillSplit.compute(
        amountMinor: bill,
        stake: Stake.bill,
        participants: table,
        loser: 'Bala',
      );

      expect(split.loserPaysEverything, isTrue);
      expect(owed(split, 'Bala'), 240000);
      expect(owed(split, 'Asha'), 0);
      expect(owed(split, 'Chitra'), 0);
      expect(owed(split, 'Dev'), 0);
      expect(split.balances, isTrue);
    });

    test('splits equally when the round ran to time and nobody lost', () {
      // The table played for the bill and the bill went unclaimed. There is
      // nobody to charge, so it divides.
      final split = BillSplit.compute(
        amountMinor: bill,
        stake: Stake.bill,
        participants: table,
        loser: null,
      );

      expect(split.loserPaysEverything, isFalse);
      for (final name in table) {
        expect(owed(split, name), 60000);
      }
    });

    test('a loser who is not in the split is not handed the bill', () {
      // Stale name, or someone who left before the bill came.
      final split = BillSplit.compute(
        amountMinor: bill,
        stake: Stake.bill,
        participants: table,
        loser: 'Someone Else',
      );

      expect(split.loserPaysEverything, isFalse);
      expect(split.balances, isTrue);
      expect(split.shares.any((s) => s.isLoser), isFalse);
    });
  });

  group('stake was not the bill', () {
    test('everyone owes an equal share', () {
      final split = BillSplit.compute(
        amountMinor: bill,
        stake: Stake.nextRound,
        participants: table,
        loser: 'Bala',
      );

      expect(split.loserPaysEverything, isFalse);
      for (final name in table) {
        expect(owed(split, name), 60000);
      }
      expect(split.balances, isTrue);
    });

    test('a custom stake still splits equally', () {
      final split = BillSplit.compute(
        amountMinor: bill,
        stake: Stake.custom,
        participants: table,
        loser: 'Bala',
      );
      expect(owed(split, 'Asha'), 60000);
      expect(split.loserPaysEverything, isFalse);
    });

    test('the loser is still flagged, so the screen can name them', () {
      final split = BillSplit.compute(
        amountMinor: bill,
        stake: Stake.dishes,
        participants: table,
        loser: 'Bala',
      );
      expect(split.shares.where((s) => s.isLoser).map((s) => s.name), ['Bala']);
    });
  });

  group('the shares always add up — the invariant', () {
    test('an amount that will not divide loses nothing', () {
      // ₹100.01 across 3 people: 3333.67 paise each, which does not exist.
      final split = BillSplit.compute(
        amountMinor: 10001,
        stake: Stake.nextRound,
        participants: ['A', 'B', 'C'],
      );

      expect(split.allocatedMinor, 10001);
      expect(split.balances, isTrue);
      // The remainder lands on one person, not spread into rounding errors.
      final amounts = split.shares.map((s) => s.amountMinor).toList()..sort();
      expect(amounts, [3333, 3333, 3335]);
    });

    test('the remainder goes to the loser when there is one', () {
      final split = BillSplit.compute(
        amountMinor: 10001,
        stake: Stake.chores,
        participants: ['A', 'B', 'C'],
        loser: 'B',
      );
      expect(split.shares.firstWhere((s) => s.name == 'B').amountMinor, 3335);
      expect(split.balances, isTrue);
    });

    test('holds across many awkward amounts and table sizes', () {
      for (var people = 1; people <= 10; people++) {
        for (final amount in [1, 7, 99, 101, 12345, 999999]) {
          final split = BillSplit.compute(
            amountMinor: amount,
            stake: Stake.nextRound,
            participants: [
              for (var i = 0; i < people; i++) 'P$i',
            ],
            tipPercent: 13,
          );
          expect(
            split.allocatedMinor,
            split.totalMinor,
            reason: '$amount across $people people did not balance',
          );
        }
      }
    });

    test('two people with the same name only absorb the remainder once', () {
      final split = BillSplit.compute(
        amountMinor: 10001,
        stake: Stake.nextRound,
        participants: ['Dev', 'Dev', 'Asha'],
      );
      expect(split.allocatedMinor, 10001);
    });
  });

  group('tip', () {
    test('is added before splitting', () {
      final split = BillSplit.compute(
        amountMinor: 100000, // ₹1,000
        stake: Stake.nextRound,
        participants: ['A', 'B'],
        tipPercent: 10,
      );

      expect(split.subtotalMinor, 100000);
      expect(split.tipMinor, 10000);
      expect(split.totalMinor, 110000);
      expect(split.shares.every((s) => s.amountMinor == 55000), isTrue);
    });

    test('a tip the loser pays is still the loser’s problem', () {
      final split = BillSplit.compute(
        amountMinor: 100000,
        stake: Stake.bill,
        participants: ['A', 'B'],
        loser: 'B',
        tipPercent: 10,
      );
      expect(owed(split, 'B'), 110000);
      expect(owed(split, 'A'), 0);
    });

    test('a negative tip is treated as none', () {
      final split = BillSplit.compute(
        amountMinor: 100000,
        stake: Stake.nextRound,
        participants: ['A'],
        tipPercent: -20,
      );
      expect(split.tipMinor, 0);
      expect(split.totalMinor, 100000);
    });
  });

  group('bad input does not crash a dinner table', () {
    test('a negative bill is a typo, not a refund', () {
      final split = BillSplit.compute(
        amountMinor: -5000,
        stake: Stake.nextRound,
        participants: ['A', 'B'],
      );
      expect(split.totalMinor, 0);
      expect(split.shares.every((s) => s.amountMinor == 0), isTrue);
    });

    test('nobody in the split still reports the total', () {
      final split = BillSplit.compute(
        amountMinor: bill,
        stake: Stake.bill,
        participants: const [],
        loser: 'Bala',
      );
      expect(split.shares, isEmpty);
      expect(split.totalMinor, bill);
      expect(split.loserPaysEverything, isFalse);
    });

    test('a table of one owes the whole thing', () {
      final split = BillSplit.compute(
        amountMinor: bill,
        stake: Stake.nextRound,
        participants: ['Asha'],
      );
      expect(owed(split, 'Asha'), bill);
    });
  });
}
