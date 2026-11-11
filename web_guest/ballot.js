// Where to eat — the voting maths, ported from the app.
//
// Spec: VENUES.md §12-§13. Approval voting, one round: tap every place you are
// willing to go, most approvals wins. There is no "no" vote — the absence of a
// row is the no, which is why a tally is a plain count.
//
// **This mirrors `VenueBallot` in
// lib/features/venue/domain/venue_models.dart.** If the ranking or the
// tie-break changes there, it must change here too, or the host's phone and
// the guests' browsers can disagree about which restaurant won — the exact
// failure the deterministic tie-break exists to prevent.
//
// It lives in its own file, with no DOM and no network, for one reason: it can
// then be run against the same cases as the Dart tests. The pick-up detector
// in app.js is a hand-synced copy and web_guest/README.md calls that out as a
// hazard; there is no reason to repeat it here.
//
//   node --test test/guest_ballot_test.mjs

/// Unknown distance sorts last rather than first: a place we cannot locate
/// should not win a tie against one we can.
export const FAR_AWAY = 1 << 30;

/// Counts DISTINCT devices, so one phone cannot stuff the ballot for its
/// favourite even if the unique constraint is ever relaxed.
export function approvalsFor(votes, venueId) {
  const devices = new Set();
  for (const v of votes) if (v.venue_id === venueId) devices.add(v.device_id);
  return devices.size;
}

export const isApprovedBy = (votes, venueId, deviceId) =>
  votes.some((v) => v.venue_id === venueId && v.device_id === deviceId);

/// How many people have voted at all — not how many votes were cast. One
/// person approving four places is still one voter.
export const votersCount = (votes) =>
  new Set(votes.map((v) => v.device_id)).size;

export const hasAnyVote = (votes) => votes.length > 0;

// Plain < and > rather than localeCompare: JavaScript compares UTF-16 code
// units here, which is what Dart's String.compareTo does. localeCompare would
// order some names differently from the app, and this is the final tie-break
// that keeps every screen agreeing.
const cmp = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

/// Candidates best-first: most approvals, then nearest, then name, then id.
///
/// The last two exist purely so the order is *total* — any two devices sorting
/// the same rows must produce the same list, and ties on approvals are the
/// common case early in a vote, not an edge case.
export function ranked(venues, votes) {
  return [...venues].sort((a, b) => {
    const byApprovals = approvalsFor(votes, b.id) - approvalsFor(votes, a.id);
    if (byApprovals !== 0) return byApprovals;

    const ad = a.distance_m ?? FAR_AWAY;
    const bd = b.distance_m ?? FAR_AWAY;
    if (ad !== bd) return ad - bd;

    const byName = cmp(
      (a.name || '').toLowerCase(),
      (b.name || '').toLowerCase(),
    );
    if (byName !== 0) return byName;
    return cmp(a.id, b.id);
  });
}

/// Where the table is going, or null while nobody has voted.
///
/// Null is meaningful: it means "no decision yet". It must never silently
/// resolve to the first restaurant in the list.
export function winner(venues, votes) {
  if (!venues.length || !hasAnyVote(votes)) return null;
  return ranked(venues, votes)[0];
}

/// The places to dim and sink — "the least selected will be removed".
///
/// Only ever the joint-lowest, and only once there is a spread. While every
/// candidate is level, nothing is trailing: dimming the whole ballot the
/// moment one person votes would be absurd.
export function trailing(venues, votes) {
  if (venues.length < 2 || !hasAnyVote(votes)) return new Set();
  const counts = venues.map((v) => approvalsFor(votes, v.id));
  const min = Math.min(...counts);
  const max = Math.max(...counts);
  if (min === max) return new Set();
  return new Set(
    venues
      .filter((v) => approvalsFor(votes, v.id) === min)
      .map((v) => v.id),
  );
}

/// Metres under a kilometre, then one decimal place. "1.2 km" is what a person
/// says; "1183 m" is what a sensor says.
export const distanceLabel = (m) =>
  m < 1000 ? `${m} m` : `${(m / 1000).toFixed(1)} km`;

/// Distance, rating and address, skipping whatever the provider did not give
/// us — real place data is full of holes, and an empty " · · " is worse than a
/// short line.
export function venueSubtitle(v) {
  const parts = [];
  if (v.distance_m != null) parts.push(distanceLabel(v.distance_m));
  if (v.rating != null) parts.push(`★ ${Number(v.rating).toFixed(1)}`);
  if (v.address && String(v.address).trim()) parts.push(String(v.address).trim());
  return parts.length ? parts.join('  ·  ') : 'No details';
}
