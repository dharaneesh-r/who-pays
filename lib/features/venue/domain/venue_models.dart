/// Where the table is going to eat, and how it decides.
///
/// Spec: VENUES.md §12–§14.
///
/// The one rule that shapes this file: **the winner is computed, never
/// stored.** Every phone works it out from the same rows with the same
/// tie-break, exactly as `RoomSnapshot.loser` does. If the winner were
/// written to a column, two phones could read it mid-write and show different
/// restaurants to people sitting at the same table.
library;

/// A place as a provider describes it, before it belongs to any room.
class Place {
  const Place({
    required this.placeId,
    required this.name,
    this.address,
    this.lat,
    this.lng,
    this.distanceM,
    this.rating,
  });

  /// The provider's own identifier — a Google `place_id`, an OSM node id.
  /// Carried so the same restaurant can be recognised across rooms without
  /// trusting the display name, which providers reword.
  final String placeId;

  final String name;
  final String? address;
  final double? lat;
  final double? lng;

  /// Metres from the host's location fix.
  final int? distanceM;

  /// 0–5 where the provider has one. Used only to decide which candidates
  /// make the ballot, never to tell the table what is "best" — that is what
  /// the vote is for.
  final double? rating;
}

/// A candidate on one room's ballot: a [Place] that has been written to
/// `room_venues` and therefore has a stable row id to vote against.
class VenueCandidate {
  const VenueCandidate({
    required this.id,
    required this.placeId,
    required this.name,
    this.address,
    this.lat,
    this.lng,
    this.distanceM,
    this.rating,
  });

  final String id;
  final String placeId;
  final String name;
  final String? address;
  final double? lat;
  final double? lng;
  final int? distanceM;
  final double? rating;

  factory VenueCandidate.fromRow(Map<String, dynamic> row) {
    final rating = row['rating'];
    return VenueCandidate(
      id: row['id'] as String,
      placeId: row['place_id'] as String? ?? '',
      name: row['name'] as String? ?? '',
      address: row['address'] as String?,
      lat: (row['lat'] as num?)?.toDouble(),
      lng: (row['lng'] as num?)?.toDouble(),
      distanceM: (row['distance_m'] as num?)?.toInt(),
      // Postgres `numeric` arrives as String through PostgREST often enough
      // that parsing both forms is cheaper than discovering it on a device.
      rating: rating == null
          ? null
          : rating is num
              ? rating.toDouble()
              : double.tryParse(rating.toString()),
    );
  }
}

/// One approval: "this device is willing to go here."
///
/// There is no "no" vote. Absence of a row is the no, which is why a tally is
/// a plain count.
class VenueVote {
  const VenueVote({required this.venueId, required this.deviceId});

  final String venueId;
  final String deviceId;

  factory VenueVote.fromRow(Map<String, dynamic> row) => VenueVote(
        venueId: row['venue_id'] as String,
        deviceId: row['device_id'] as String,
      );
}

/// The ballot as this phone currently understands it.
///
/// Approval voting, one round: everybody taps every place they are willing to
/// go, and the most-approved place wins. Chosen over multi-round elimination
/// because a hungry table will not sit through six rounds of voting.
class VenueBallot {
  VenueBallot({
    required this.candidates,
    required List<VenueVote> votes,
  }) : _approvals = _index(votes);

  const VenueBallot.empty()
      : candidates = const [],
        _approvals = const {};

  final List<VenueCandidate> candidates;

  /// venue id → the devices that approved it. A set, so one phone tapping
  /// twice cannot inflate a count even if the database constraint is relaxed.
  final Map<String, Set<String>> _approvals;

  static Map<String, Set<String>> _index(List<VenueVote> votes) {
    final map = <String, Set<String>>{};
    for (final v in votes) {
      map.putIfAbsent(v.venueId, () => <String>{}).add(v.deviceId);
    }
    return map;
  }

  int approvalsFor(String venueId) => _approvals[venueId]?.length ?? 0;

  bool isApprovedBy(String venueId, String deviceId) =>
      _approvals[venueId]?.contains(deviceId) ?? false;

  /// Every place this device said yes to.
  Set<String> approvalsBy(String deviceId) => {
        for (final entry in _approvals.entries)
          if (entry.value.contains(deviceId)) entry.key,
      };

  /// How many people have voted at all. Shown so the host knows whether to
  /// wait before closing the ballot.
  int get votersCount =>
      _approvals.values.expand((devices) => devices).toSet().length;

  bool get hasAnyVote => _approvals.values.any((d) => d.isNotEmpty);

  /// Candidates best-first.
  ///
  /// Most approvals, then nearest, then name, then row id. The last two exist
  /// purely so the order is **total** — any two phones sorting the same rows
  /// must produce the same list, and ties on approvals are the common case
  /// early in a vote, not an edge case.
  List<VenueCandidate> get ranked {
    final list = [...candidates];
    list.sort(_compare);
    return list;
  }

  int _compare(VenueCandidate a, VenueCandidate b) {
    final byApprovals = approvalsFor(b.id).compareTo(approvalsFor(a.id));
    if (byApprovals != 0) return byApprovals;

    // Unknown distance sorts last rather than first: a place we cannot
    // locate should not win a tie against one we can.
    final ad = a.distanceM ?? _farAway;
    final bd = b.distanceM ?? _farAway;
    if (ad != bd) return ad.compareTo(bd);

    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (byName != 0) return byName;
    return a.id.compareTo(b.id);
  }

  static const _farAway = 1 << 30;

  /// Where the table is going, or null while nobody has voted.
  ///
  /// Null is meaningful: it means "no decision yet", and the host is offered
  /// the choice of reopening the vote or picking a place by hand. It must
  /// never silently resolve to the first restaurant in the list.
  VenueCandidate? get winner {
    if (candidates.isEmpty || !hasAnyVote) return null;
    return ranked.first;
  }

  /// The places to grey out and sink to the bottom — "the least selected will
  /// be removed".
  ///
  /// Only ever the joint-lowest, and only once there is a spread to speak of.
  /// While every candidate is level, nothing is trailing: dimming the whole
  /// ballot the moment one person votes would be absurd.
  Set<String> get trailing {
    if (candidates.length < 2 || !hasAnyVote) return const {};
    final counts = candidates.map((c) => approvalsFor(c.id)).toList();
    final min = counts.reduce((a, b) => a < b ? a : b);
    final max = counts.reduce((a, b) => a > b ? a : b);
    if (min == max) return const {};
    return {
      for (final c in candidates)
        if (approvalsFor(c.id) == min) c.id,
    };
  }
}
