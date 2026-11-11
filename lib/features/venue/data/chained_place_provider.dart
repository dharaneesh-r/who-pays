import '../domain/place_provider.dart';
import '../domain/venue_models.dart';

/// Asks each source in turn until one has somewhere to eat.
///
/// Spec: VENUES.md §14. This exists because of a measured failure, not a
/// hypothetical one: on 11 Nov 2026 every Overpass mirror was failing at the
/// same moment, on the phone and the desktop, and the ballot showed nothing.
/// The OpenStreetMap *data* was fine throughout — only that one piece of
/// volunteer infrastructure was down. A second free service reading the same
/// data would have answered.
///
/// The order matters. The first source is the one whose answers are best, not
/// the one most likely to reply; a slower, better list is worth waiting for,
/// and the fallbacks only run when the preferred source gives nothing.
///
/// An empty result counts as a failure worth falling through on. "No
/// restaurants within 5 km" is almost always a thin source rather than an
/// empty neighbourhood, and the last source's empty answer is still returned
/// honestly if they all agree.
class ChainedPlaceProvider implements PlaceProvider {
  ChainedPlaceProvider(this.sources) : assert(sources.isNotEmpty);

  final List<PlaceProvider> sources;

  /// Credit for every source that asks for it, since any of them may have
  /// produced what is on screen. Deduplicated — they are mostly all
  /// OpenStreetMap, and crediting it three times would be absurd.
  @override
  String? get attribution {
    final credits = <String>{
      for (final source in sources) ?source.attribution,
    };
    return credits.isEmpty ? null : credits.join(' · ');
  }

  @override
  Future<List<Place>> nearby({
    required double lat,
    required double lng,
    int radiusM = 5000,
    int limit = 20,
  }) async {
    PlaceLookupFailure? lastFailure;

    for (final source in sources) {
      try {
        final places = await source.nearby(
          lat: lat,
          lng: lng,
          radiusM: radiusM,
          limit: limit,
        );
        if (places.isNotEmpty) return places;
      } on PlaceLookupFailure catch (e) {
        lastFailure = e;
      } catch (_) {
        lastFailure = const PlaceLookupFailure(
          'Could not reach the places service. Check the connection.',
        );
      }
    }

    // Every source failed outright: report it, so the screen can say so.
    if (lastFailure != null) throw lastFailure;

    // Every source answered, and all of them had nothing. That is a real
    // answer about a quiet neighbourhood, not an error.
    return const [];
  }
}
