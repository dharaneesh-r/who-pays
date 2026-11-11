import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../domain/place_provider.dart';
import '../domain/venue_models.dart';

/// Nearby places from OpenStreetMap's Nominatim service.
///
/// Spec: VENUES.md §14. A **fallback** behind [OverpassPlaceProvider], not a
/// replacement, for two reasons.
///
/// It is better at addresses: Overpass can only report `addr:*` tags that
/// somebody actually mapped, while Nominatim resolves the containing street.
/// For Coimbatore it returns "Adyar Ananda Bhavan, Bharathiyar Road" where
/// Overpass returns a name and nothing else.
///
/// But it is a **geocoder**, not a place search. It takes a text query, so
/// this asks for "restaurant" inside a bounding box and filters the answers
/// by real distance afterwards. Nominatim's usage policy asks for no more
/// than one request a second and discourages systematic POI harvesting — one
/// request per dinner is well inside that, and this must never be used for
/// anything heavier. If the app ever gets popular enough for that to strain,
/// the answer is a proper provider with a key, not more of this.
class NominatimPlaceProvider implements PlaceProvider {
  NominatimPlaceProvider({http.Client? client, Uri? endpoint})
      : _client = client ?? http.Client(),
        _endpoint = endpoint ?? _defaultEndpoint;

  final http.Client _client;
  final Uri _endpoint;

  static final _defaultEndpoint =
      Uri.parse('https://nominatim.openstreetmap.org/search');

  /// Keeps the worst case — every Overpass mirror dead, then this — inside
  /// about half a minute rather than two and a half.
  static const _timeout = Duration(seconds: 8);

  /// Nominatim matches text, not categories, so one query for "restaurant"
  /// misses most places. Measured within 2 km of Coimbatore town hall:
  /// "restaurant" alone found 35, adding these found 80.
  ///
  /// "hotel" is deliberately absent. In Indian English it usually means an
  /// eatery, but every one of the 20 results it returned was `tourism=hotel`
  /// — somewhere to sleep. Eateries actually named "Hotel X" are tagged as
  /// restaurants and come back from the other terms anyway.
  static const _terms = ['restaurant', 'cafe', 'bakery'];

  /// What counts as somewhere to eat. Anything else a text search drags in —
  /// lodging above all — is dropped.
  static const _foodTypes = {
    'restaurant',
    'cafe',
    'fast_food',
    'food_court',
    'ice_cream',
    'bakery',
    'pastry',
    'confectionery',
    'bar',
    'pub',
    'canteen',
    'deli',
  };

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

    // One request per term, in sequence. Nominatim's usage policy allows at
    // most one request a second, so these are never fired in parallel.
    final found = <String, Place>{};
    for (final term in _terms) {
      final places = await _search(term, lat, lng, radius);
      for (final place in places) {
        // First term wins a duplicate, so the more specific "restaurant"
        // result beats the same shop found again under "bakery".
        found.putIfAbsent(place.name.toLowerCase().trim(), () => place);
      }
    }

    final places = found.values.toList()
      ..sort(
        (a, b) => (a.distanceM ?? 1 << 30).compareTo(b.distanceM ?? 1 << 30),
      );
    return places.take(limit).toList();
  }

  Future<List<Place>> _search(
    String term,
    double lat,
    double lng,
    int radius,
  ) async {
    final dLat = radius / 111320.0;
    final dLng = radius / (111320.0 * math.cos(lat * math.pi / 180).abs());

    final url = _endpoint.replace(queryParameters: {
      'q': term,
      'format': 'jsonv2',
      // Nominatim caps this at 40. Ask for the lot, since the distance filter
      // and the name filter will both thin it out.
      'limit': '40',
      'bounded': '1',
      'viewbox': '${lng - dLng},${lat + dLat},${lng + dLng},${lat - dLat}',
      'addressdetails': '1',
    });

    http.Response response;
    try {
      response = await _client.get(url, headers: {
        // Nominatim's policy requires a identifying User-Agent. A product
        // name only — never anything identifying the person using the app.
        'User-Agent': 'WhoPays/0.1 (Flutter app)',
        'Accept': 'application/json',
      }).timeout(_timeout);
    } catch (_) {
      throw const PlaceLookupFailure(
        'Could not reach the places service. Check the connection.',
      );
    }

    if (response.statusCode != 200) {
      throw PlaceLookupFailure(
        'Places lookup failed (${response.statusCode}).',
      );
    }

    final List<dynamic> rows;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const [];
      rows = decoded;
    } catch (_) {
      throw const PlaceLookupFailure('Unexpected reply from places.');
    }

    return [
      for (final row in rows)
        if (row is Map<String, dynamic>) ?_place(row, lat, lng, radius),
    ];
  }

  static Place? _place(
    Map<String, dynamic> row,
    double fromLat,
    double fromLng,
    int radius,
  ) {
    final name = row['name'];
    // Plenty of rows come back with an empty name — a numbered building, or
    // the street itself. Nothing to vote for.
    if (name is! String || name.trim().isEmpty) return null;

    // A text search drags in whatever shares the word. Every result for
    // "hotel" was somewhere to sleep; keep only somewhere to eat.
    final type = row['type'];
    if (type is! String || !_foodTypes.contains(type)) return null;

    final lat = double.tryParse('${row['lat']}');
    final lng = double.tryParse('${row['lon']}');
    if (lat == null || lng == null) return null;

    final distance = distanceMetres(
      fromLat: fromLat,
      fromLng: fromLng,
      toLat: lat,
      toLng: lng,
    );
    // The box reaches past the circle at its corners. Honour the radius the
    // caller asked for rather than offering somewhere 7 km away on a 5 km
    // search.
    if (distance > radius) return null;

    return Place(
      placeId: 'osm:${row['osm_type'] ?? 'node'}/${row['osm_id']}',
      name: name.trim(),
      address: _address(row['address']),
      lat: lat,
      lng: lng,
      distanceM: distance,
      // OpenStreetMap has no ratings.
      rating: null,
    );
  }

  /// The most specific useful line Nominatim gives. Its `display_name` is the
  /// full postal address down to the country, which is far too long for a
  /// ballot row.
  static String? _address(Object? address) {
    if (address is! Map) return null;
    for (final key in ['road', 'suburb', 'neighbourhood', 'city_district']) {
      final value = address[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    final city = address['city'] ?? address['town'] ?? address['village'];
    return city is String && city.trim().isNotEmpty ? city.trim() : null;
  }
}
