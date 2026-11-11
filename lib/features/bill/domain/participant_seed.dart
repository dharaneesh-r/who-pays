/// Who is in the split, as the data trickles in.
///
/// Spec: VENUES.md §15.
///
/// This exists as a pure function because the rule is fiddly and got it wrong
/// once. The split screen learns who is at the table from two sources that
/// arrive in an unpredictable order — the saved player name (from
/// SharedPreferences) and the room's player list (from Supabase) — and seeding
/// once and for all meant that at a real table, where the snapshot often lands
/// a frame after the name, the split showed one person and five people were
/// told they owed nothing.
///
/// The rules, in order:
///
///   1. Once the user has touched the list, it is theirs. Never overwrite it.
///   2. The room's list beats the solo fallback, even if the fallback got
///      there first.
///   3. The room's list is only accepted once, so a later heartbeat cannot
///      silently undo an edit-free reorder.
///   4. An empty list is not an answer; it leaves things as they are.
///
/// Returns the names to seed with, or null to leave the list alone.
List<String>? seedParticipants({
  required List<String> candidate,
  required bool fromTable,
  required bool alreadySeeded,
  required bool alreadySeededFromTable,
  required bool edited,
}) {
  // Rule 4: nothing to say.
  if (candidate.isEmpty) return null;

  // Rule 1: the user has the final word.
  if (edited) return null;

  // Rule 3: the table has already spoken.
  if (alreadySeededFromTable) return null;

  // Rule 2: only the table may replace an existing seed.
  if (alreadySeeded && !fromTable) return null;

  return candidate;
}
