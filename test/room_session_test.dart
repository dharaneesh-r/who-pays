import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:who_pays/core/feedback/alarm_service.dart';
import 'package:who_pays/data/remote/room_repository.dart';
import 'package:who_pays/features/detector/application/detector_service.dart';
import 'package:who_pays/features/detector/domain/detector_models.dart';
import 'package:who_pays/features/game/application/game_controller.dart';
import 'package:who_pays/features/game/domain/game_models.dart';
import 'package:who_pays/features/room/application/room_session.dart';
import 'package:who_pays/features/room/domain/room_models.dart';

import 'game_controller_test.dart' show FakeAlarm, FakeDetector;

/// An in-memory room server. Tests push room and player updates by hand, the
/// way Supabase realtime would.
class FakeRoomRepo implements RoomRepo {
  final rooms = StreamController<Room?>.broadcast();
  final people = StreamController<List<RoomPlayer>>.broadcast();

  final List<RoomStatus> statusWrites = [];
  final List<CatchReason> caughtReports = [];
  int resets = 0;
  int touches = 0;
  int leaves = 0;
  bool exists = true;

  static const code = 'ABCD';
  static const hostId = 'host-device';

  Room room(RoomStatus status, {String host = hostId}) => Room(
        code: code,
        hostId: host,
        status: status,
        config: const GameConfig(),
      );

  @override
  Future<Room> createRoom({
    required String deviceId,
    required String name,
    required GameConfig config,
  }) async =>
      room(RoomStatus.lobby, host: deviceId);

  @override
  Future<Room> joinRoom({
    required String code,
    required String deviceId,
    required String name,
  }) async =>
      room(RoomStatus.lobby);

  @override
  Stream<Room?> watchRoom(String code) => rooms.stream;

  @override
  Stream<List<RoomPlayer>> watchPlayers(String code) => people.stream;

  /// Device ids "connected" to the realtime channel. Tests push sets into it
  /// to simulate somebody closing their app.
  final presence = StreamController<Set<String>>.broadcast();

  @override
  Stream<Set<String>> watchPresence({
    required String code,
    required String deviceId,
  }) =>
      presence.stream;

  @override
  Future<void> touch({required String code, required String deviceId}) async =>
      touches++;

  @override
  Future<bool> roomExists(String code) async => exists;

  @override
  Future<void> setStatus(String code, RoomStatus status) async =>
      statusWrites.add(status);

  @override
  Future<void> resetRound(String code) async => resets++;

  @override
  Future<void> reportCaught({
    required String code,
    required String deviceId,
    required Duration lasted,
    required CatchReason reason,
  }) async =>
      caughtReports.add(reason);

  @override
  Future<void> leaveRoom({
    required String code,
    required String deviceId,
  }) async =>
      leaves++;

  void dispose() {
    presence.close();
    rooms.close();
    people.close();
  }
}

void main() {
  late FakeRoomRepo repo;
  late FakeDetector detector;
  late ProviderContainer container;

  RoomPlayer person(
    String name, {
    required String device,
    int? caughtAfterSeconds,
  }) {
    final now = DateTime.now();
    return RoomPlayer(
      id: 'id-$name',
      deviceId: device,
      name: name,
      joinedAt: now,
      lastSeen: now,
      caughtAt: caughtAfterSeconds == null
          ? null
          : now.add(Duration(seconds: caughtAfterSeconds)),
      lasted: caughtAfterSeconds == null
          ? null
          : Duration(seconds: caughtAfterSeconds),
    );
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    repo = FakeRoomRepo();
    detector = FakeDetector();
    container = ProviderContainer(overrides: [
      roomRepositoryProvider.overrideWithValue(repo),
      detectorServiceProvider.overrideWithValue(detector),
      alarmServiceProvider.overrideWithValue(FakeAlarm()),
    ]);
    container.listen(roomSessionProvider, (_, _) {});
    container.listen(gameControllerProvider, (_, _) {});
  });

  tearDown(() {
    container.dispose();
    repo.dispose();
  });

  RoomSessionState session() => container.read(roomSessionProvider);
  RoomSession controller() => container.read(roomSessionProvider.notifier);
  GameState game() => container.read(gameControllerProvider);

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 30));

  Future<void> joinAsGuest() async {
    await controller().join(FakeRoomRepo.code);
    await settle();
  }

  Future<void> hostTable() async {
    await controller().host(const GameConfig());
    await settle();
  }

  group('joining', () {
    test('a four-letter code is required', () async {
      await controller().join('AB');
      expect(session().inRoom, isFalse);
      expect(session().error, isNotNull);
    });

    test('joining attaches to the table and remembers it', () async {
      await joinAsGuest();

      expect(session().inRoom, isTrue);
      expect(session().code, FakeRoomRepo.code);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_room_code'), FakeRoomRepo.code,
          reason: 'a killed app must be able to offer a rejoin');
    });

    test('leaving clears the table and forgets it', () async {
      await joinAsGuest();
      await controller().leave();
      await settle();

      expect(session().inRoom, isFalse);
      expect(repo.leaves, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('last_room_code'), isNull,
          reason: 'leaving on purpose should not then offer a rejoin');
    });

    test('the host closing the table ends the session', () async {
      await joinAsGuest();
      repo.rooms.add(null); // the room row disappeared
      await settle();

      expect(session().inRoom, isFalse);
      expect(session().error, isNotNull);
    });
  });

  group('following the host', () {
    test('settling starts the round on this phone', () async {
      await joinAsGuest();
      expect(game().phase, RoundPhase.setup);

      repo.rooms.add(repo.room(RoomStatus.settling));
      await settle();

      expect(game().phase, RoundPhase.settling);
      expect(detector.startCount, 1);
    });

    test('a finished round is not restarted by the same status', () async {
      // The room stays in `settling` for the whole round. Restarting from
      // `finished` meant the result screen was never seen.
      await joinAsGuest();
      repo.rooms.add(repo.room(RoomStatus.settling));
      await settle();

      detector.emit(DetectorState.armed);
      await settle();
      detector.emit(DetectorState.caught, reason: CatchReason.motion);
      await settle();
      expect(game().phase, RoundPhase.finished);

      repo.rooms.add(repo.room(RoomStatus.settling));
      await settle();

      expect(game().phase, RoundPhase.finished,
          reason: 'the round must not restart itself');
      expect(detector.startCount, 1);
    });

    test('lobby sends everyone back to setup', () async {
      await joinAsGuest();
      repo.rooms.add(repo.room(RoomStatus.settling));
      await settle();
      expect(game().phase, RoundPhase.settling);

      repo.rooms.add(repo.room(RoomStatus.lobby));
      await settle();

      expect(game().phase, RoundPhase.setup);
    });
  });

  group('reporting a catch', () {
    test('a catch is reported to the table exactly once', () async {
      await joinAsGuest();
      repo.rooms.add(repo.room(RoomStatus.settling));
      await settle();
      detector.emit(DetectorState.armed);
      await settle();

      detector.emit(DetectorState.caught, reason: CatchReason.leftApp);
      await settle();
      // The detector keeps emitting afterwards.
      detector.emit(DetectorState.caught, reason: CatchReason.leftApp);
      await settle();

      expect(repo.caughtReports, [CatchReason.leftApp]);
    });

    test('surviving the round reports nothing', () async {
      await joinAsGuest();
      repo.rooms.add(repo.room(RoomStatus.settling));
      await settle();
      detector.emit(DetectorState.armed);
      await settle();

      expect(repo.caughtReports, isEmpty);
    });
  });

  group('host duties', () {
    test('only the host closes a decided round', () async {
      // Joined as a guest, so this phone is not the host.
      await joinAsGuest();
      repo.rooms.add(repo.room(RoomStatus.settling));
      repo.people.add([
        person('Winner', device: 'x'),
        person('Loser', device: 'y', caughtAfterSeconds: 10),
      ]);
      await settle();

      expect(repo.statusWrites, isNot(contains(RoomStatus.finished)),
          reason: 'a guest must never close the round for everyone');
    });

    test('the host closes the round once one player is left', () async {
      await hostTable();
      final hostId = session().deviceId!;

      repo.rooms.add(repo.room(RoomStatus.settling, host: hostId));
      repo.people.add([
        person('Winner', device: hostId),
        person('Loser', device: 'y', caughtAfterSeconds: 10),
      ]);
      await settle();

      expect(repo.statusWrites, contains(RoomStatus.finished));
    });

    test('startRound clears the previous results first', () async {
      await hostTable();
      final hostId = session().deviceId!;
      repo.rooms.add(repo.room(RoomStatus.lobby, host: hostId));
      await settle();

      repo.statusWrites.clear();
      await controller().startRound();
      await settle();

      expect(repo.resets, greaterThan(0),
          reason: 'old catches must not carry into the new round');
      expect(repo.statusWrites, contains(RoomStatus.settling));
    });

    test('a guest cannot start a round', () async {
      await joinAsGuest();
      repo.rooms.add(repo.room(RoomStatus.lobby));
      await settle();

      repo.statusWrites.clear();
      await controller().startRound();
      await settle();

      expect(repo.statusWrites, isEmpty);
    });
  });

  group('errors', () {
    test('an error can be dismissed', () async {
      await controller().join('XX');
      expect(session().error, isNotNull);

      controller().dismissError();
      expect(session().error, isNull);
    });
  });

  /// Regression: when the round closes, every phone has to stop.
  ///
  /// Found by an end-to-end run, not by these tests. The room reached
  /// `finished`, the player who cracked saw their result, and every other
  /// phone kept counting — the "why is my timer still running?" bug.
  /// `RoomStatus.finished` was a no-op in the status handler, so nothing ever
  /// told the local game the round was over.
  group('a finished room ends the local round', () {
    Future<void> roundInProgress() async {
      await joinAsGuest();
      repo.rooms.add(repo.room(RoomStatus.settling));
      await settle();
      detector.emit(DetectorState.armed);
      await settle();
    }

    test('a phone still counting is told the round is over', () async {
      await roundInProgress();
      expect(game().phase, RoundPhase.running,
          reason: 'precondition: this phone is mid-round');

      repo.rooms.add(repo.room(RoomStatus.finished));
      await settle();

      expect(game().phase, RoundPhase.finished);
      expect(game().result?.outcome, RoundOutcome.survived,
          reason: 'this phone was never caught — someone else cracked');
    });

    test('a phone already caught keeps its own result', () async {
      await roundInProgress();
      detector.trigger(CatchReason.motion);
      await settle();
      final caughtFor = game().result?.lasted;
      expect(game().result?.outcome, RoundOutcome.caught);

      repo.rooms.add(repo.room(RoomStatus.finished));
      await settle();

      expect(game().result?.outcome, RoundOutcome.caught,
          reason: 'closing the round must not rewrite who lost');
      expect(game().result?.lasted, caughtFor);
    });

    test('a phone back at setup is left alone', () async {
      await joinAsGuest();
      repo.rooms.add(repo.room(RoomStatus.finished));
      await settle();

      expect(game().phase, RoundPhase.setup,
          reason: 'nothing was running, so there is nothing to end');
    });
  });

  /// Realtime presence, which is the only way to notice someone leaving on a
  /// database without the presence column.
  ///
  /// The guard matters more than the feature: if this phone cannot see itself
  /// on the channel, the socket is down and the empty set must not be read as
  /// "everybody left".
  group('socket presence', () {
    setUp(() => RoomSession.offlineGrace = Duration.zero);
    tearDown(() => RoomSession.offlineGrace = const Duration(seconds: 30));

    Future<void> twoAtTheTable() async {
      await joinAsGuest();
      expect(session().deviceId, isNotNull,
          reason: 'precondition: the session knows which phone it is');
      repo.rooms.add(repo.room(RoomStatus.lobby));
      repo.people.add([
        person('Me', device: session().deviceId!),
        person('Other', device: 'other-device'),
      ]);
      await settle();
    }

    test('a phone that drops off the channel stops blocking the round',
        () async {
      await twoAtTheTable();
      repo.presence.add({session().deviceId!, 'other-device'});
      await settle();
      expect(session().snapshot!.stillIn, hasLength(2));

      repo.presence.add({session().deviceId!}); // they closed the app
      await settle();

      expect(session().snapshot!.stillIn.map((p) => p.name), ['Me']);
      expect(session().snapshot!.isDecided, isTrue);
    });

    test('a dead socket does not eject the whole table', () async {
      await twoAtTheTable();
      repo.presence.add({session().deviceId!, 'other-device'});
      await settle();

      repo.presence.add(const {}); // cannot even see ourselves
      await settle();

      expect(session().snapshot!.stillIn, hasLength(2),
          reason: 'no information is not the same as everybody leaving');
      expect(session().snapshot!.isDecided, isFalse);
    });

    test('someone who comes back is not still counted as gone', () async {
      await twoAtTheTable();
      repo.presence.add({session().deviceId!, 'other-device'});
      await settle();
      repo.presence.add({session().deviceId!});
      await settle();
      expect(session().snapshot!.stillIn, hasLength(1));

      repo.presence.add({session().deviceId!, 'other-device'}); // reconnected
      await settle();

      expect(session().snapshot!.stillIn, hasLength(2));
    });
  });
}
