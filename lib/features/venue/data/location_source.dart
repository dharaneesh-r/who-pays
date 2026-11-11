import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/location_config.dart';
import 'geolocator_location_source.dart';

/// Where the host's phone is.
///
/// Spec: VENUES.md §12. Behind an interface for the same reason
/// [PlaceProvider] is: the real implementation needs a location permission in
/// the manifest, and adding one before the Play closed test restarts the Data
/// Safety review (§7). So the interface and every screen above it are built
/// now, and the single class that touches the sensor is added when that gate
/// is cleared.
///
/// **Only the host calls this.** Everyone is at the same table, so one fix is
/// the correct number of fixes — guests read the candidate list out of
/// `room_venues` and are never asked for location at all.
abstract interface class LocationSource {
  /// A single coarse fix. Never a stream: this app has no business watching
  /// anybody move.
  Future<LatLng> current();
}

class LatLng {
  const LatLng(this.lat, this.lng);
  final double lat;
  final double lng;
}

/// Thrown when there is no usable fix. The message is read by a person in a
/// restaurant, so it says what to do, not what went wrong.
class LocationUnavailable implements Exception {
  const LocationUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A fixed point, for development and tests.
///
/// Defaults to central Chennai, which matches [FakePlaceProvider]'s list so
/// the two line up when the app is run without a real provider.
class FixedLocationSource implements LocationSource {
  const FixedLocationSource({this.point = const LatLng(13.0827, 80.2707)});

  final LatLng point;

  @override
  Future<LatLng> current() async => point;
}

/// The real source only when the build asks for it.
///
/// Off by default: see [LocationConfig] for why that is a policy decision
/// rather than an oversight, and what the two steps to enable it are. With it
/// off the ballot still works end to end from a fixed point.
final locationSourceProvider = Provider<LocationSource>(
  (_) => LocationConfig.enabled
      ? const GeolocatorLocationSource()
      : const FixedLocationSource(),
);
