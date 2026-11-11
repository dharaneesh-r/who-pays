import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:who_pays/features/venue/data/nominatim_place_provider.dart';
import 'package:who_pays/features/venue/domain/place_provider.dart';

/// Coimbatore town hall.
const fromLat = 11.0021;
const fromLng = 76.9661;

/// A row shaped the way Nominatim really replies, taken from a live call.
Map<String, dynamic> row({
  int osmId = 123,
  String? name = 'Adyar Ananda Bhavan',
  double lat = 11.0100,
  double lng = 76.9700,
  Map<String, String> address = const {'road': 'Bharathiyar Road'},
}) {
  return {
    'place_id': 1,
    'osm_type': 'node',
    'osm_id': osmId,
    'lat': '$lat',
    'lon': '$lng',
    'name': ?name,
    'display_name': 'long postal address, Coimbatore, Tamil Nadu, India',
    'address': address,
  };
}

void main() {
  ({NominatimPlaceProvider provider, List<http.Request> sent}) harness({
    int status = 200,
    Object? body,
    bool throwNetwork = false,
  }) {
    final sent = <http.Request>[];
    final client = MockClient((request) async {
      sent.add(request);
      if (throwNetwork) throw http.ClientException('offline');
      return http.Response(
        body is String ? body : jsonEncode(body ?? <dynamic>[]),
        status,
        headers: {'content-type': 'application/json'},
      );
    });
    return (provider: NominatimPlaceProvider(client: client), sent: sent);
  }

  group('the request', () {
    test('bounds the search to a box around the point', () async {
      final h = harness();
      await h.provider.nearby(lat: fromLat, lng: fromLng, radiusM: 5000);

      final q = h.sent.single.url.queryParameters;
      expect(q['bounded'], '1');
      expect(q['viewbox'], isNotNull);
      expect(q['addressdetails'], '1');
      // Nominatim caps at 40, and the distance filter thins it afterwards.
      expect(q['limit'], '40');
    });

    test('identifies the app, as the usage policy requires', () async {
      final h = harness();
      await h.provider.nearby(lat: fromLat, lng: fromLng);
      final agent = h.sent.single.headers['user-agent'] ?? '';
      expect(agent, contains('WhoPays'));
      // Never anything identifying the person using the app.
      expect(agent, isNot(contains('@')));
    });
  });

  group('parsing', () {
    test('reads a row and computes its distance', () async {
      final h = harness(body: [row()]);
      final p = (await h.provider.nearby(lat: fromLat, lng: fromLng)).single;

      expect(p.name, 'Adyar Ananda Bhavan');
      expect(p.placeId, 'osm:node/123');
      expect(p.address, 'Bharathiyar Road');
      expect(p.distanceM, greaterThan(500));
      expect(p.rating, isNull);
    });

    test('drops anything past the radius the caller asked for', () async {
      // The viewbox is a square around the circle, so its corners reach about
      // 1.4x further. A live Coimbatore call returned a place at 5030 m on a
      // 5 km search.
      final h = harness(body: [
        row(osmId: 1, name: 'Near', lat: 11.0030, lng: 76.9665),
        row(osmId: 2, name: 'Corner', lat: 11.0480, lng: 77.0120),
      ]);
      final places =
          await h.provider.nearby(lat: fromLat, lng: fromLng, radiusM: 5000);
      expect(places.map((p) => p.name), ['Near']);
    });

    test('skips unnamed rows, which Nominatim returns plenty of', () async {
      final h = harness(body: [
        row(osmId: 1, name: 'Anandhas'),
        row(osmId: 2, name: null),
        row(osmId: 3, name: '  '),
      ]);
      final places = await h.provider.nearby(lat: fromLat, lng: fromLng);
      expect(places.map((p) => p.name), ['Anandhas']);
    });

    test('orders nearest first', () async {
      final h = harness(body: [
        row(osmId: 1, name: 'Further', lat: 11.0200, lng: 76.9800),
        row(osmId: 2, name: 'Closer', lat: 11.0025, lng: 76.9663),
      ]);
      final places = await h.provider.nearby(lat: fromLat, lng: fromLng);
      expect(places.map((p) => p.name), ['Closer', 'Further']);
    });

    test('deduplicates by name', () async {
      final h = harness(body: [
        row(osmId: 1, name: 'KR Restaurant'),
        row(osmId: 2, name: 'kr restaurant', lat: 11.0101),
      ]);
      expect(await h.provider.nearby(lat: fromLat, lng: fromLng), hasLength(1));
    });

    test('honours the limit', () async {
      final h = harness(body: [
        for (var i = 0; i < 20; i++)
          row(osmId: i, name: 'Place $i', lat: 11.0021 + i / 100000),
      ]);
      final places =
          await h.provider.nearby(lat: fromLat, lng: fromLng, limit: 4);
      expect(places, hasLength(4));
    });
  });

  group('address', () {
    test('prefers the road', () async {
      final h = harness(body: [
        row(address: {'road': 'Mettupalayam Road', 'city': 'Coimbatore'}),
      ]);
      expect(
        (await h.provider.nearby(lat: fromLat, lng: fromLng)).single.address,
        'Mettupalayam Road',
      );
    });

    test('falls back to the suburb, then the city', () async {
      final suburb = harness(body: [
        row(address: {'suburb': 'Saibaba Colony', 'city': 'Coimbatore'}),
      ]);
      expect(
        (await suburb.provider.nearby(lat: fromLat, lng: fromLng))
            .single
            .address,
        'Saibaba Colony',
      );

      final city = harness(body: [
        row(address: {'city': 'Coimbatore'}),
      ]);
      expect(
        (await city.provider.nearby(lat: fromLat, lng: fromLng)).single.address,
        'Coimbatore',
      );
    });

    test('is null rather than the full postal display_name', () async {
      // display_name runs to the country and is far too long for a row.
      final h = harness(body: [
        row(address: const {}),
      ]);
      expect(
        (await h.provider.nearby(lat: fromLat, lng: fromLng)).single.address,
        isNull,
      );
    });
  });

  group('failure', () {
    test('a network failure reads as advice', () async {
      final h = harness(throwNetwork: true);
      await expectLater(
        h.provider.nearby(lat: fromLat, lng: fromLng),
        throwsA(
          isA<PlaceLookupFailure>()
              .having((e) => e.message, 'message', contains('connection')),
        ),
      );
    });

    test('a rate limit surfaces its status', () async {
      final h = harness(status: 429);
      await expectLater(
        h.provider.nearby(lat: fromLat, lng: fromLng),
        throwsA(isA<PlaceLookupFailure>()),
      );
    });

    test('a captive portal page does not crash the screen', () async {
      final h = harness(body: '<html>Sign in</html>');
      await expectLater(
        h.provider.nearby(lat: fromLat, lng: fromLng),
        throwsA(isA<PlaceLookupFailure>()),
      );
    });
  });

  test('credits OpenStreetMap', () {
    expect(NominatimPlaceProvider().attribution, contains('OpenStreetMap'));
  });
}
