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
  });

  final String code;
  final String hostId;
  final RoomStatus status;
  final GameConfig config;
  final DateTime? startedAt;

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
    );
  }
}

class RoomPlayer {
  const RoomPlayer({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.joinedAt,
    this.caughtAt,
    this.lasted,
    this.reason,
  });

  final String id;
  final String deviceId;
  final String name;
  final DateTime joinedAt;

  /// Null while still in the game.
  final DateTime? caughtAt;
  final Duration? lasted;
  final CatchReason? reason;

  bool get isOut => caughtAt != null;

  factory RoomPlayer.fromRow(Map<String, dynamic> row) {
    final lastedMs = row['lasted_ms'] as int?;
    final reasonName = row['catch_reason'] as String?;

    return RoomPlayer(
      id: row['id'] as String,
      deviceId: row['device_id'] as String,
      name: row['name'] as String,
      joinedAt: DateTime.tryParse(row['joined_at'] as String? ?? '') ??
          DateTime.now(),
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
  const RoomSnapshot({required this.room, required this.players});

  final Room room;
  final List<RoomPlayer> players;

  /// The loser: whoever was caught earliest. Decided by timestamp rather than
  /// by whichever phone's message reached the server first, so two people
  /// cracking at nearly the same moment still get a stable answer.
  RoomPlayer? get loser {
    final out = players.where((p) => p.isOut).toList()
      ..sort((a, b) => a.caughtAt!.compareTo(b.caughtAt!));
    return out.firstOrNull;
  }

  List<RoomPlayer> get stillIn =>
      players.where((p) => !p.isOut).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Everyone, ordered for the live board: survivors first, then the fallen in
  /// the order they fell.
  List<RoomPlayer> get standings {
    final out = players.where((p) => p.isOut).toList()
      ..sort((a, b) => a.caughtAt!.compareTo(b.caughtAt!));
    return [...stillIn, ...out];
  }

  /// A round is over once at most one player is left standing.
  bool get isDecided => players.isNotEmpty && stillIn.length <= 1;

  RoomPlayer? playerFor(String deviceId) =>
      players.where((p) => p.deviceId == deviceId).firstOrNull;
}
