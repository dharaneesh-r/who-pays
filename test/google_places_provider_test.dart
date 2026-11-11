import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:who_pays/features/venue/data/google_places_provider.dart';
import 'package:who_pays/features/venue/domain/place_provider.dart';

/// Chennai Central, the point every expectation below is measured from.
const fromLat = 13.0827;
const fromLng = 80.2707;

/// One entry shaped the way the Places API (New) really replies.
Map<String, dynamic> place({
  String id = 'ChIJ_abc',
  String? name = 'Hotel Saravana Bhavan',
  String? address = 'T. Nagar, Chennai',
  double? lat = 13.0400,
  double? lng = 80.2300,
  num? rating = 4.3,
}) {
  // Built imperatively rather than with collection-ifs: a missing field is
  // an absent key here, which is exactly how the API behaves, and the
  // null-aware element form cannot express "omit the whole entry".
  final entry = <String, dynamic>{'id': id};
  if (name != null) {
    entry['displayName'] = {'text': name, 'languageCode': 'en'};
  }
  if (address != null) entry['formattedAddress'] = address;
  if (lat != null && lng != null) {
    entry['location'] = {'latitude': lat, 'longitude': lng};
  }
  if (rating != null) entry['rating'] = rating;
  return entry;
}

void main() {
  /// A provider wired to a canned reply, capturing the request it made.
  ({GooglePlacesProvider provider, List<http.Request> sent}) harness({
    int status = 200,
    Object? body,
    bool throwNetwork = false,
    String apiKey = 'test-key',
  }) {
    final sent = <http.Request>[];
    final client = MockClient((request) async {
      sent.add(request);
      if (throwNetwork) throw http.ClientException('no route to host');
      return http.Response(
        body is String ? body : jsonEncode(body ?? {}),
        status,
        headers: {'content-type': 'application/json'},
      );
    });
    return (
      provider: GooglePlacesProvider(client: client, apiKey: apiKey),
      sent: sent,
    );
  }

  group('the request', () {
    test('asks for restaurants in a circle, with a field mask', () async {
      final h = harness(body: {'places': <dynamic>[]});
      await h.provider.nearby(lat: fromLat, lng: fromLng, radiusM: 5000);

      final request = h.sent.single;
      expect(request.method, 'POST');
      expect(request.url.host, 'places.googleapis.com');
      expect(request.headers['X-Goog-Api-Key'], 'test-key');
      // The field mask is mandatory on this API, and every extra field costs
      // money, so it must stay narrow.
      expect(request.headers['X-Goog-FieldMask'], contains('places.id'));
      expect(request.headers['X-Goog-FieldMask'], isNot(contains('reviews')));

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['includedTypes'], contains('restaurant'));
      final circle = (body['locationRestriction']
          as Map<String, dynamic>)['circle'] as Map<String, dynamic>;
      expect(circle['radius'], 5000.0);
      expect((circle['center'] as Map)['latitude'], fromLat);
    });

    test('clamps the count to the 20 the API allows', () async {
      final h = harness(body: {'places': <dynamic>[]});
      await h.provider.nearby(lat: fromLat, lng: fromLng, limit: 60);

      final body = jsonDecode(h.sent.single.body) as Map<String, dynamic>;
      expect(body['maxResultCount'], 20);
    });

    test('clamps an absurd radius rather than being rejected', () async {
      final h = harness(body: {'places': <dynamic>[]});
      await h.provider.nearby(lat: fromLat, lng: fromLng, radiusM: 900000);

      final body = jsonDecode(h.sent.single.body) as Map<String, dynamic>;
      final circle = (body['locationRestriction']
          as Map<String, dynamic>)['circle'] as Map<String, dynamic>;
      expect(circle['radius'], 50000.0);
    });

    test('never calls out at all without a key', () async {
      final h = harness(apiKey: '');
      await expectLater(
        h.provider.nearby(lat: fromLat, lng: fromLng),
        throwsA(isA<PlaceLookupFailure>()),
      );
      // The point: no request, so no bill and no 403 in the console.
      expect(h.sent, isEmpty);
    });
  });

  group('parsing', () {
    test('reads a place and computes its distance', () async {
      final h = harness(body: {'places': [place()]});
      final places =
          await h.provider.nearby(lat: fromLat, lng: fromLng, radiusM: 50000);

      final p = places.single;
      expect(p.placeId, 'ChIJ_abc');
      expect(p.name, 'Hotel Saravana Bhavan');
      expect(p.address, 'T. Nagar, Chennai');
      expect(p.rating, 4.3);
      // Computed by the host and then stored, never recomputed per device,
      // because distance is the vote tie-break.
      expect(p.distanceM, greaterThan(5000));
      expect(p.distanceM, lessThan(7000));
    });

    test('survives a place with no rating, address or location', () async {
      final h = harness(body: {
        'places': [place(id: 'bare', rating: null, address: null, lat: null, lng: null)],
      });
      final places = await h.provider.nearby(lat: fromLat, lng: fromLng);

      final p = places.single;
      expect(p.rating, isNull);
      expect(p.address, isNull);
      // No coordinates means no distance — and VenueBallot sorts an unknown
      // distance last rather than first.
      expect(p.distanceM, isNull);
    });

    test('skips an entry with no id or no name — nothing to vote for',
        () async {
      final h = harness(body: {
        'places': [
          place(id: 'good'),
          {'id': 'no-name'},
          place(id: '', name: 'Nameless id'),
          place(id: 'blank-name', name: '   '),
          'not even an object',
        ],
      });
      final places = await h.provider.nearby(lat: fromLat, lng: fromLng);
      expect(places.map((p) => p.placeId), ['good']);
    });

    test('an empty search returns {} rather than an empty list', () async {
      // This is what the API actually sends when nothing matches, and reading
      // it as a list would throw.
      final h = harness(body: <String, dynamic>{});
      expect(await h.provider.nearby(lat: fromLat, lng: fromLng), isEmpty);
    });

    test('reads an integer rating', () async {
      final h = harness(body: {'places': [place(rating: 4)]});
      final places = await h.provider.nearby(lat: fromLat, lng: fromLng);
      expect(places.single.rating, 4.0);
    });

    test('orders by rating, then by distance', () async {
      final h = harness(body: {
        'places': [
          place(id: 'far-good', rating: 4.8, lat: 13.20, lng: 80.40),
          place(id: 'near-poor', rating: 3.1, lat: 13.083, lng: 80.271),
          place(id: 'near-good', rating: 4.8, lat: 13.085, lng: 80.272),
        ],
      });
      final places =
          await h.provider.nearby(lat: fromLat, lng: fromLng, radiusM: 50000);

      expect(
        places.map((p) => p.placeId),
        ['near-good', 'far-good', 'near-poor'],
      );
    });

    test('returns no more than asked for', () async {
      final h = harness(body: {
        'places': [for (var i = 0; i < 10; i++) place(id: 'p$i')],
      });
      final places =
          await h.provider.nearby(lat: fromLat, lng: fromLng, limit: 3);
      expect(places, hasLength(3));
    });
  });

  group('failure', () {
    test('surfaces Google’s own message, which names the real problem',
        () async {
      final h = harness(
        status: 403,
        body: {
          'error': {'code': 403, 'message': 'API key not valid.'},
        },
      );
      await expectLater(
        h.provider.nearby(lat: fromLat, lng: fromLng),
        throwsA(
          isA<PlaceLookupFailure>().having(
            (e) => e.message,
            'message',
            'API key not valid.',
          ),
        ),
      );
    });

    test('falls back to the status code when there is no message', () async {
      final h = harness(status: 500, body: {'error': {}});
      await expectLater(
        h.provider.nearby(lat: fromLat, lng: fromLng),
        throwsA(
          isA<PlaceLookupFailure>()
              .having((e) => e.message, 'message', contains('500')),
        ),
      );
    });

    test('a network failure reads as advice, not as a stack trace', () async {
      final h = harness(throwNetwork: true);
      await expectLater(
        h.provider.nearby(lat: fromLat, lng: fromLng),
        throwsA(
          isA<PlaceLookupFailure>()
              .having((e) => e.message, 'message', contains('connection')),
        ),
      );
    });

    test('a non-JSON body does not crash the screen', () async {
      // A captive portal serving an HTML login page is the usual cause.
      final h = harness(body: '<html>Sign in to WiFi</html>');
      await expectLater(
        h.provider.nearby(lat: fromLat, lng: fromLng),
        throwsA(isA<PlaceLookupFailure>()),
      );
    });
  });

  test('declares the attribution Google requires', () {
    // Showing their place data without a Google map needs visible credit, and
    // the ballot screen renders whatever this returns.
    expect(GooglePlacesProvider(apiKey: 'k').attribution, 'Powered by Google');
  });
}
