import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/prefs_service.dart';
import '../../../data/local/round_dao.dart';
import '../../game/domain/game_models.dart';
import '../domain/tally.dart';

/// How far back the leaderboard looks. Recent behaviour is what the group
/// cares about; a bad month last year is not interesting.
const tallyWindow = Duration(days: 30);

/// Writes a finished round to the database.
///
/// Separate from the game controller so the controller stays about game rules
/// and this stays about storage — and so a failed write can never break a round.
class RoundRecorder {
  RoundRecorder(this._dao, this._prefs);

  final RoundDao _dao;
  final PrefsService _prefs;

  Future<void> record({
    required GameConfig config,
    required RoundResult result,
    String? roomCode,
  }) async {
    final name = await _prefs.playerName();

    await _dao.saveRound(
      config: config,
      result: result,
      roomCode: roomCode,
      players: [
        PlayerAppearance(
          name: name,
          lasted: result.lasted,
          crackedFirst: result.outcome == RoundOutcome.caught,
          playedAt: DateTime.now(),
        ),
      ],
    );
  }
}

final roundRecorderProvider = Provider<RoundRecorder>((ref) {
  return RoundRecorder(
    ref.watch(roundDaoProvider),
    ref.watch(prefsServiceProvider),
  );
});

/// Bumped after each saved round so the stats screens refetch.
class StatsRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final statsRevisionProvider =
    NotifierProvider<StatsRevision, int>(StatsRevision.new);

final talliesProvider = FutureProvider<List<PlayerTally>>((ref) async {
  ref.watch(statsRevisionProvider);
  final dao = ref.watch(roundDaoProvider);
  final appearances =
      await dao.appearancesSince(DateTime.now().subtract(tallyWindow));
  return buildTallies(appearances);
});

final recentRoundsProvider = FutureProvider<List<StoredRound>>((ref) async {
  ref.watch(statsRevisionProvider);
  return ref.watch(roundDaoProvider).recentRounds();
});

final personalBestProvider = FutureProvider<Duration>((ref) async {
  ref.watch(statsRevisionProvider);
  final name = await ref.watch(playerNameProvider.future);
  return ref.watch(roundDaoProvider).personalBest(name);
});
