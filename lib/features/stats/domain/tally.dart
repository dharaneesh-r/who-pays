/// One player's appearance in one round, as stored.
class PlayerAppearance {
  const PlayerAppearance({
    required this.name,
    required this.lasted,
    required this.crackedFirst,
    required this.playedAt,
  });

  final String name;
  final Duration lasted;
  final bool crackedFirst;
  final DateTime playedAt;
}

/// A player's standing in the group. This is the thing people screenshot and
/// argue about, so the numbers have to be obvious and hard to dispute.
class PlayerTally {
  const PlayerTally({
    required this.name,
    required this.rounds,
    required this.firstCracks,
    required this.best,
  });

  final String name;
  final int rounds;

  /// How many times this player was the first to touch their phone.
  final int firstCracks;

  /// Longest they ever lasted.
  final Duration best;

  /// 0–1. The number nobody wants to be top of.
  double get crackRate => rounds == 0 ? 0 : firstCracks / rounds;
}

/// Builds the leaderboard from raw appearances.
///
/// Pure so it can be tested without a database — the aggregation is where the
/// bugs would be, not in the SQL.
List<PlayerTally> buildTallies(Iterable<PlayerAppearance> appearances) {
  final rounds = <String, int>{};
  final cracks = <String, int>{};
  final best = <String, Duration>{};

  for (final a in appearances) {
    rounds[a.name] = (rounds[a.name] ?? 0) + 1;
    if (a.crackedFirst) cracks[a.name] = (cracks[a.name] ?? 0) + 1;
    final current = best[a.name];
    if (current == null || a.lasted > current) best[a.name] = a.lasted;
  }

  final tallies = rounds.keys
      .map((name) => PlayerTally(
            name: name,
            rounds: rounds[name]!,
            firstCracks: cracks[name] ?? 0,
            best: best[name] ?? Duration.zero,
          ))
      .toList();

  // Worst offender first: most first-cracks, then the higher rate, then name
  // so the order never jitters between identical rows.
  tallies.sort((a, b) {
    final byCracks = b.firstCracks.compareTo(a.firstCracks);
    if (byCracks != 0) return byCracks;
    final byRate = b.crackRate.compareTo(a.crackRate);
    if (byRate != 0) return byRate;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  return tallies;
}

/// "Ramesh has cracked first 7 times this month" — the line that makes the
/// group come back. Returns null when there is nothing worth saying yet.
String? headline(List<PlayerTally> tallies) {
  if (tallies.isEmpty) return null;
  final worst = tallies.first;
  if (worst.firstCracks < 2) return null;

  // "You" is the fallback name for a player who never set one, and it is a
  // pronoun — "You has cracked first" reads as broken English.
  final verb = worst.name == 'You' ? 'have' : 'has';
  return '${worst.name} $verb cracked first ${worst.firstCracks} times';
}

/// Keeps only appearances inside the trailing window, so the leaderboard
/// reflects recent behaviour rather than someone's bad month a year ago.
///
/// Named `withinWindow` rather than `within` because `flutter_test` exports a
/// matcher of that name, and the clash is invisible until a test fails oddly.
Iterable<PlayerAppearance> withinWindow(
  Iterable<PlayerAppearance> appearances,
  Duration window, {
  required DateTime now,
}) {
  final cutoff = now.subtract(window);
  return appearances.where((a) => !a.playedAt.isBefore(cutoff));
}
