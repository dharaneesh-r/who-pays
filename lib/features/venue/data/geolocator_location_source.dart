import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'location_source.dart';

/// The real thing: one precise fix from the phone.
///
/// Spec: VENUES.md §12, §16. Three rules this holds to deliberately:
///
///   * **Precise.** Coarse carries 500 m to 1 km of error, which is larger
///     than the differences the ballot asks people to judge — it showed
///     "450 m" for somewhere that might be a kilometre away, and could sort a
///     shop across the road behind one twice as far. A list about distance
///     needs a fix better than the distances on it.
///   * **One fix, never a stream.** This app has no business watching anybody
///     move, and nothing is stored about where the phone has been.
///   * **Host only.** Guests read the candidate list out of `room_venues`, so
///     this is never called on a guest's phone.
///
/// Every failure becomes a [LocationUnavailable] whose message is written for
/// someone standing in a restaurant, not for a log file.
class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  /// Long enough for a cold GPS fix indoors, short enough that nobody thinks
  /// the app has hung while their friends wait to order.
  static const _timeout = Duration(seconds: 15);

  @override
  Future<LatLng> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable(
        'Location is switched off on this phone. Turn it on, or pick a place '
        'yourselves.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // Denied for good: the system will not ask again, so saying "allow it"
    // would be useless advice. Only Settings can undo this.
    if (permission == LocationPermission.deniedForever) {
      throw const LocationUnavailable(
        'Location is blocked for this app. You can allow it in Settings, or '
        'just pick a place yourselves.',
      );
    }

    // A user who grants only approximate location on Android 12+ still lands
    // here as whileInUse, and that is deliberately not an error: the search
    // works, the distances are simply softer, and nagging someone for making
    // a considered privacy choice would be worse than a vaguer list.
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      throw const LocationUnavailable(
        'Without location we cannot find places nearby — pick one yourselves.',
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // Precise on purpose. See the class comment.
          accuracy: LocationAccuracy.high,
          timeLimit: _timeout,
        ),
      );
      return LatLng(position.latitude, position.longitude);
    } on TimeoutException {
      throw const LocationUnavailable(
        'Could not get a location — indoors it sometimes will not. Try again '
        'or pick a place yourselves.',
      );
    } on LocationServiceDisabledException {
      // Can still happen: switched off between the check above and the fix.
      throw const LocationUnavailable(
        'Location was switched off. Turn it on, or pick a place yourselves.',
      );
    } catch (_) {
      throw const LocationUnavailable(
        'Could not get a location. Pick a place yourselves.',
      );
    }
  }
}
