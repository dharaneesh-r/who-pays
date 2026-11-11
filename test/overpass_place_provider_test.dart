import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:who_pays/features/venue/data/overpass_place_provider.dart';
import 'package:who_pays/features/venue/domain/place_provider.dart';

/// Coimbatore town hall — the case that prompted this provider.
const fromLat = 11.0021;
const fromLng = 76.9661;

Map<String, dynamic> node({
  int id = 1,
  String? name = 'Annapoorna',
  double lat = 11.0030,
  double lng = 76.9670,
  Map<String, String> extraTags = const {},
}) {
  return {
    'type': 'node',
    'id': id,
    'lat': lat,
    'lon': lng,
    'tags': <String, String>{
      'amenity': 'restaurant',
      // ?name omits the key entirely when null, which is how Overpass
      // actually replies for an unnamed place.
      'name': ?name,
      ...extraTags,
    },
  };
}

void main() {
  ({OverpassPlaceProvider provider, List<http.Request> sent}) harness({
    int status = 200,
    Object? body,
    bool throwNetwork = false,
  }) {
    final sent = <http.Request>[];
    final client = MockClient((request) async {
      sent.add(request);
      if (throwNetwork) throw http.ClientException('no route to host');
      return http.Response(
        body is String ? body : jsonEncode(body ?? {'elements': <dynamic>[]}),
        status,
        headers: {'content-type': 'application/json'},
      );
    });
    return (
      // One endpoint in tests, so a single canned reply is not retried
      // against two more mirrors.
      provider: OverpassPlaceProvider(
        client: client,
        endpoints: [Uri.parse('https://overpass.test/api/interpreter')],
      ),
      sent: sent,
    );
  }

  group('the query', () {
    test('asks for eateries around the given point', () async {
      final h = harness();
      await h.provider.nearby(lat: fromLat, lng: fromLng, radiusM: 5000);

      final body = Uri.splitQueryString(h.sent.single.body)['data']!;
      expect(body, contains('around:5000,$fromLat,$fromLng'));
      expect(body, contains('restaurant'));
      // "Hotel" means an eatery in Indian English, so cafes and fast food
      // belong on the ballot too.
      expect(body, contains('cafe'));
      expect(body, contains('fast_food'));
      // Ways carry a computed centre, so a restaurant mapped as a building
      // is not silently dropped.
      expect(body, contains('out center'));
    });

    test('identifies itself without identifying the user', () async {
      final h = harness();
      await h.provider.nearby(lat: fromLat, lng: fromLng);
      final agent = h.sent.single.headers['user-agent'] ?? '';
      expect(agent, contains('WhoPays'));
      expect(agent, isNot(contains('@')));
    });

    test('clamps an absurd radius', () async {
      final h = harness();
      await h.provider.nearby(lat: fromLat, lng: fromLng, radiusM: 900000);
      final body = Uri.splitQueryString(h.sent.single.body)['data']!;
      expect(body, contains('around:50000,'));
    });
  });

  group('parsing', () {
    test('reads a node and computes its distance', () async {
      final h = harness(body: {'elements': [node()]});
      final places = await h.provider.nearby(lat: fromLat, lng: fromLng);

      final p = places.single;
      expect(p.placeId, 'osm:node/1');
      expect(p.name, 'Annapoorna');
      // About 130 m away.
      expect(p.distanceM, greaterThan(50));
      expect(p.distanceM, lessThan(300));
      // OpenStreetMap has no ratings; the ballot omits the star.
      expect(p.rating, isNull);
    });

    test('reads a way via its centre', () async {
      final h = harness(body: {
        'elements': [
          {
            'type': 'way',
            'id': 42,
            'center': {'lat': 11.0040, 'lon': 76.9680},
            'tags': {'amenity': 'restaurant', 'name': 'Sree Annapoorna'},
          },
        ],
      });
      final places = await h.provider.nearby(lat: fromLat, lng: fromLng);
      expect(places.single.placeId, 'osm:way/42');
      expect(places.single.distanceM, isNotNull);
    });

    test('skips anything unnamed — it cannot be voted for', () async {
      final h = harness(body: {
        'elements': [
          node(id: 1, name: 'Hotel Junior Kuppanna'),
          node(id: 2, name: null),
          node(id: 3, name: '   '),
        ],
      });
      final places = await h.provider.nearby(lat: fromLat, lng: fromLng);
      expect(places.map((p) => p.name), ['Hotel Junior Kuppanna']);
    });

    test('skips an element with no coordinates', () async {
      final h = harness(body: {
        'elements': [
          {'type': 'way', 'id': 7, 'tags': {'name': 'No Centre'}},
        ],
      });
      expect(await h.provider.nearby(lat: fromLat, lng: fromLng), isEmpty);
    });

    test('orders by distance, nearest first', () async {
      final h = harness(body: {
        'elements': [
          node(id: 1, name: 'Far', lat: 11.0300, lng: 76.9900),
          node(id: 2, name: 'Near', lat: 11.0023, lng: 76.9663),
          node(id: 3, name: 'Middle', lat: 11.0100, lng: 76.9700),
        ],
      });
      final places = await h.provider.nearby(lat: fromLat, lng: fromLng);
      expect(places.map((p) => p.name), ['Near', 'Middle', 'Far']);
    });

    test('deduplicates a venue mapped as both a node and a building', () async {
      // Very common in OpenStreetMap, and a ballot listing the same
      // restaurant twice looks broken.
      final h = harness(body: {
        'elements': [
          node(id: 1, name: 'Annapoorna'),
          {
            'type': 'way',
            'id': 2,
            'center': {'lat': 11.0031, 'lon': 76.9671},
            'tags': {'amenity': 'restaurant', 'name': 'annapoorna'},
          },
        ],
      });
      final places = await h.provider.nearby(lat: fromLat, lng: fromLng);
      expect(places, hasLength(1));
    });

    test('honours the limit', () async {
      final h = harness(body: {
        'elements': [
          for (var i = 0; i < 30; i++)
            node(id: i, name: 'Place $i', lat: 11.0 + i / 10000),
        ],
      });
      final places =
          await h.provider.nearby(lat: fromLat, lng: fromLng, limit: 5);
      expect(places, hasLength(5));
    });

    test('an empty area returns nothing rather than throwing', () async {
      // A real outcome in a small town, and the screen has a message for it.
      final h = harness(body: {'elements': <dynamic>[]});
      expect(await h.provider.nearby(lat: fromLat, lng: fromLng), isEmpty);
    });
  });

  group('address', () {
    test('reads house number and street', () async {
      final h = harness(body: {
        'elements': [
          node(extraTags: {
            'addr:housenumber': '47',
            'addr:street': 'Mettupalayam Road',
          }),
        ],
      });
      final places = await h.provider.nearby(lat: fromLat, lng: fromLng);
      expect(places.single.address, '47 Mettupalayam Road');
    });

    test('falls back to the area', () async {
      final h = harness(body: {
        'elements': [
          node(extraTags: {'addr:suburb': 'R.S. Puram'}),
        ],
      });
      expect(
        (await h.provider.nearby(lat: fromLat, lng: fromLng)).single.address,
        'R.S. Puram',
      );
    });

    test('uses the city only when nothing finer is known', () async {
      final h = harness(body: {
        'elements': [
          node(extraTags: {'addr:city': 'Coimbatore'}),
        ],
      });
      expect(
        (await h.provider.nearby(lat: fromLat, lng: fromLng)).single.address,
        'Coimbatore',
      );
    });

    test('is null when OpenStreetMap has nothing — which is common', () async {
      final h = harness(body: {'elements': [node()]});
      expect(
        (await h.provider.nearby(lat: fromLat, lng: fromLng)).single.address,
        isNull,
      );
    });
  });

  group('failure', () {
    test('a busy public instance reads as advice', () async {
      // Overpass sheds load with 429 and 504; a status code helps nobody at
      // a dinner table.
      for (final status in [429, 504]) {
        final h = harness(status: status);
        await expectLater(
          h.provider.nearby(lat: fromLat, lng: fromLng),
          throwsA(
            isA<PlaceLookupFailure>()
                .having((e) => e.message, 'message', contains('busy')),
          ),
        );
      }
    });

    test('a network failure reads as advice, not a stack trace', () async {
      final h = harness(throwNetwork: true);
      await expectLater(
        h.provider.nearby(lat: fromLat, lng: fromLng),
        throwsA(
          isA<PlaceLookupFailure>()
              .having((e) => e.message, 'message', contains('connection')),
        ),
      );
    });

    test('a captive portal page does not crash the screen', () async {
      final h = harness(body: '<html>Sign in to WiFi</html>');
      await expectLater(
        h.provider.nearby(lat: fromLat, lng: fromLng),
        throwsA(isA<PlaceLookupFailure>()),
      );
    });
  });

  test('falls over to the next mirror when one is down', () async {
    // On 11 Nov 2026 the main instance 502ed and two mirrors timed out within
    // a minute. A single endpoint means the feature is down with it.
    final tried = <String>[];
    final client = MockClient((request) async {
      tried.add(request.url.host);
      if (tried.length < 3) return http.Response('bad gateway', 502);
      return http.Response(jsonEncode({'elements': [node()]}), 200);
    });
    final provider = OverpassPlaceProvider(
      client: client,
      endpoints: [
        Uri.parse('https://one.test/api'),
        Uri.parse('https://two.test/api'),
        Uri.parse('https://three.test/api'),
      ],
    );

    final places = await provider.nearby(lat: fromLat, lng: fromLng);
    expect(tried, ['one.test', 'two.test', 'three.test']);
    expect(places.single.name, 'Annapoorna');
  });

  test('reports a failure only once every mirror is down', () async {
    final client = MockClient((_) async => http.Response('down', 502));
    final provider = OverpassPlaceProvider(
      client: client,
      endpoints: [Uri.parse('https://one.test/api'), Uri.parse('https://two.test/api')],
    );
    await expectLater(
      provider.nearby(lat: fromLat, lng: fromLng),
      throwsA(isA<PlaceLookupFailure>()),
    );
  });

  test('stops retrying dead mirrors for a short while', () async {
    // A widening search runs the chain twice. With Overpass down that meant
    // paying every mirror timeout twice: a measured search took 77 seconds,
    // half of it waiting on servers already known to be dead.
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('bad gateway', 502);
    });
    final provider = OverpassPlaceProvider(
      client: client,
      endpoints: [Uri.parse('https://a.test/api'), Uri.parse('https://b.test/api')],
    );

    await expectLater(
      provider.nearby(lat: fromLat, lng: fromLng),
      throwsA(isA<PlaceLookupFailure>()),
    );
    expect(requests, 2, reason: 'both mirrors tried the first time');

    // Second call, moments later: no further requests at all.
    await expectLater(
      provider.nearby(lat: fromLat, lng: fromLng),
      throwsA(isA<PlaceLookupFailure>()),
    );
    expect(requests, 2, reason: 'dead mirrors are not tried again at once');
  });

  test('credits OpenStreetMap, as the licence requires', () {
    expect(
      OverpassPlaceProvider().attribution,
      contains('OpenStreetMap'),
    );
  });
}
