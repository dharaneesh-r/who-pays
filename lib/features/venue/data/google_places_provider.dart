import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/places_config.dart';
import '../domain/place_provider.dart';
import '../domain/venue_models.dart';

/// Nearby restaurants from the Google Places API (New).
///
/// Spec: VENUES.md §14. Called **once per room, by the host only** — guests
/// read the candidates out of `room_venues`. That is what keeps a ten-person
/// table at one request rather than ten, and is the whole reason this fits
/// inside the free monthly allowance.
///
/// ## What is stored, and for how long
///
/// The Places terms restrict caching their content. The rows this writes into
/// `room_venues` cascade from `rooms`, and `purge_old_rooms()` in
/// `supabase/schema.sql` deletes rooms older than a day — so place data lives
/// at most 24 hours. Place **ids** may be kept indefinitely, which is why
/// `place_id` is the column that identifies a venue rather than its name.
/// If that purge job is ever switched off, this claim stops being true.
///
/// ## Attribution
///
/// Showing Places data without a Google map requires visible attribution,
/// which is why [attribution] is part of the interface and the ballot screen
/// renders it. It is not optional polish.
class GooglePlacesProvider implements PlaceProvider {
  GooglePlacesProvider({http.Client? client, String? apiKey})
      : _client = client ?? http.Client(),
        _key = apiKey ?? PlacesConfig.key;

  final http.Client _client;
  final String _key;

  static final _endpoint =
      Uri.parse('https://places.googleapis.com/v1/places:searchNearby');

  /// Indian English calls a modest eatery a "hotel", so cafes are included
  /// alongside restaurants. Anything broader turns the ballot into noise.
  static const _types = ['restaurant', 'cafe'];

  /// Only the fields the ballot actually shows. The field mask is not
  /// optional on this API, and asking for fields we do not use costs money.
  static const _fieldMask =
      'places.id,places.displayName,places.formattedAddress,'
      'places.location,places.rating';

  @override
  String? get attribution => 'Powered by Google';

  /// Releases the connection pool. Wired to the provider's `onDispose`, since
  /// an `http.Client` holds sockets open until it is told not to.
  void close() => _client.close();

  @override
  Future<List<Place>> nearby({
    required double lat,
    required double lng,
    int radiusM = 5000,
    int limit = 20,
  }) async {
    if (_key.isEmpty) {
      throw const PlaceLookupFailure('No places key in this build.');
    }

    // The API caps searchNearby at 20 results, which happens to be the cap the
    // ballot wants anyway. Asking for more is rejected outright.
    final count = limit.clamp(1, 20);

    http.Response response;
    try {
      response = await _client.post(
        _endpoint,
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _key,
          'X-Goog-FieldMask': _fieldMask,
        },
        body: jsonEncode({
          'includedTypes': _types,
          'maxResultCount': count,
          'locationRestriction': {
            'circle': {
              'center': {'latitude': lat, 'longitude': lng},
              // The API wants a double, and rejects a radius over 50 km.
              'radius': radiusM.clamp(1, 50000).toDouble(),
            },
          },
        }),
      );
    } catch (_) {
      // No network, DNS failure, a captive portal on the restaurant wifi.
      throw const PlaceLookupFailure(
        'Could not reach the places service. Check the connection.',
      );
    }

    if (response.statusCode != 200) {
      throw PlaceLookupFailure(_errorMessage(response));
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const PlaceLookupFailure('Unexpected reply from places.');
    }

    // A search with no hits returns `{}`, not an empty list.
    final raw = body['places'];
    if (raw is! List) return const [];

    final places = <Place>[
      for (final entry in raw)
        if (entry is Map<String, dynamic>) ?_place(entry, lat, lng),
    ];

    // Best first, then nearest. This decides which places make the ballot when
    // the API returns more than the table should have to read; it is not the
    // vote, which is the only thing that decides where anyone eats.
    places.sort((a, b) {
      final byRating = (b.rating ?? 0).compareTo(a.rating ?? 0);
      if (byRating != 0) return byRating;
      return (a.distanceM ?? 1 << 30).compareTo(b.distanceM ?? 1 << 30);
    });

    return places.take(count).toList();
  }

  /// Null for an entry with no id or no name — there would be nothing to vote
  /// for and nothing to store.
  static Place? _place(Map<String, dynamic> p, double fromLat, double fromLng) {
    final id = p['id'] as String?;
    if (id == null || id.isEmpty) return null;

    final name = (p['displayName'] as Map<String, dynamic>?)?['text'] as String?;
    if (name == null || name.trim().isEmpty) return null;

    final location = p['location'] as Map<String, dynamic>?;
    final placeLat = (location?['latitude'] as num?)?.toDouble();
    final placeLng = (location?['longitude'] as num?)?.toDouble();

    return Place(
      placeId: id,
      name: name.trim(),
      address: (p['formattedAddress'] as String?)?.trim(),
      lat: placeLat,
      lng: placeLng,
      // Computed here, by the host, and then stored — never recomputed per
      // device. Distance is the vote tie-break, so every phone has to be
      // comparing the same numbers.
      distanceM: placeLat == null || placeLng == null
          ? null
          : distanceMetres(
              fromLat: fromLat,
              fromLng: fromLng,
              toLat: placeLat,
              toLng: placeLng,
            ),
      rating: (p['rating'] as num?)?.toDouble(),
    );
  }

  /// Google's own message where there is one — "API key not valid" is worth
  /// showing, because it tells whoever built the APK exactly what is wrong.
  static String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        final error = body['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message'];
          if (message is String && message.trim().isNotEmpty) {
            return message.trim();
          }
        }
      }
    } catch (_) {
      // Fall through to the status code.
    }
    return 'Places lookup failed (${response.statusCode}).';
  }
}
