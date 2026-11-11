import 'package:flutter_test/flutter_test.dart';
import 'package:who_pays/features/venue/domain/place_provider.dart';
import 'package:who_pays/features/venue/domain/venue_models.dart';

void main() {
  VenueCandidate v(String id, {int? distance, String? name}) => VenueCandidate(
        id: id,
        placeId: 'place-$id',
        name: name ?? 'Venue $id',
        distanceM: distance,
      );

  VenueVote vote(String venueId, String device) =>
      VenueVote(venueId: venueId, deviceId: device);

  group('tally', () {
    test('counts one approval per device', () {
      final ballot = VenueBallot(
        candidates: [v('a'), v('b')],
        votes: [vote('a', 'phone1'), vote('a', 'phone2'), vote('b', 'phone1')],
      );

      expect(ballot.approvalsFor('a'), 2);
      expect(ballot.approvalsFor('b'), 1);
    });

    test('one device cannot stuff the ballot for its favourite', () {
      final ballot = VenueBallot(
        candidates: [v('a')],
        votes: [vote('a', 'phone1'), vote('a', 'phone1'), vote('a', 'phone1')],
      );
      expect(ballot.approvalsFor('a'), 1);
    });

    test('a device may approve several places — that is the point', () {
      final ballot = VenueBallot(
        candidates: [v('a'), v('b'), v('c')],
        votes: [vote('a', 'phone1'), vote('b', 'phone1')],
      );

      expect(ballot.approvalsBy('phone1'), {'a', 'b'});
      expect(ballot.isApprovedBy('a', 'phone1'), isTrue);
      expect(ballot.isApprovedBy('c', 'phone1'), isFalse);
      // One person voting for two places is still one voter.
      expect(ballot.votersCount, 1);
    });

    test('counts voters, not votes', () {
      final ballot = VenueBallot(
        candidates: [v('a'), v('b')],
        votes: [vote('a', 'p1'), vote('b', 'p1'), vote('a', 'p2')],
      );
      expect(ballot.votersCount, 2);
    });
  });

  group('winner', () {
    test('is the most approved', () {
      final ballot = VenueBallot(
        candidates: [v('a'), v('b')],
        votes: [vote('b', 'p1'), vote('b', 'p2'), vote('a', 'p1')],
      );
      expect(ballot.winner?.id, 'b');
    });

    test('is null while nobody has voted — never a silent default', () {
      final ballot = VenueBallot(candidates: [v('a'), v('b')], votes: const []);
      expect(ballot.winner, isNull);
      expect(ballot.hasAnyVote, isFalse);
    });

    test('is null with no candidates', () {
      expect(const VenueBallot.empty().winner, isNull);
    });

    test('breaks a tie by distance, so the table walks less', () {
      final ballot = VenueBallot(
        candidates: [v('far', distance: 4000), v('near', distance: 300)],
        votes: [vote('far', 'p1'), vote('near', 'p2')],
      );
      expect(ballot.winner?.id, 'near');
    });

    test('an unknown distance loses a tie to a known one', () {
      final ballot = VenueBallot(
        candidates: [v('unknown'), v('known', distance: 4500)],
        votes: [vote('unknown', 'p1'), vote('known', 'p2')],
      );
      expect(ballot.winner?.id, 'known');
    });

    test('is identical on every phone regardless of row order', () {
      // The same rows, shuffled, as two phones would receive them.
      final one = VenueBallot(
        candidates: [
          v('a', distance: 100, name: 'Same'),
          v('b', distance: 100, name: 'Same'),
        ],
        votes: [vote('a', 'p1'), vote('b', 'p2')],
      );
      final two = VenueBallot(
        candidates: [
          v('b', distance: 100, name: 'Same'),
          v('a', distance: 100, name: 'Same'),
        ],
        votes: [vote('b', 'p2'), vote('a', 'p1')],
      );

      // Equal approvals, equal distance, equal name: the id decides, and both
      // phones must agree. Two phones showing different restaurants to the
      // same table is the failure this guards against.
      expect(one.winner?.id, two.winner?.id);
      expect(one.ranked.map((c) => c.id), two.ranked.map((c) => c.id));
    });
  });

  group('trailing — "the least selected will be removed"', () {
    test('is empty before anyone votes', () {
      final ballot = VenueBallot(candidates: [v('a'), v('b')], votes: const []);
      expect(ballot.trailing, isEmpty);
    });

    test('is empty while every candidate is level', () {
      // Dimming the whole ballot the moment one person votes would be absurd.
      final ballot = VenueBallot(
        candidates: [v('a'), v('b')],
        votes: [vote('a', 'p1'), vote('b', 'p1')],
      );
      expect(ballot.trailing, isEmpty);
    });

    test('marks the joint-lowest once there is a spread', () {
      final ballot = VenueBallot(
        candidates: [v('a'), v('b'), v('c')],
        votes: [vote('a', 'p1'), vote('a', 'p2'), vote('b', 'p1')],
      );
      // 'c' has none, 'b' has one, 'a' has two.
      expect(ballot.trailing, {'c'});
    });

    test('marks several when they are jointly last', () {
      final ballot = VenueBallot(
        candidates: [v('a'), v('b'), v('c')],
        votes: [vote('a', 'p1')],
      );
      expect(ballot.trailing, {'b', 'c'});
    });

    test('never marks the only candidate', () {
      final ballot = VenueBallot(
        candidates: [v('a')],
        votes: [vote('a', 'p1')],
      );
      expect(ballot.trailing, isEmpty);
    });
  });

  group('fromRow', () {
    test('reads a row as PostgREST delivers it', () {
      final c = VenueCandidate.fromRow({
        'id': 'row-1',
        'place_id': 'ChIJ_abc',
        'name': 'Murugan Idli Shop',
        'address': 'Besant Nagar',
        'lat': 13.0,
        'lng': 80.2,
        'distance_m': 1200,
        'rating': 4.5,
      });

      expect(c.name, 'Murugan Idli Shop');
      expect(c.distanceM, 1200);
      expect(c.rating, 4.5);
    });

    test('reads a numeric rating sent as a string', () {
      // Postgres `numeric` arrives as a String often enough that discovering
      // it on a device would be the wrong place to find out.
      final c = VenueCandidate.fromRow({
        'id': 'row-1',
        'place_id': 'p',
        'name': 'X',
        'rating': '4.2',
      });
      expect(c.rating, 4.2);
    });

    test('survives the nulls a provider really sends', () {
      final c = VenueCandidate.fromRow({
        'id': 'row-1',
        'place_id': 'p',
        'name': 'No Rating Cafe',
        'address': null,
        'lat': null,
        'lng': null,
        'distance_m': null,
        'rating': null,
      });

      expect(c.rating, isNull);
      expect(c.distanceM, isNull);
      expect(c.address, isNull);
    });
  });

  group('distanceMetres', () {
    test('is zero for the same point', () {
      expect(
        distanceMetres(
          fromLat: 13.0827,
          fromLng: 80.2707,
          toLat: 13.0827,
          toLng: 80.2707,
        ),
        0,
      );
    });

    test('matches a known city distance within a percent', () {
      // Chennai Central to Marina Beach, about 2.9 km.
      final d = distanceMetres(
        fromLat: 13.0827,
        fromLng: 80.2707,
        toLat: 13.0500,
        toLng: 80.2824,
      );
      expect(d, greaterThan(3400));
      expect(d, lessThan(3900));
    });
  });

  group('FakePlaceProvider', () {
    test('honours the radius', () async {
      const provider = FakePlaceProvider();
      final places = await provider.nearby(lat: 13, lng: 80, radiusM: 5000);

      expect(places, isNotEmpty);
      expect(places.every((p) => (p.distanceM ?? 0) <= 5000), isTrue);
      expect(places.any((p) => p.name == 'Too Far Cafe'), isFalse);
    });

    test('honours the limit, because a 5 km ballot is not a ballot', () async {
      const provider = FakePlaceProvider();
      final places = await provider.nearby(lat: 13, lng: 80, limit: 2);
      expect(places, hasLength(2));
    });

    test('can be made to fail so error handling is exercised', () async {
      const provider = FakePlaceProvider(
        failure: PlaceLookupFailure('No places found nearby.'),
      );
      expect(
        () => provider.nearby(lat: 13, lng: 80),
        throwsA(isA<PlaceLookupFailure>()),
      );
    });
  });
}
