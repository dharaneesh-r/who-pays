/// Who lost, as the split screen should understand it.
///
/// Spec: VENUES.md §15.
///
/// A pure function because the screen got this wrong, and the way it was wrong
/// was invisible to every unit test: the tests handed `BillSplit.compute` a
/// loser name directly, so nothing covered where that name comes from.
///
/// The bug, found on a real phone: in a **solo** round the screen read the
/// loser from the room snapshot, and solo play has no room. So someone who had
/// just been caught — siren, "So you pay the bill" on the previous screen —
/// opened the split and was told "nobody cracked, the bill splits evenly".
///
/// The rules:
///
///   1. At a table, the room decides. The loser is whoever cracked *first*,
///      which only the room can know, and this phone being caught says
///      nothing about whether it was first.
///   2. Alone, being caught *is* losing. There is nobody else to have been
///      faster.
///   3. Otherwise nobody lost — the round ran to time.
String? resolveLoser({
  required String? roomLoser,
  required bool inRoom,
  required bool caught,
  required String? myName,
}) {
  // Rule 1. Deliberately returns the room's answer even when it is null: a
  // table where nobody has cracked yet has no loser, and this phone's own
  // state must not override that.
  if (inRoom) return roomLoser;

  // Rule 2.
  if (caught) return myName ?? 'You';

  // Rule 3.
  return null;
}
