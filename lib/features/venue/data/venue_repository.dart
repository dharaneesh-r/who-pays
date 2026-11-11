import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/remote/supabase_init.dart';
import '../domain/venue_models.dart';

/// What the ballot needs from the server, as an interface so the session can
/// be tested without a network.
///
/// Spec: VENUES.md §12–§13. Mirrors the shape of `RoomRepo` deliberately —
/// same stream-per-table pattern, same "the server stores rows, the phones
/// decide" split.
abstract interface class VenueRepo {
  /// Write the candidate list for a room. Called **once, by the host**.
  Future<void> publishCandidates({
    required String code,
    required List<Place> places,
  });

  Stream<List<VenueCandidate>> watchCandidates(String code);
  Stream<List<VenueVote>> watchVotes(String code);

  /// Add or remove one approval. [approve] false deletes the row — there is no
  /// "no" vote, so un-tapping is a delete, which keeps a tally a plain count.
  Future<void> setApproval({
    required String code,
    required String venueId,
    required String deviceId,
    required bool approve,
  });

  /// Record the venue the host settled on, or null to reopen the vote.
  ///
  /// This is **not** the computed tally winner — that is worked out
  /// identically on every phone and never stored. This is a decision somebody
  /// committed to, which the host may make against the vote when the app is
  /// wrong about what is open. Storing a decision and storing a tally result
  /// are different things.
  Future<void> setDecidedVenue({
    required String code,
    required String? venueId,
  });

  /// Drop every candidate and vote for a room, so the host can search again
  /// from a different spot without stale restaurants on the ballot.
  Future<void> clearBallot(String code);
}

class VenueRepository implements VenueRepo {
  SupabaseClient get _db => Supabase.instance.client;

  void _requireOnline() {
    if (!supabaseReady) {
      throw const VenueUnavailable('Not connected — cannot vote right now.');
    }
  }

  @override
  Future<void> publishCandidates({
    required String code,
    required List<Place> places,
  }) async {
    _requireOnline();
    if (places.isEmpty) return;

    // Upsert rather than insert: a host who searches twice would otherwise
    // hit the (room_code, place_id) unique constraint and see a raw Postgres
    // error at a dinner table.
    await _db.from('room_venues').upsert(
      [
        for (final p in places)
          {
            'room_code': code,
            'place_id': p.placeId,
            'name': p.name,
            'address': p.address,
            'lat': p.lat,
            'lng': p.lng,
            'distance_m': p.distanceM,
            'rating': p.rating,
          },
      ],
      onConflict: 'room_code,place_id',
    );
  }

  @override
  Stream<List<VenueCandidate>> watchCandidates(String code) {
    return _db
        .from('room_venues')
        .stream(primaryKey: ['id'])
        .eq('room_code', code)
        .map((rows) => rows.map(VenueCandidate.fromRow).toList());
  }

  @override
  Stream<List<VenueVote>> watchVotes(String code) {
    return _db
        .from('venue_votes')
        .stream(primaryKey: ['id'])
        .eq('room_code', code)
        .map((rows) => rows.map(VenueVote.fromRow).toList());
  }

  @override
  Future<void> setApproval({
    required String code,
    required String venueId,
    required String deviceId,
    required bool approve,
  }) async {
    _requireOnline();

    if (!approve) {
      await _db
          .from('venue_votes')
          .delete()
          .eq('venue_id', venueId)
          .eq('device_id', deviceId);
      return;
    }

    // Idempotent: the unique constraint on (venue_id, device_id) means a
    // double-tap from a laggy connection cannot double-count.
    await _db.from('venue_votes').upsert(
      {
        'room_code': code,
        'venue_id': venueId,
        'device_id': deviceId,
      },
      onConflict: 'venue_id,device_id',
    );
  }

  @override
  Future<void> setDecidedVenue({
    required String code,
    required String? venueId,
  }) async {
    _requireOnline();
    await _db
        .from('rooms')
        .update({'decided_venue_id': venueId})
        .eq('code', code);
  }

  @override
  Future<void> clearBallot(String code) async {
    _requireOnline();
    // venue_votes cascades from room_venues, so deleting the candidates is
    // enough — but votes are deleted first anyway, because relying on a
    // cascade that a migration might not have applied is how rows get
    // orphaned.
    await _db.from('venue_votes').delete().eq('room_code', code);
    await _db.from('room_venues').delete().eq('room_code', code);
  }
}

class VenueUnavailable implements Exception {
  const VenueUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

final venueRepositoryProvider = Provider<VenueRepo>((_) => VenueRepository());
