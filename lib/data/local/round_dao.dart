import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/detector/domain/detector_models.dart';
import '../../features/game/domain/game_models.dart';
import '../../features/stats/domain/tally.dart';
import 'app_database.dart';

/// A finished round as stored and read back.
class StoredRound {
  const StoredRound({
    required this.id,
    required this.playedAt,
    required this.stakeText,
    required this.lasted,
    required this.outcome,
    this.reason,
    this.roomCode,
  });

  final int id;
  final DateTime playedAt;
  final String stakeText;
  final Duration lasted;
  final RoundOutcome outcome;
  final CatchReason? reason;
  final String? roomCode;
}

class RoundDao {
  RoundDao(this._database);

  final AppDatabase _database;

  /// Saves a finished round plus one row per player.
  ///
  /// For a solo round that is a single player; the same shape covers a full
  /// table once rooms arrive, so nothing has to be migrated later.
  Future<int> saveRound({
    required GameConfig config,
    required RoundResult result,
    required List<PlayerAppearance> players,
    String? roomCode,
    DateTime? playedAt,
  }) async {
    if (kIsWeb) return 0;
    final db = await _database.instance;

    return db.transaction((txn) async {
      final roundId = await txn.insert('rounds', {
        'played_at': (playedAt ?? DateTime.now()).millisecondsSinceEpoch,
        'stake': config.stake.name,
        'custom_stake': config.customStake,
        'target_ms': config.target?.inMilliseconds,
        'lasted_ms': result.lasted.inMilliseconds,
        'outcome': result.outcome.name,
        'reason': result.reason?.name,
        'room_code': roomCode,
      });

      final batch = txn.batch();
      for (final player in players) {
        batch.insert('round_players', {
          'round_id': roundId,
          'name': player.name,
          'lasted_ms': player.lasted.inMilliseconds,
          'cracked_first': player.crackedFirst ? 1 : 0,
        });
      }
      await batch.commit(noResult: true);

      return roundId;
    });
  }

  Future<List<StoredRound>> recentRounds({int limit = 50}) async {
    if (kIsWeb) return const [];
    final db = await _database.instance;
    final rows = await db.query(
      'rounds',
      orderBy: 'played_at DESC',
      limit: limit,
    );

    return rows.map((row) {
      final stake = Stake.values.firstWhere(
        (s) => s.name == row['stake'],
        orElse: () => Stake.bill,
      );
      final config = GameConfig(
        stake: stake,
        customStake: row['custom_stake'] as String?,
      );

      return StoredRound(
        id: row['id'] as int,
        playedAt:
            DateTime.fromMillisecondsSinceEpoch(row['played_at'] as int),
        stakeText: config.stakeText,
        lasted: Duration(milliseconds: row['lasted_ms'] as int),
        outcome: row['outcome'] == RoundOutcome.survived.name
            ? RoundOutcome.survived
            : RoundOutcome.caught,
        reason: _reasonFrom(row['reason'] as String?),
        roomCode: row['room_code'] as String?,
      );
    }).toList();
  }

  /// Every player appearance since [since], for the leaderboard.
  Future<List<PlayerAppearance>> appearancesSince(DateTime since) async {
    if (kIsWeb) return const [];
    final db = await _database.instance;
    final rows = await db.rawQuery(
      '''
      SELECT p.name, p.lasted_ms, p.cracked_first, r.played_at
      FROM round_players p
      JOIN rounds r ON r.id = p.round_id
      WHERE r.played_at >= ?
      ORDER BY r.played_at DESC
      ''',
      [since.millisecondsSinceEpoch],
    );

    return rows
        .map((row) => PlayerAppearance(
              name: row['name'] as String,
              lasted: Duration(milliseconds: row['lasted_ms'] as int),
              crackedFirst: (row['cracked_first'] as int) == 1,
              playedAt:
                  DateTime.fromMillisecondsSinceEpoch(row['played_at'] as int),
            ))
        .toList();
  }

  /// Rounds played since midnight — what the free tier is counted against.
  Future<int> roundsToday() async {
    if (kIsWeb) return 0;
    final db = await _database.instance;
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);

    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM rounds WHERE played_at >= ?',
      [midnight.millisecondsSinceEpoch],
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  /// Every day on which a round was played, newest first. Feeds the streak.
  Future<List<DateTime>> playedDays({int limit = 400}) async {
    if (kIsWeb) return const [];
    final db = await _database.instance;
    final rows = await db.query(
      'rounds',
      columns: ['played_at'],
      orderBy: 'played_at DESC',
      limit: limit,
    );
    return rows
        .map((row) =>
            DateTime.fromMillisecondsSinceEpoch(row['played_at'] as int))
        .toList();
  }

  /// Longest this player has ever lasted.
  Future<Duration> personalBest(String name) async {
    if (kIsWeb) return Duration.zero;
    final db = await _database.instance;
    final rows = await db.rawQuery(
      'SELECT MAX(lasted_ms) AS best FROM round_players WHERE name = ?',
      [name],
    );
    final best = rows.first['best'] as int?;
    return Duration(milliseconds: best ?? 0);
  }

  static CatchReason? _reasonFrom(String? name) {
    if (name == null) return null;
    for (final reason in CatchReason.values) {
      if (reason.name == name) return reason;
    }
    return null;
  }
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final roundDaoProvider = Provider<RoundDao>(
  (ref) => RoundDao(ref.watch(appDatabaseProvider)),
);
