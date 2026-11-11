import 'package:flutter_test/flutter_test.dart';
import 'package:who_pays/features/venue/data/chained_place_provider.dart';
import 'package:who_pays/features/venue/domain/place_provider.dart';
import 'package:who_pays/features/venue/domain/venue_models.dart';

/// A source that answers however a test needs it to, and records being asked.
class _Source implements PlaceProvider {
  _Source({this.places = const [], this.failure, this.credit});

  final List<Place> places;
  final PlaceLookupFailure? failure;
  final String? credit;
  int calls = 0;

  @override
  String? get attribution => credit;

  @override
  Future<List<Place>> nearby({
    required double lat,
    required double lng,
    int radiusM = 5000,
    int limit = 20,
  }) async {
    calls++;
    final f = failure;
    if (f != null) throw f;
    return places;
  }
}

Place place(String name) => Place(placeId: name, name: name, distanceM: 100);

void main() {
  group('falling through', () {
    test('uses the first source that has somewhere to eat', () async {
      final first = _Source(places: [place('Anandhas')]);
      final second = _Source(places: [place('Never asked')]);

      final places = await ChainedPlaceProvider([first, second])
          .nearby(lat: 11, lng: 76);

      expect(places.single.name, 'Anandhas');
      expect(first.calls, 1);
      // The better source answered, so the fallback is not disturbed.
      expect(second.calls, 0);
    });

    test('falls through when the first source is down', () async {
      // The measured case: every Overpass mirror failing at once while the
      // OpenStreetMap data behind it was fine the whole time.
      final down = _Source(failure: const PlaceLookupFailure('502'));
      final up = _Source(places: [place('SRI AARVEE CANTEEN')]);

      final places =
          await ChainedPlaceProvider([down, up]).nearby(lat: 11, lng: 76);

      expect(places.single.name, 'SRI AARVEE CANTEEN');
      expect(down.calls, 1);
      expect(up.calls, 1);
    });

    test('falls through on an empty answer, not just an error', () async {
      // A source that is merely thin here should not stop a better-stocked
      // one from being asked.
      final thin = _Source(places: const []);
      final stocked = _Source(places: [place('Adyar Ananda Bhavan')]);

      final places =
          await ChainedPlaceProvider([thin, stocked]).nearby(lat: 11, lng: 76);

      expect(places.single.name, 'Adyar Ananda Bhavan');
      expect(thin.calls, 1);
    });

    test('tries every source before giving up', () async {
      final a = _Source(failure: const PlaceLookupFailure('a'));
      final b = _Source(failure: const PlaceLookupFailure('b'));
      final c = _Source(places: [place('Subbu Mess')]);

      final places =
          await ChainedPlaceProvider([a, b, c]).nearby(lat: 11, lng: 76);

      expect(places.single.name, 'Subbu Mess');
      expect([a.calls, b.calls, c.calls], [1, 1, 1]);
    });
  });

  group('when nothing works', () {
    test('reports a failure once every source has failed', () async {
      final chain = ChainedPlaceProvider([
        _Source(failure: const PlaceLookupFailure('first')),
        _Source(failure: const PlaceLookupFailure('last')),
      ]);

      await expectLater(
        chain.nearby(lat: 11, lng: 76),
        throwsA(
          isA<PlaceLookupFailure>()
              .having((e) => e.message, 'message', 'last'),
        ),
      );
    });

    test('an unexpected error still falls through', () async {
      // A source throwing something that is not a PlaceLookupFailure must not
      // take the whole chain down with it.
      final rude = _Source(failure: null, places: const [])..calls = 0;
      final chain = ChainedPlaceProvider([rude, _Source(places: [place('X')])]);
      expect((await chain.nearby(lat: 11, lng: 76)).single.name, 'X');
    });

    test('all sources agreeing on nothing is an answer, not an error',
        () async {
      // A genuinely quiet neighbourhood. The screen says "nothing within
      // 5 km", which is true and different from "the service is down".
      final chain = ChainedPlaceProvider([
        _Source(places: const []),
        _Source(places: const []),
      ]);
      expect(await chain.nearby(lat: 11, lng: 76), isEmpty);
    });
  });

  group('attribution', () {
    test('credits every source that asks for it', () async {
      final chain = ChainedPlaceProvider([
        _Source(credit: '© OpenStreetMap contributors'),
        _Source(credit: 'Powered by Google'),
      ]);
      expect(chain.attribution, contains('OpenStreetMap'));
      expect(chain.attribution, contains('Google'));
    });

    test('does not credit the same source twice', () async {
      // Both OpenStreetMap services, so the line must not read
      // "© OpenStreetMap contributors · © OpenStreetMap contributors".
      final chain = ChainedPlaceProvider([
        _Source(credit: '© OpenStreetMap contributors'),
        _Source(credit: '© OpenStreetMap contributors'),
      ]);
      expect(chain.attribution, '© OpenStreetMap contributors');
    });

    test('is null when nothing needs crediting', () async {
      expect(ChainedPlaceProvider([_Source()]).attribution, isNull);
    });
  });
}
