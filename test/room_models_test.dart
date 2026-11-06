import 'package:flutter_test/flutter_test.dart';
import 'package:who_pays/features/detector/domain/detector_models.dart';
import 'package:who_pays/features/game/domain/game_models.dart';
import 'package:who_pays/features/room/domain/room_models.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 6, 20);

  const room = Room(
    code: 'ABCD',
    hostId: 'host-device',
    status: RoomStatus.running,
    config: GameConfig(),
  );

  RoomPlayer player(
    String name, {
    required String device,
    int? caughtAfterSeconds,
  }) {
    return RoomPlayer(
      id: 'id-$name',
      deviceId: device,
      name: name,
      joinedAt: t0,
      caughtAt: caughtAfterSeconds == null
          ? null
          : t0.add(Duration(seconds: caughtAfterSeconds)),
      lasted: caughtAfterSeconds == null
          ? null
          : Duration(seconds: caughtAfterSeconds),
      reason: caughtAfterSeconds == null ? null : CatchReason.motion,
    );
  }

  group('loser', () {
    test('is whoever was caught earliest, not whoever reported first', () {
      final snapshot = RoomSnapshot(
        room: room,
        players: [
          // Deliberately out of order: the list order must not decide this.
          player('Priya', device: 'b', caughtAfterSeconds: 90),
          player('Ramesh', device: 'a', caughtAfterSeconds: 40),
          player('Arjun', device: 'c'),
        ],
      );

      expect(snapshot.loser?.name, 'Ramesh');
    });

    test('is null while nobody has cracked', () {
      final snapshot = RoomSnapshot(
        room: room,
        players: [player('Arjun', device: 'c'), player('Priya', device: 'b')],
      );
      expect(snapshot.loser, isNull);
    });
  });

  group('standings', () {
    test('survivors first, then the fallen in the order they fell', () {
      final snapshot = RoomSnapshot(
        room: room,
        players: [
          player('Priya', device: 'b', caughtAfterSeconds: 90),
          player('Ramesh', device: 'a', caughtAfterSeconds: 40),
          player('Arjun', device: 'c'),
        ],
      );

      expect(
        snapshot.standings.map((p) => p.name).toList(),
        ['Arjun', 'Ramesh', 'Priya'],
      );
    });

    test('survivors are sorted by name so the board does not jitter', () {
      final snapshot = RoomSnapshot(
        room: room,
        players: [
          player('zoe', device: 'z'),
          player('Adam', device: 'a'),
        ],
      );
      expect(snapshot.standings.map((p) => p.name).toList(), ['Adam', 'zoe']);
    });
  });

  group('isDecided', () {
    test('false while two or more are still in', () {
      final snapshot = RoomSnapshot(
        room: room,
        players: [
          player('A', device: 'a'),
          player('B', device: 'b'),
          player('C', device: 'c', caughtAfterSeconds: 10),
        ],
      );
      expect(snapshot.isDecided, isFalse);
    });

    test('true once only one is left', () {
      final snapshot = RoomSnapshot(
        room: room,
        players: [
          player('A', device: 'a'),
          player('B', device: 'b', caughtAfterSeconds: 10),
        ],
      );
      expect(snapshot.isDecided, isTrue);
    });

    test('false for an empty table rather than claiming a winner', () {
      const snapshot = RoomSnapshot(room: room, players: []);
      expect(snapshot.isDecided, isFalse);
    });
  });

  group('row parsing', () {
    test('reads a room row, including an open-ended target', () {
      final parsed = Room.fromRow({
        'code': 'WXYZ',
        'host_id': 'host-1',
        'stake': 'dishes',
        'custom_stake': null,
        'target_ms': null,
        'status': 'running',
        'started_at': t0.toIso8601String(),
      });

      expect(parsed.code, 'WXYZ');
      expect(parsed.config.stake, Stake.dishes);
      expect(parsed.config.target, isNull);
      expect(parsed.status, RoomStatus.running);
      expect(parsed.isHost('host-1'), isTrue);
      expect(parsed.isHost('someone-else'), isFalse);
    });

    test('falls back to lobby for an unknown status', () {
      expect(roomStatusFrom('nonsense'), RoomStatus.lobby);
      expect(roomStatusFrom(null), RoomStatus.lobby);
    });

    test('reads a player row that has not been caught', () {
      final parsed = RoomPlayer.fromRow({
        'id': 'p1',
        'device_id': 'd1',
        'name': 'Ramesh',
        'joined_at': t0.toIso8601String(),
        'caught_at': null,
        'lasted_ms': null,
        'catch_reason': null,
      });

      expect(parsed.isOut, isFalse);
      expect(parsed.reason, isNull);
    });

    test('reads a caught player row', () {
      final parsed = RoomPlayer.fromRow({
        'id': 'p1',
        'device_id': 'd1',
        'name': 'Ramesh',
        'joined_at': t0.toIso8601String(),
        'caught_at': t0.add(const Duration(seconds: 30)).toIso8601String(),
        'lasted_ms': 30000,
        'catch_reason': 'leftApp',
      });

      expect(parsed.isOut, isTrue);
      expect(parsed.lasted, const Duration(seconds: 30));
      expect(parsed.reason, CatchReason.leftApp);
    });
  });

  group('playerFor', () {
    test('finds this phone, and returns null for a stranger', () {
      final snapshot = RoomSnapshot(
        room: room,
        players: [player('Ramesh', device: 'a')],
      );
      expect(snapshot.playerFor('a')?.name, 'Ramesh');
      expect(snapshot.playerFor('zzz'), isNull);
    });
  });
}
