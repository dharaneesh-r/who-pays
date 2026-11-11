/// Who owes what after the round.
///
/// Spec: VENUES.md §15.
///
/// **Why this is "stake-aware".** The app's whole premise is that the loser
/// pays. A plain equal split would contradict the game it is attached to: the
/// result screen would announce "Bala pays the bill" and the next screen would
/// ask everyone for a quarter of it. So the split reads the stake that was
/// actually played for:
///
///   * stake was *pays the bill*  → the loser owes the whole total, others ₹0
///   * any other stake           → split equally; the stake is settled off-app
///
/// One screen, two answers, decided by what the table bet.
///
/// **Why integers.** Money is held in minor units — paise, cents — and never
/// in a double. `0.1 + 0.2` is not `0.3`, and a split that loses a rupee to
/// floating point is the kind of bug six people notice while staring at a
/// bill.
library;

import '../../game/domain/game_models.dart';

/// One line on the split screen.
class BillShare {
  const BillShare({
    required this.name,
    required this.amountMinor,
    required this.isLoser,
  });

  final String name;

  /// What this person owes, in minor units (paise / cents).
  final int amountMinor;

  /// Whether this is the person who cracked first. Shown differently, and the
  /// recipient of any indivisible remainder.
  final bool isLoser;
}

/// The computed split. Build one with [BillSplit.compute].
class BillSplit {
  const BillSplit({
    required this.subtotalMinor,
    required this.tipMinor,
    required this.totalMinor,
    required this.shares,
    required this.loserPaysEverything,
  });

  /// The bill as entered, before tip.
  final int subtotalMinor;

  /// Tip added, in minor units. Zero when no tip was set.
  final int tipMinor;

  /// What the table owes in total — [subtotalMinor] + [tipMinor]. This is the
  /// number the shares must add up to.
  final int totalMinor;

  final List<BillShare> shares;

  /// True when the stake was *pays the bill* and there is a loser to pay it.
  /// The UI reads this to decide whether to say "Bala owes everything" or
  /// "everyone owes an equal share".
  final bool loserPaysEverything;

  /// The invariant worth testing: the shares add up to exactly the total.
  /// Nothing is lost to rounding, ever.
  int get allocatedMinor =>
      shares.fold(0, (sum, share) => sum + share.amountMinor);

  bool get balances => allocatedMinor == totalMinor;

  /// Work out who owes what.
  ///
  /// [amountMinor] is the bill before tip, in minor units. [participants] are
  /// the people in the split — anyone who did not eat is simply left out of
  /// the list. [loser] is the name of whoever cracked first, or null when the
  /// round ran to time and nobody lost.
  static BillSplit compute({
    required int amountMinor,
    required Stake stake,
    required List<String> participants,
    String? loser,
    int tipPercent = 0,
  }) {
    // A negative bill is not a refund, it is a typo. Clamp rather than throw:
    // this runs behind a text field at a dinner table.
    final subtotal = amountMinor < 0 ? 0 : amountMinor;
    final tipPct = tipPercent < 0 ? 0 : tipPercent;
    final tip = (subtotal * tipPct / 100).round();
    final total = subtotal + tip;

    // The loser only counts if they are actually in the split. A name that is
    // not among the participants — someone who left, or a stale value — must
    // not be handed the bill.
    final loserInSplit =
        loser != null && participants.contains(loser) ? loser : null;

    // No participants means no shares. The totals are still reported so the
    // screen can show the bill and ask who is paying.
    if (participants.isEmpty) {
      return BillSplit(
        subtotalMinor: subtotal,
        tipMinor: tip,
        totalMinor: total,
        shares: const [],
        loserPaysEverything: false,
      );
    }

    // Stake was the bill itself, and somebody lost: they owe all of it.
    //
    // When the stake was the bill but *nobody* lost — the round ran to time
    // and every phone stayed down — there is no one to charge, so this falls
    // through to an equal split. That is the honest answer: the table played
    // for the bill and the bill went unclaimed.
    if (stake == Stake.bill && loserInSplit != null) {
      return BillSplit(
        subtotalMinor: subtotal,
        tipMinor: tip,
        totalMinor: total,
        shares: [
          for (final name in participants)
            BillShare(
              name: name,
              amountMinor: name == loserInSplit ? total : 0,
              isLoser: name == loserInSplit,
            ),
        ],
        loserPaysEverything: true,
      );
    }

    // Everything else splits equally.
    final n = participants.length;
    final base = total ~/ n;

    // What will not divide — at most n-1 minor units. It goes to the loser if
    // there is one, otherwise to the first person listed (the host). Someone
    // has to absorb it or the shares would not sum to the total, and the
    // person who cracked is the fairest candidate.
    final remainder = total - (base * n);
    final absorber = loserInSplit ?? participants.first;
    var remainderGiven = false;

    return BillSplit(
      subtotalMinor: subtotal,
      tipMinor: tip,
      totalMinor: total,
      shares: [
        for (final name in participants)
          BillShare(
            name: name,
            amountMinor: () {
              // `name == absorber` can be true more than once if two people
              // share a name, so the remainder is handed out at most once.
              if (name == absorber && !remainderGiven) {
                remainderGiven = true;
                return base + remainder;
              }
              return base;
            }(),
            isLoser: name == loserInSplit,
          ),
      ],
      loserPaysEverything: false,
    );
  }
}
