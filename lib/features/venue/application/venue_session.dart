import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/places_config.dart';
import '../../../data/local/device_identity.dart';
import '../../room/application/room_session.dart';
import '../data/chained_place_provider.dart';
import '../data/google_places_provider.dart';
import '../data/nominatim_place_provider.dart';
import '../data/overpass_place_provider.dart';
import '../data/location_source.dart';
import '../data/venue_repository.dart';
import '../domain/place_provider.dart';
import '../domain/venue_models.dart';

/// How far to look. From the owner's decision, VENUES.md §12.
const searchRadiusM = 5000;

/// The ballot is capped because a 5 km radius in a city centre returns
/// hundreds of restaurants, and a ballot of hundreds is not a ballot.
const maxCandidates = 20;

/// Which place provider the app uses.
///
/// Real places when the build carries a key, invented ones otherwise. That
/// fallback is the useful part: a debug build and the test suite never touch
/// the network or spend anything, and a release built without the key shows
/// fake restaurants rather than an error at a dinner table.
/// Google when the build carries a key, OpenStreetMap otherwise.
///
/// OSM is the default rather than the fake list because a fake list ignores
/// where you are: the owner opened this in Coimbatore and was offered
/// restaurants in Chennai. Free, no key, no billing — it just works, at the
/// cost of no ratings and thinner coverage outside cities.
final placeProviderProvider = Provider<PlaceProvider>((ref) {
  if (PlacesConfig.isConfigured) {
    final google = GooglePlacesProvider();
    // These own an http.Client, which holds sockets open until closed.
    ref.onDispose(google.close);
    return google;
  }
  // Free sources, chained. Overpass first because a purpose-built POI query
  // gives the better list; Nominatim behind it because it is a different
  // service on the same data, so an Overpass outage — which happened on 11
  // Nov, on every mirror at once — no longer empties the ballot. Nominatim
  // also resolves street names Overpass can only report when mapped.
  final overpass = OverpassPlaceProvider();
  final nominatim = NominatimPlaceProvider();
  ref.onDispose(overpass.close);
  ref.onDispose(nominatim.close);
  return ChainedPlaceProvider([overpass, nominatim]);
});

class VenueSessionState {
  const VenueSessionState({
    this.candidates = const [],
    this.votes = const [],
    this.searching = false,
    this.error,
    this.decidedVenueId,
  });

  final List<VenueCandidate> candidates;
  final List<VenueVote> votes;
  final bool searching;
  final String? error;

  /// The venue the host locked in.
  ///
  /// Distinct from `ballot.winner`, which is *computed* from the votes and
  /// changes as people tap. This is a *decision* — a fact somebody committed
  /// to, which the host may make against the vote. Storing it is not the same
  /// as storing the tally result, and the two must not be conflated.
  final String? decidedVenueId;

  VenueBallot get ballot =>
      VenueBallot(candidates: candidates, votes: votes);

  bool get hasCandidates => candidates.isNotEmpty;

  VenueCandidate? get decided => decidedVenueId == null
      ? null
      : candidates.where((c) => c.id == decidedVenueId).firstOrNull;

  VenueSessionState copyWith({
    List<VenueCandidate>? candidates,
    List<VenueVote>? votes,
    bool? searching,
    String? error,
    String? decidedVenueId,
    bool clearError = false,
    bool clearDecision = false,
  }) {
    return VenueSessionState(
      candidates: candidates ?? this.candidates,
      votes: votes ?? this.votes,
      searching: searching ?? this.searching,
      error: clearError ? null : (error ?? this.error),
      decidedVenueId:
          clearDecision ? null : (decidedVenueId ?? this.decidedVenueId),
    );
  }
}

/// Finding somewhere to eat, and the table's vote on it.
///
/// Works in two modes, deliberately:
///
///   * **At a table** (a room code exists) — candidates and votes live in
///     Supabase and stream to every phone, including guests on the web page.
///   * **Alone** (no room) — everything is held in memory on this phone. Still
///     useful: one person deciding where to eat is the common case for someone
///     who just opened the app, and making them host a table first would be
///     friction for no reason.
///
/// The [VenueBallot] domain object does not know or care which mode it is in,
/// which is why there is no second code path for the tally or the winner.
class VenueSession extends Notifier<VenueSessionState> {
  StreamSubscription<List<VenueCandidate>>? _candidateSub;
  StreamSubscription<List<VenueVote>>? _voteSub;
  String? _code;

  VenueRepo get _repo => ref.read(venueRepositoryProvider);

  bool get isLive => _code != null;

  @override
  VenueSessionState build() {
    ref.onDispose(_detach);

    // Joining or leaving a table is a new ballot, so resetting the state here
    // is correct rather than merely convenient. Selecting on the code alone
    // keeps this from re-running on every heartbeat.
    final code = ref.watch(roomSessionProvider.select((s) => s.code));
    _attach(code);

    // A decision made on the host's phone has to reach everyone else's. This
    // is a listen rather than a watch because it must update the state, not
    // rebuild and wipe it.
    ref.listen(
      roomSessionProvider
          .select((s) => s.snapshot?.room.decidedVenueId),
      (_, next) {
        // Guard on the code: with no room the selector is always null, and
        // without this a solo decision would be cleared the moment anything
        // else in the room session changed.
        if (_code == null) return;
        if (next == null) {
          if (state.decidedVenueId != null) {
            state = state.copyWith(clearDecision: true);
          }
        } else if (next != state.decidedVenueId) {
          state = state.copyWith(decidedVenueId: next);
        }
      },
    );

    return const VenueSessionState();
  }

  void _attach(String? code) {
    _detach();
    _code = code;
    if (code == null) return;

    _candidateSub = _repo.watchCandidates(code).listen(
          (rows) => state = state.copyWith(candidates: rows),
          // A dropped stream must not look like an empty restaurant list.
          onError: (Object e) => state = state.copyWith(error: '$e'),
        );
    _voteSub = _repo.watchVotes(code).listen(
          (rows) => state = state.copyWith(votes: rows),
          onError: (Object e) => state = state.copyWith(error: '$e'),
        );
  }

  void _detach() {
    _candidateSub?.cancel();
    _voteSub?.cancel();
    _candidateSub = null;
    _voteSub = null;
  }

  Future<String> _deviceId() => ref.read(deviceIdentityProvider).id();

  /// Look for restaurants near this phone and put them on the ballot.
  Future<void> search() async {
    if (state.searching) return;
    state = state.copyWith(searching: true, clearError: true);

    try {
      final at = await ref.read(locationSourceProvider).current();
      final places = await ref.read(placeProviderProvider).nearby(
            lat: at.lat,
            lng: at.lng,
            radiusM: searchRadiusM,
            limit: maxCandidates,
          );

      if (places.isEmpty) {
        state = state.copyWith(
          searching: false,
          error: 'Nothing found within 5 km. Pick somewhere yourselves.',
        );
        return;
      }

      final code = _code;
      if (code != null) {
        // The rows come back through the stream, which is also how every
        // other phone at the table gets them. No local shortcut, so the host
        // sees exactly what the guests see.
        await _repo.publishCandidates(code: code, places: places);
        state = state.copyWith(searching: false);
      } else {
        state = state.copyWith(
          searching: false,
          candidates: [
            for (final p in places)
              VenueCandidate(
                // No database row offline, so the provider's id is the id.
                id: p.placeId,
                placeId: p.placeId,
                name: p.name,
                address: p.address,
                lat: p.lat,
                lng: p.lng,
                distanceM: p.distanceM,
                rating: p.rating,
              ),
          ],
        );
      }
    } on LocationUnavailable catch (e) {
      state = state.copyWith(searching: false, error: e.message);
    } on PlaceLookupFailure catch (e) {
      state = state.copyWith(searching: false, error: e.message);
    } on VenueUnavailable catch (e) {
      state = state.copyWith(searching: false, error: e.message);
    } catch (_) {
      state = state.copyWith(
        searching: false,
        error: 'Could not look up places. Check the connection.',
      );
    }
  }

  /// Approve or un-approve one place for this phone.
  Future<void> toggle(String venueId) async {
    final deviceId = await _deviceId();
    final approved = state.ballot.isApprovedBy(venueId, deviceId);
    final code = _code;

    if (code == null) {
      final votes = [...state.votes];
      if (approved) {
        votes.removeWhere(
          (v) => v.venueId == venueId && v.deviceId == deviceId,
        );
      } else {
        votes.add(VenueVote(venueId: venueId, deviceId: deviceId));
      }
      state = state.copyWith(votes: votes, clearError: true);
      return;
    }

    try {
      await _repo.setApproval(
        code: code,
        venueId: venueId,
        deviceId: deviceId,
        approve: !approved,
      );
    } on VenueUnavailable catch (e) {
      state = state.copyWith(error: e.message);
    } catch (_) {
      state = state.copyWith(error: 'Vote did not save. Try again.');
    }
  }

  /// Settle it. Normally the leading venue, but the host may override — and
  /// must be able to, because the app can be wrong about what is open.
  Future<void> lockIn(String venueId) async {
    final code = _code;
    if (code == null) {
      state = state.copyWith(decidedVenueId: venueId, clearError: true);
      return;
    }
    try {
      await _repo.setDecidedVenue(code: code, venueId: venueId);
      state = state.copyWith(decidedVenueId: venueId, clearError: true);
    } catch (_) {
      state = state.copyWith(error: 'Could not share that decision.');
    }
  }

  /// Reopen the vote.
  Future<void> reopen() async {
    final code = _code;
    if (code == null) {
      state = state.copyWith(clearDecision: true, clearError: true);
      return;
    }
    try {
      await _repo.setDecidedVenue(code: code, venueId: null);
      state = state.copyWith(clearDecision: true, clearError: true);
    } catch (_) {
      state = state.copyWith(error: 'Could not reopen the vote.');
    }
  }

  /// Throw the list away and look again — the table moved, or the first
  /// search was from the wrong place.
  Future<void> startOver() async {
    final code = _code;
    if (code != null) {
      try {
        await _repo.clearBallot(code);
      } catch (_) {
        state = state.copyWith(error: 'Could not clear the list.');
        return;
      }
    }
    state = const VenueSessionState();
    await search();
  }

  void dismissError() => state = state.copyWith(clearError: true);
}

final venueSessionProvider =
    NotifierProvider<VenueSession, VenueSessionState>(VenueSession.new);
