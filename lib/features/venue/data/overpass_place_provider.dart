import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/place_provider.dart';
import '../domain/venue_models.dart';

/// Nearby places from OpenStreetMap, via the Overpass API.
///
/// Spec: VENUES.md §14. This is the **default** provider: free, no API key, no
/// billing account, no signup. Google Places has better coverage in India, but
/// it needs a card on file before it returns a single result, and an app that
/// shows nothing until its owner sets up billing is an app that shows nothing.
///
/// What it gives up: OpenStreetMap has **no ratings**, so every candidate
/// comes back with a null rating and the ballot simply omits the star. It also
/// thins out away from city centres, which is a real limitation — in a small
/// town the list may be short or empty, and the screen says so rather than
/// pretending.
///
/// Attribution is required by the ODbL licence, which is why [attribution] is
/// part of the interface and the ballot screen renders it.
class OverpassPlaceProvider implements PlaceProvider {
  OverpassPlaceProvider({http.Client? client, List<Uri>? endpoints})
      : _client = client ?? http.Client(),
        _endpoints = endpoints ?? defaultEndpoints;

  final http.Client _client;
  final List<Uri> _endpoints;

  /// Tried in order until one answers.
  ///
  /// Not belt-and-braces: on 11 Nov 2026 the main instance returned 502 and
  /// two mirrors timed out, all within a minute. These are volunteer-run
  /// servers with no SLA, and a single endpoint means the feature is down
  /// whenever that one server is.
  static final defaultEndpoints = [
    Uri.parse('https://overpass-api.de/api/interpreter'),
    Uri.parse('https://overpass.kumi.systems/api/interpreter'),
    Uri.parse('https://overpass.private.coffee/api/interpreter'),
  ];

  /// "Hotel" in Indian English means an eatery, so this is deliberately
  /// broader than `restaurant` alone. `food_court` matters in malls.
  static const _amenities = 'restaurant|cafe|fast_food|food_court';

  /// Short on purpose, and much shorter than the server-side `[timeout:25]`
  /// in the query.
  ///
  /// Measured on a phone in Coimbatore: with 25 s per mirror, three failing
  /// mirrors meant 75 s of spinner before the fallback was even tried, and a
  /// full search took 144 s. Nobody waits that long at a table. A healthy
  /// Overpass answers this query in two or three seconds, so anything past
  /// six is already a sick server and the next source is the better bet.
  ///
  /// Public Overpass instances are a shared volunteer resource. One request
  /// per dinner is well within fair use; polling would not be.
  static const _timeout = Duration(seconds: 6);

  void close() => _client.close();

  @override
  String? get attribution => '© OpenStreetMap contributors';

  @override
  Future<List<Place>> nearby({
    required double lat,
    required double lng,
    int radiusM = 5000,
    int limit = 20,
  }) async {
    final radius = radiusM.clamp(100, 50000);

    // `out center` gives ways (a building mapped as an area) a single point,
    // so a restaurant mapped as a polygon is not silently dropped.
    final query = '[out:json][timeout:25];'
        '('
        'node["amenity"~"^($_amenities)\$"](around:$radius,$lat,$lng);'
        'way["amenity"~"^($_amenities)\$"](around:$radius,$lat,$lng);'
        ');'
        'out center ${(limit * 3).clamp(10, 120)};';

    // Try each mirror in turn. Only the last failure is reported, because by
    // then they are all down and the person just needs to know to pick a
    // place themselves.
    http.Response? response;
    PlaceLookupFailure? lastFailure;

    for (final endpoint in _endpoints) {
      try {
        final attempt = await _client
            .post(
              endpoint,
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                // Overpass asks clients to identify themselves. A product
                // name only — never anything identifying the person.
                'User-Agent': 'WhoPays/0.1 (Flutter app)',
              },
              body: {'data': query},
            )
            .timeout(_timeout);

        if (attempt.statusCode == 200) {
          response = attempt;
          break;
        }

        // 429/504 is load shedding, 502/503 is the server being down. All of
        // them mean "ask the next mirror", not "give up".
        lastFailure = const PlaceLookupFailure(
          'The places service is busy. Try again in a moment.',
        );
      } catch (_) {
        lastFailure = const PlaceLookupFailure(
          'Could not reach the places service. Check the connection.',
        );
      }
    }

    if (response == null) {
      throw lastFailure ??
          const PlaceLookupFailure('Could not reach the places service.');
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const PlaceLookupFailure('Unexpected reply from places.');
    }

    final elements = body['elements'];
    if (elements is! List) return const [];

    final places = <Place>[
      for (final element in elements)
        if (element is Map<String, dynamic>) ?_place(element, lat, lng),
    ];

    // Nearest first. OpenStreetMap has no popularity signal to rank by, so
    // distance is the only honest ordering — and at a table it is the one
    // people care about anyway.
    places.sort(
      (a, b) => (a.distanceM ?? 1 << 30).compareTo(b.distanceM ?? 1 << 30),
    );

    // Deduplicate: a venue mapped as both a node and a building way appears
    // twice, and a ballot listing the same restaurant twice looks broken.
    final seen = <String>{};
    final unique = <Place>[
      for (final p in places)
        if (seen.add(p.name.toLowerCase().trim())) p,
    ];

    return unique.take(limit).toList();
  }

  static Place? _place(
    Map<String, dynamic> element,
    double fromLat,
    double fromLng,
  ) {
    final tags = element['tags'];
    if (tags is! Map) return null;

    final name = tags['name'];
    // An unnamed restaurant cannot be voted for or recognised at the table.
    if (name is! String || name.trim().isEmpty) return null;

    // Nodes carry lat/lon directly; ways carry a computed centre.
    final centre = element['center'];
    final lat = (element['lat'] ?? (centre is Map ? centre['lat'] : null))
        as num?;
    final lng = (element['lon'] ?? (centre is Map ? centre['lon'] : null))
        as num?;
    if (lat == null || lng == null) return null;

    final type = element['type'] as String? ?? 'node';
    final id = element['id'];
    if (id == null) return null;

    return Place(
      placeId: 'osm:$type/$id',
      name: name.trim(),
      address: _address(tags),
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      distanceM: distanceMetres(
        fromLat: fromLat,
        fromLng: fromLng,
        toLat: lat.toDouble(),
        toLng: lng.toDouble(),
      ),
      // OpenStreetMap has no ratings. The ballot omits the star rather than
      // inventing one.
      rating: null,
    );
  }

  /// Whatever address tags exist, in the order a person would say them.
  /// OpenStreetMap addresses are patchy, so this returns null rather than a
  /// fragment that says nothing.
  static String? _address(Map tags) {
    String? tag(String key) {
      final value = tags[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    final street = tag('addr:street');
    final number = tag('addr:housenumber');
    final area = tag('addr:suburb') ?? tag('addr:neighbourhood');
    final city = tag('addr:city');

    // Built up rather than with collection-ifs: each part is conditional on
    // more than its own nullness, which the null-aware element form cannot
    // express.
    final line = <String>[];
    if (street != null) {
      line.add(number == null ? street : '$number $street');
    }
    if (area != null) line.add(area);
    // Only worth saying when nothing more specific is known.
    if (street == null && area == null && city != null) line.add(city);

    return line.isEmpty ? null : line.join(', ');
  }
}
