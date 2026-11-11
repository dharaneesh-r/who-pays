import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:who_pays/features/game/domain/game_models.dart';
import 'package:who_pays/features/room/application/room_session.dart';
import 'package:who_pays/features/room/domain/room_models.dart';
import 'package:who_pays/features/venue/application/venue_session.dart';
import 'package:who_pays/features/venue/data/location_source.dart';
import 'package:who_pays/features/venue/data/venue_repository.dart';
import 'package:who_pays/features/venue/domain/place_provider.dart';
import 'package:who_pays/features/venue/domain/venue_models.dart';

/// Records what the session asked the server to do, and lets a test push rows
/// back as the realtime streams would.
class FakeVenueRepo implements VenueRepo {
  final _candidates = StreamController<List<VenueCandidate>>.broadcast();
  final _votes = StreamController<List<VenueVote>>.broadcast();

  List<Place> published = const [];
  final List<String> approvals = [];
  final List<String> removals = [];
  String? decided;
  bool cleared = false;
  Object? throwOnApproval;

  void dispose() {
    _candidates.close();
    _votes.close();
  }

  void pushCandidates(List<VenueCandidate> rows) => _candidates.add(rows);
  void pushVotes(List<VenueVote> rows) => _votes.add(rows);

  @override
  Future<void> publishCandidates({
    required String code,
    required List<Place> places,
  }) async {
    published = places;
  }

  @override
  Stream<List<VenueCandidate>> watchCandidates(String code) =>
      _candidates.stream;

  @override
  Stream<List<VenueVote>> watchVotes(String code) => _votes.stream;

  @override
  Future<void> setApproval({
    required String code,
    required String venueId,
    required String deviceId,
    required bool approve,
  }) async {
    final e = throwOnApproval;
    if (e != null) throw e;
    (approve ? approvals : removals).add(venueId);
  }

  @override
  Future<void> setDecidedVenue({
    required String code,
    required String? venueId,
  }) async {
    decided = venueId;
  }

  @override
  Future<void> clearBallot(String code) async {
    cleared = true;
  }
}

/// A room session with a state a test controls outright.
class FixedRoomSession extends RoomSession {
  FixedRoomSession(this._initial);
  final RoomSessionState _initial;

  @override
  RoomSessionState build() => _initial;

  void push(RoomSessionState next) => state = next;
}

RoomSnapshot snapshotWith({String? decidedVenueId}) => RoomSnapshot(
      room: Room(
        code: 'ABCD',
        hostId: 'host-device',
        status: RoomStatus.lobby,
        config: const GameConfig(),
        decidedVenueId: decidedVenueId,
      ),
      players: const [],
    );

void main() {
  late FakeVenueRepo repo;
  late ProviderContainer container;

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  /// The id this phone votes with, so a test can replay its own vote coming
  /// back through the stream.
  Future<String> thisDevice() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_id')!;
  }

  VenueSessionState venue() => container.read(venueSessionProvider);
  VenueSession session() => container.read(venueSessionProvider.notifier);

  /// Builds a container. [roomCode] null means nobody is at a table, which is
  /// the solo path.
  void boot({
    RoomSessionState? room,
    PlaceProvider provider = const FakePlaceProvider(),
  }) {
    container = ProviderContainer(overrides: [
      venueRepositoryProvider.overrideWithValue(repo),
      placeProviderProvider.overrideWithValue(provider),
      locationSourceProvider.overrideWithValue(const FixedLocationSource()),
      if (room != null)
        roomSessionProvider.overrideWith(() => FixedRoomSession(room)),
    ]);
    container.listen(venueSessionProvider, (_, _) {});
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    repo = FakeVenueRepo();
  });

  tearDown(() {
    container.dispose();
    repo.dispose();
  });

  group('alone — no table, nothing on the network', () {
    test('search fills the ballot from the provider', () async {
      boot();
      await session().search();

      // Two of the six fakes are inside the 2 km radius (450 m and 1.2 km);
      // the rest sit at 2.6 km and beyond. If this number changes, check
      // searchRadiusM before touching the test.
      expect(venue().candidates, hasLength(2));
      expect(
        venue().candidates.map((c) => c.name),
        isNot(contains('Too Far Cafe')),
      );
      expect(venue().searching, isFalse);
      // Nothing was sent anywhere.
      expect(repo.published, isEmpty);
    });

    test('tapping a place approves it, tapping again takes it back', () async {
      boot();
      await session().search();
      final id = venue().candidates.first.id;

      await session().toggle(id);
      expect(venue().ballot.approvalsFor(id), 1);
      expect(venue().ballot.winner?.id, id);

      await session().toggle(id);
      expect(venue().ballot.approvalsFor(id), 0);
      expect(venue().ballot.winner, isNull);
    });

    test('locking in records the decision and reopening clears it', () async {
      boot();
      await session().search();
      final id = venue().candidates.first.id;

      await session().lockIn(id);
      expect(venue().decidedVenueId, id);
      expect(venue().decided?.id, id);
      // Solo, so the server was never told.
      expect(repo.decided, isNull);

      await session().reopen();
      expect(venue().decidedVenueId, isNull);
    });

    test('an empty result says so instead of showing a blank list', () async {
      boot(provider: const FakePlaceProvider(places: []));
      await session().search();

      expect(venue().candidates, isEmpty);
      expect(venue().error, contains('Nothing found'));
      expect(venue().searching, isFalse);
    });

    test('a lookup failure surfaces its message and stops the spinner',
        () async {
      boot(
        provider: const FakePlaceProvider(
          failure: PlaceLookupFailure('No places found nearby.'),
        ),
      );
      await session().search();

      expect(venue().error, 'No places found nearby.');
      expect(venue().searching, isFalse);
    });

    test('an error can be dismissed', () async {
      boot(provider: const FakePlaceProvider(places: []));
      await session().search();
      expect(venue().error, isNotNull);

      session().dismissError();
      expect(venue().error, isNull);
    });
  });

  group('at a table', () {
    RoomSessionState atTable({String? decidedVenueId}) => RoomSessionState(
          code: 'ABCD',
          deviceId: 'host-device',
          snapshot: snapshotWith(decidedVenueId: decidedVenueId),
        );

    test('search publishes to the server and waits for the stream', () async {
      boot(room: atTable());
      await session().search();

      expect(repo.published, hasLength(2));
      // The host gets the list the same way the guests do — through the
      // stream — so nobody is looking at a different ballot.
      expect(venue().candidates, isEmpty);

      repo.pushCandidates([
        const VenueCandidate(id: 'v1', placeId: 'p1', name: 'Saravana'),
      ]);
      await settle();
      expect(venue().candidates.single.name, 'Saravana');
    });

    test('votes arriving from other phones are counted', () async {
      boot(room: atTable());
      repo.pushCandidates([
        const VenueCandidate(id: 'v1', placeId: 'p1', name: 'A'),
        const VenueCandidate(id: 'v2', placeId: 'p2', name: 'B'),
      ]);
      repo.pushVotes([
        const VenueVote(venueId: 'v2', deviceId: 'guest-1'),
        const VenueVote(venueId: 'v2', deviceId: 'guest-2'),
        const VenueVote(venueId: 'v1', deviceId: 'guest-1'),
      ]);
      await settle();

      expect(venue().ballot.approvalsFor('v2'), 2);
      expect(venue().ballot.winner?.id, 'v2');
      expect(venue().ballot.votersCount, 2);
    });

    test('tapping sends an approval, tapping again sends a removal', () async {
      boot(room: atTable());
      repo.pushCandidates([
        const VenueCandidate(id: 'v1', placeId: 'p1', name: 'A'),
      ]);
      await settle();

      await session().toggle('v1');
      expect(repo.approvals, ['v1']);

      // The server is the source of truth, so the removal only follows once
      // the vote has actually come back through the stream.
      repo.pushVotes([VenueVote(venueId: 'v1', deviceId: await thisDevice())]);
      await settle();

      await session().toggle('v1');
      expect(repo.removals, ['v1']);
    });

    test('a failed vote is reported rather than silently lost', () async {
      boot(room: atTable());
      repo.pushCandidates([
        const VenueCandidate(id: 'v1', placeId: 'p1', name: 'A'),
      ]);
      await settle();
      repo.throwOnApproval = const VenueUnavailable('Not connected.');

      await session().toggle('v1');
      expect(venue().error, 'Not connected.');
    });

    test('locking in tells the server', () async {
      boot(room: atTable());
      await session().lockIn('v1');
      expect(repo.decided, 'v1');
      expect(venue().decidedVenueId, 'v1');

      await session().reopen();
      expect(repo.decided, isNull);
      expect(venue().decidedVenueId, isNull);
    });

    test('a decision made on another phone arrives through the room',
        () async {
      final room = atTable();
      boot(room: room);
      repo.pushCandidates([
        const VenueCandidate(id: 'v9', placeId: 'p9', name: 'Decided Place'),
      ]);
      await settle();
      expect(venue().decidedVenueId, isNull);

      // The host locks it in on their phone; this one hears about it via the
      // room row, not via the ballot.
      final host =
          container.read(roomSessionProvider.notifier) as FixedRoomSession;
      host.push(
        RoomSessionState(
          code: room.code,
          deviceId: room.deviceId,
          snapshot: snapshotWith(decidedVenueId: 'v9'),
        ),
      );
      await settle();

      expect(venue().decidedVenueId, 'v9');
      expect(venue().decided?.name, 'Decided Place');
    });

    test('starting over clears the ballot on the server', () async {
      boot(room: atTable());
      await session().startOver();
      expect(repo.cleared, isTrue);
      expect(repo.published, hasLength(2));
    });
  });
}

