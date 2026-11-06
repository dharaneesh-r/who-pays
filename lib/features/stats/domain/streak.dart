/// The phone-free dinner streak.
///
/// This is the only mechanic in the app with a reason to open it on a random
/// Tuesday. Everything else is event-driven — someone has to organise a dinner
/// — so without this the app is a party trick people install and forget.
class Streak {
  const Streak({required this.current, required this.best, this.playedToday = false});

  static const none = Streak(current: 0, best: 0);

  final int current;
  final int best;
  final bool playedToday;

  bool get isAlive => current > 0;
}

/// Calendar day, ignoring the time of day.
DateTime dayOf(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day);

/// Works out the streak from the days rounds were played on.
///
/// Counts *days with at least one round*, not rounds — three games at one
/// dinner is one night out, and claiming it as three would make the number
/// meaningless.
Streak computeStreak(Iterable<DateTime> playedAt, {required DateTime now}) {
  final days = playedAt.map(dayOf).toSet().toList()
    ..sort((a, b) => b.compareTo(a)); // newest first

  if (days.isEmpty) return Streak.none;

  final today = dayOf(now);
  final yesterday = today.subtract(const Duration(days: 1));
  final playedToday = days.first == today;

  // A streak survives until the end of the next day: playing on Monday and
  // then Wednesday morning breaks it, but Monday then Tuesday night does not.
  var current = 0;
  if (days.first == today || days.first == yesterday) {
    var expected = days.first;
    for (final day in days) {
      if (day == expected) {
        current++;
        expected = expected.subtract(const Duration(days: 1));
      } else if (day.isBefore(expected)) {
        break;
      }
    }
  }

  // Longest run anywhere in the history.
  var best = 1;
  var run = 1;
  for (var i = 1; i < days.length; i++) {
    final gap = days[i - 1].difference(days[i]).inDays;
    if (gap == 1) {
      run++;
    } else {
      run = 1;
    }
    if (run > best) best = run;
  }

  return Streak(
    current: current,
    best: best > current ? best : current,
    playedToday: playedToday,
  );
}
