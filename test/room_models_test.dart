import 'package:flutter_test/flutter_test.dart';
import 'package:who_pays/features/detector/domain/detector_models.dart';
import 'package:who_pays/features/game/domain/game_models.dart';
import 'package:who_pays/features/room/domain/room_models.dart';

void main() {
  _socketPresenceTests();
  _presenceUnknownTests();
  final t0 = DateTime.utc(2026, 11, 6, 20);

  const room = Room(
    code: 'ABCD',
    hostId: 'host-device',
    status: RoomStatus.running,
    config: GameConfig(),
  );

  /// [quietForSeconds] simulates a phone that has stopped reporting in.
  RoomPlayer player(
    String name, {
    required String device,
    int? caughtAfterSeconds,
    int quietForSeconds = 0,
  }) {
    return RoomPlayer(
      id: 'id-$name',
      deviceId: device,
      name: name,
      joinedAt: t0,
      lastSeen: t0.subtract(Duration(seconds: quietForSeconds)),
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
        now: t0,
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
        now: t0,
        players: [player('Arjun', device: 'c'), player('Priya', device: 'b')],
      );
      expect(snapshot.loser, isNull);
    });
  });

  group('standings', () {
    test('survivors first, then the fallen in the order they fell', () {
      final snapshot = RoomSnapshot(
        room: room,
        now: t0,
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
        now: t0,
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
        now: t0,
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
        now: t0,
        players: [
          player('A', device: 'a'),
          player('B', device: 'b', caughtAfterSeconds: 10),
        ],
      );
      expect(snapshot.isDecided, isTrue);
    });

    test('false for an empty table rather than claiming a winner', () {
      final snapshot = RoomSnapshot(room: room, now: t0, players: const []);
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

  group('presence', () {
    // A player who closed the app left a row that was neither caught nor
    // present, so the round could never resolve and the table was stuck.
    test('a player who stopped reporting is not still in the game', () {
      final snapshot = RoomSnapshot(
        room: room,
        now: t0,
        players: [
          player('Here', device: 'a'),
          player('Gone', device: 'b', quietForSeconds: 120),
        ],
      );

      expect(snapshot.stillIn.map((p) => p.name), ['Here']);
      expect(snapshot.departed.map((p) => p.name), ['Gone']);
    });

    test('a quiet phone no longer blocks the round from resolving', () {
      final snapshot = RoomSnapshot(
        room: room,
        now: t0,
        players: [
          player('Here', device: 'a'),
          player('Gone', device: 'b', quietForSeconds: 120),
        ],
      );
      expect(snapshot.isDecided, isTrue);
    });

    test('a brief gap does not eject anybody', () {
      // Shorter than the timeout: a missed heartbeat on bad wifi.
      final snapshot = RoomSnapshot(
        room: room,
        now: t0,
        players: [
          player('Here', device: 'a'),
          player('Blip', device: 'b', quietForSeconds: 30),
        ],
      );
      expect(snapshot.stillIn.length, 2);
      expect(snapshot.isDecided, isFalse);
    });

    test('a caught player stays on the board however quiet they go', () {
      final snapshot = RoomSnapshot(
        room: room,
        now: t0,
        players: [
          player('Here', device: 'a'),
          player('Caught', device: 'b', caughtAfterSeconds: 10, quietForSeconds: 600),
        ],
      );

      expect(snapshot.departed, isEmpty);
      expect(snapshot.standings.map((p) => p.name), ['Here', 'Caught']);
      expect(snapshot.loser?.name, 'Caught');
    });

    test('everyone leaving does not invent a winner', () {
      final snapshot = RoomSnapshot(
        room: room,
        now: t0,
        players: [
          player('Gone1', device: 'a', quietForSeconds: 120),
          player('Gone2', device: 'b', quietForSeconds: 120),
        ],
      );
      expect(snapshot.stillIn, isEmpty);
      expect(snapshot.loser, isNull);
    });
  });

  group('playerFor', () {
    test('finds this phone, and returns null for a stranger', () {
      final snapshot = RoomSnapshot(
        room: room,
        now: t0,
        players: [player('Ramesh', device: 'a')],
      );
      expect(snapshot.playerFor('a')?.name, 'Ramesh');
      expect(snapshot.playerFor('zzz'), isNull);
    });
  });
}

/// Regression: a database without the presence column must not eject
/// everybody.
///
/// Found by an end-to-end run, not by a unit test — the host's phone kept
/// counting after the round had already been marked finished. `last_seen` fell
/// back to `joined_at`, so 45 seconds after joining every player looked
/// departed, `stillIn` emptied, and the round "resolved" with nobody having
/// been caught.
const _room = Room(
  code: 'ABCD',
  hostId: 'host-device',
  status: RoomStatus.running,
  config: GameConfig(),
);

void _presenceUnknownTests() {
  RoomPlayer player(String name, {required Map<String, dynamic> extra}) =>
      RoomPlayer.fromRow({
        'id': 'id-$name',
        'device_id': 'dev-$name',
        'name': name,
        'joined_at':
            DateTime.now().subtract(const Duration(minutes: 10)).toIso8601String(),
        ...extra,
      });

  group('presence when the column is missing', () {
    test('a player with no last_seen is still at the table', () {
      final snap = RoomSnapshot(
        room: _room,
        players: [player('Asha', extra: {})],
      );
      expect(snap.stillIn, hasLength(1));
      expect(snap.departed, isEmpty);
    });

    test('the round is not decided just because presence is unknown', () {
      final snap = RoomSnapshot(
        room: _room,
        players: [player('Asha', extra: {}), player('Bala', extra: {})],
      );
      expect(snap.isDecided, isFalse,
          reason: 'two live players, nobody caught');
    });

    test('an explicit stale last_seen still counts as departed', () {
      final stale = DateTime.now().subtract(const Duration(minutes: 5));
      final snap = RoomSnapshot(
        room: _room,
        players: [
          player('Asha', extra: {'last_seen': stale.toIso8601String()}),
        ],
      );
      expect(snap.departed, hasLength(1),
          reason: 'presence still works where the column exists');
    });
  });
}

/// Presence from the realtime socket, which works on a database that never
/// had the presence migration applied.
///
/// The danger here is not missing a departure — it is ejecting somebody who
/// is sitting at the table. So `confirmedGone` is only ever set by the
/// session after watching a phone stay off the channel, and an empty set has
/// to mean "nothing known".
void _socketPresenceTests() {
  RoomPlayer p(String name, {String? lastSeen}) => RoomPlayer.fromRow({
        'id': 'id-$name',
        'device_id': 'dev-$name',
        'name': name,
        'joined_at': DateTime.now()
            .subtract(const Duration(minutes: 10))
            .toIso8601String(),
        'last_seen': ?lastSeen,
      });

  group('socket presence', () {
    test('someone confirmed gone stops blocking the round', () {
      final snap = RoomSnapshot(
        room: _room,
        players: [p('Asha'), p('Bala')],
        confirmedGone: {'dev-Bala'},
      );
      expect(snap.stillIn.map((x) => x.name), ['Asha']);
      expect(snap.isDecided, isTrue,
          reason: 'one player left standing, so the round can end');
    });

    test('an empty set means nothing known, not everybody gone', () {
      final snap = RoomSnapshot(
        room: _room,
        players: [p('Asha'), p('Bala')],
      );
      expect(snap.stillIn, hasLength(2));
      expect(snap.isDecided, isFalse);
    });

    test('a caught player stays on the board even once gone', () {
      final caught = RoomPlayer.fromRow({
        'id': 'id-c',
        'device_id': 'dev-c',
        'name': 'Chandra',
        'joined_at': DateTime.now().toIso8601String(),
        'caught_at': DateTime.now().toIso8601String(),
        'lasted_ms': 1000,
        'catch_reason': 'motion',
      });
      final snap = RoomSnapshot(
        room: _room,
        players: [caught],
        confirmedGone: {'dev-c'},
      );
      expect(snap.loser?.name, 'Chandra',
          reason: 'closing the app must not erase a result');
      expect(snap.departed, isEmpty);
    });

    test('the database heartbeat still wins where the column exists', () {
      final stale =
          DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String();
      final snap = RoomSnapshot(
        room: _room,
        players: [p('Asha', lastSeen: stale)],
      );
      expect(snap.departed, hasLength(1));
    });
  });
}
