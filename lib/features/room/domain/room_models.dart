import '../../detector/domain/detector_models.dart';
import '../../game/domain/game_models.dart';

enum RoomStatus { lobby, settling, running, finished }

RoomStatus roomStatusFrom(String? value) => switch (value) {
      'settling' => RoomStatus.settling,
      'running' => RoomStatus.running,
      'finished' => RoomStatus.finished,
      _ => RoomStatus.lobby,
    };

class Room {
  const Room({
    required this.code,
    required this.hostId,
    required this.status,
    required this.config,
    this.startedAt,
    this.decidedVenueId,
  });

  final String code;
  final String hostId;
  final RoomStatus status;
  final GameConfig config;
  final DateTime? startedAt;

  /// The venue the host settled on, or null while the table is still voting.
  ///
  /// Null on a database without `migration_venues.sql` applied, which reads as
  /// "no decision" — the same as a table that has not voted. That is the safe
  /// direction: the venue feature quietly does nothing rather than breaking
  /// the game.
  final String? decidedVenueId;

  bool isHost(String deviceId) => hostId == deviceId;

  factory Room.fromRow(Map<String, dynamic> row) {
    final stake = Stake.values.firstWhere(
      (s) => s.name == row['stake'],
      orElse: () => Stake.bill,
    );
    final targetMs = row['target_ms'] as int?;

    return Room(
      code: row['code'] as String,
      hostId: row['host_id'] as String,
      status: roomStatusFrom(row['status'] as String?),
      config: GameConfig(
        stake: stake,
        customStake: row['custom_stake'] as String?,
        target: targetMs == null ? null : Duration(milliseconds: targetMs),
      ),
      startedAt: row['started_at'] == null
          ? null
          : DateTime.tryParse(row['started_at'] as String),
      decidedVenueId: row['decided_venue_id'] as String?,
    );
  }
}

class RoomPlayer {
  const RoomPlayer({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.joinedAt,
    required this.lastSeen,
    this.caughtAt,
    this.lasted,
    this.reason,
  });

  final String id;
  final String deviceId;
  final String name;
  final DateTime joinedAt;

  /// Last time this phone reported in. A player who closes the app stops
  /// touching this, which is how the table notices they are gone.
  /// When this phone last said it was still here.
  ///
  /// Null means the database has no presence column at all — not that the
  /// player is absent. The two must not be confused: treating "unknown" as
  /// "gone" ejects everybody 45 seconds after they join, which silently ends
  /// the round and blames the wrong person.
  final DateTime? lastSeen;

  /// Null while still in the game.
  final DateTime? caughtAt;
  final Duration? lasted;
  final CatchReason? reason;

  bool get isOut => caughtAt != null;

  factory RoomPlayer.fromRow(Map<String, dynamic> row) {
    final lastedMs = row['lasted_ms'] as int?;
    final reasonName = row['catch_reason'] as String?;

    final joined = DateTime.tryParse(row['joined_at'] as String? ?? '') ??
        DateTime.now();

    return RoomPlayer(
      id: row['id'] as String,
      deviceId: row['device_id'] as String,
      name: row['name'] as String,
      joinedAt: joined,
      // Absent column (migration not applied) stays null, which means
      // "presence is unknowable here" rather than "left the table".
      lastSeen: row['last_seen'] == null
          ? null
          : DateTime.tryParse(row['last_seen'] as String? ?? ''),
      caughtAt: row['caught_at'] == null
          ? null
          : DateTime.tryParse(row['caught_at'] as String),
      lasted: lastedMs == null ? null : Duration(milliseconds: lastedMs),
      reason: reasonName == null
          ? null
          : CatchReason.values
              .where((r) => r.name == reasonName)
              .firstOrNull,
    );
  }
}

/// The whole table, as this phone currently understands it.
class RoomSnapshot {
  const RoomSnapshot({
    required this.room,
    required this.players,
    this.confirmedGone = const {},
    this.now,
  });

  final Room room;
  final List<RoomPlayer> players;

  /// Device ids this phone has watched disconnect and stay disconnected.
  ///
  /// Worked out by the session from the realtime channel, not from any
  /// column, so it still works on a database without the presence migration.
  /// Empty means "nothing known", never "nobody is here".
  final Set<String> confirmedGone;

  /// Injectable so presence can be tested without waiting in real time.
  final DateTime? now;

  /// How long a phone can go quiet before the table assumes it left.
  /// Comfortably longer than the heartbeat interval, so one missed beat on a
  /// bad restaurant connection does not eject anybody.
  static const presenceTimeout = Duration(seconds: 45);

  DateTime get _now => now ?? DateTime.now();

  /// A caught player stays on the board forever — they already have a result.
  /// Only someone still playing can go absent.
  /// A database without the presence column cannot tell us who wandered off,
  /// so everyone counts as present — exactly how the app behaved before
  /// presence existed. Better a stuck table than ejecting live players.
  bool isAtTable(RoomPlayer p) {
    // A caught player already has a result; they cannot un-lose by leaving.
    if (p.isOut) return true;
    // Watched them drop off the socket and stay off.
    if (confirmedGone.contains(p.deviceId)) return false;
    final seen = p.lastSeen;
    // No presence column on this database: nothing says they left.
    if (seen == null) return true;
    return _now.difference(seen) < presenceTimeout;
  }

  /// Players who closed the app without being caught. They are not shown and
  /// never block the round from resolving.
  List<RoomPlayer> get departed =>
      players.where((p) => !isAtTable(p)).toList();

  /// The loser: whoever was caught earliest. Decided by timestamp rather than
  /// by whichever phone's message reached the server first, so two people
  /// cracking at nearly the same moment still get a stable answer.
  RoomPlayer? get loser {
    final out = players.where((p) => p.isOut).toList()
      ..sort((a, b) => a.caughtAt!.compareTo(b.caughtAt!));
    return out.firstOrNull;
  }

  List<RoomPlayer> get stillIn =>
      players.where((p) => !p.isOut && isAtTable(p)).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Everyone, ordered for the live board: survivors first, then the fallen in
  /// the order they fell.
  List<RoomPlayer> get standings {
    final out = players.where((p) => p.isOut).toList()
      ..sort((a, b) => a.caughtAt!.compareTo(b.caughtAt!));
    return [...stillIn, ...out];
  }

  /// A round is over once at most one player is left standing. Someone who
  /// walked away does not count as standing — before presence existed, one
  /// closed app left a table unable to ever finish.
  bool get isDecided => players.isNotEmpty && stillIn.length <= 1;

  RoomPlayer? playerFor(String deviceId) =>
      players.where((p) => p.deviceId == deviceId).firstOrNull;
}
