/// One person's best round on one day.
class DuelScore {
  const DuelScore({
    required this.deviceId,
    required this.name,
    required this.best,
    required this.day,
    required this.updatedAt,
  });

  final String deviceId;
  final String name;

  /// The longest single round they managed that day — not a total. The duel
  /// rewards one good stretch, not grinding out many short ones.
  final Duration best;

  final DateTime day;
  final DateTime updatedAt;

  factory DuelScore.fromRow(Map<String, dynamic> row) {
    return DuelScore(
      deviceId: row['device_id'] as String,
      name: row['name'] as String,
      best: Duration(milliseconds: row['best_ms'] as int),
      day: DateTime.tryParse(row['day'] as String? ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(row['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

class Duel {
  const Duel({required this.code, required this.name});

  final String code;
  final String name;

  factory Duel.fromRow(Map<String, dynamic> row) => Duel(
        code: row['code'] as String,
        name: row['name'] as String? ?? 'Focus Duel',
      );
}

/// Today's board for one duel.
class DuelBoard {
  const DuelBoard({
    required this.duel,
    required this.scores,
    this.wins = const {},
  });

  final Duel duel;
  final List<DuelScore> scores;

  /// device id → days won, all time.
  final Map<String, int> wins;

  /// Longest first. Ties go to whoever got there first, so a draw still
  /// produces one leader rather than an argument.
  List<DuelScore> get ranked {
    final sorted = [...scores];
    sorted.sort((a, b) {
      final byBest = b.best.compareTo(a.best);
      if (byBest != 0) return byBest;
      return a.updatedAt.compareTo(b.updatedAt);
    });
    return sorted;
  }

  DuelScore? get leader => ranked.isEmpty ? null : ranked.first;

  DuelScore? scoreFor(String deviceId) =>
      scores.where((s) => s.deviceId == deviceId).firstOrNull;

  /// How far behind the leader this phone is. Null when leading, or when
  /// they have not played today.
  Duration? gapFor(String deviceId) {
    final mine = scoreFor(deviceId);
    final top = leader;
    if (mine == null || top == null) return null;
    if (top.deviceId == deviceId) return null;
    return top.best - mine.best;
  }

  bool get nobodyHasPlayed => scores.isEmpty;
}

/// Is this round worth sending? Only a personal best for the day counts, so a
/// string of short rounds never overwrites a good one.
bool beatsToday(Duration round, Duration? currentBest) =>
    currentBest == null || round > currentBest;
