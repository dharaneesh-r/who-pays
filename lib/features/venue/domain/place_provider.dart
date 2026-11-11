import 'dart:math' as math;

import 'venue_models.dart';

/// Where nearby restaurants come from.
///
/// Spec: VENUES.md §14.
///
/// This exists as an interface for one reason: the choice of provider is not
/// settled. Google has the best coverage in India and fits inside its free
/// monthly allowance at one request per dinner, but requires a billing
/// account on file. OpenStreetMap needs no card and is patchy here. Behind
/// this interface, that decision can change without touching the voting code
/// — and none of the voting code is blocked waiting for an API key.
abstract interface class PlaceProvider {
  /// Credit the data source must be shown, or null when there is nothing to
  /// credit.
  ///
  /// Part of the interface rather than a detail of one implementation because
  /// Google requires visible attribution when their place data is shown
  /// without a Google map. A screen that forgets it is a licence breach, so
  /// the interface makes it impossible to add a provider without deciding.
  String? get attribution;

  /// Restaurants near a point, nearest-and-best first.
  ///
  /// Called **once per room, by the host only** — never per guest. Guests read
  /// the candidates out of `room_venues`. That is what keeps a ten-person
  /// table at one API request instead of ten.
  Future<List<Place>> nearby({
    required double lat,
    required double lng,
    int radiusM,
    int limit,
  });
}

/// Thrown when a lookup fails in a way the table can act on. The message is
/// shown to the user, so it is written for a person at a restaurant, not for a
/// log file.
class PlaceLookupFailure implements Exception {
  const PlaceLookupFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Metres between two coordinates on a sphere.
///
/// Good to a fraction of a percent at city scale, which is far better than a
/// phone's location fix, and avoids a dependency for twelve lines of maths.
/// Used for the vote tie-break, so it must be identical on every phone —
/// which is why distance is computed once by the host and stored, never
/// recomputed per device.
int distanceMetres({
  required double fromLat,
  required double fromLng,
  required double toLat,
  required double toLng,
}) {
  const earthRadiusM = 6371000.0;
  double radians(double deg) => deg * math.pi / 180.0;

  final dLat = radians(toLat - fromLat);
  final dLng = radians(toLng - fromLng);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(radians(fromLat)) *
          math.cos(radians(toLat)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return (earthRadiusM * c).round();
}

/// A fixed list of places, for tests and for developing without a key.
///
/// Deliberately returns plausible rather than pretty data: one entry with no
/// rating and one with no address, because the real providers do that and the
/// UI has to survive it.
class FakePlaceProvider implements PlaceProvider {
  const FakePlaceProvider({this.places, this.failure});

  final List<Place>? places;

  /// Set to make every call fail, so error handling can be exercised.
  final PlaceLookupFailure? failure;

  /// Nothing to credit: these places are invented.
  @override
  String? get attribution => null;

  @override
  Future<List<Place>> nearby({
    required double lat,
    required double lng,
    int radiusM = 5000,
    int limit = 20,
  }) async {
    final f = failure;
    if (f != null) throw f;
    final list = places ?? _defaults;
    return list.where((p) => (p.distanceM ?? 0) <= radiusM).take(limit).toList();
  }

  static const _defaults = <Place>[
    Place(
      placeId: 'fake-1',
      name: 'Hotel Saravana Bhavan',
      address: 'T. Nagar',
      distanceM: 450,
      rating: 4.3,
    ),
    Place(
      placeId: 'fake-2',
      name: 'Murugan Idli Shop',
      address: 'Besant Nagar',
      distanceM: 1200,
      rating: 4.5,
    ),
    Place(
      placeId: 'fake-3',
      name: 'Buhari',
      address: 'Anna Salai',
      distanceM: 2600,
      rating: 4.0,
    ),
    // No rating — providers often have none for new or small places.
    Place(placeId: 'fake-4', name: 'Thalappakatti', distanceM: 3100),
    // No address.
    Place(placeId: 'fake-5', name: 'Ratna Cafe', distanceM: 4800, rating: 4.1),
    // Outside a 5 km radius: present so the filter is actually tested.
    Place(placeId: 'fake-6', name: 'Too Far Cafe', distanceM: 7400, rating: 4.9),
  ];
}
