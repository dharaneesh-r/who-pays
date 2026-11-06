# Final 4 Candidates

Date: 2026-11-06. All earlier plan files deleted.
Criteria: fun, emotional, unique, minimalist, small APK, ages 18–60, works in India.

---

## 1. REWIND  ⭐ PICK

- A quiz game built from the photos already on your phone.
- Asks what year, which city, who's missing, which photo came first — 5 photos, 90 seconds, a score.
- Family Mode: one person shares an album link, everyone guesses the same photos, live leaderboard.
- People use it because 40,000 dead photos become a game, and the nostalgia hits hardest for older users.
- Proven demand (5 iPhone apps do this), zero presence on Play Store. ~15 MB, offline, one button.

## 2. ROOTED

- A garden where each plant is one real friend.
- The longer since you last spoke, the more that plant wilts.
- One tap on a wilting plant opens WhatsApp or the dialler.
- People use it because nobody loses friends on purpose — they lose them to 6 months of silence.
- No backend, no account, no feed. ~8 MB, one screen.

## 3. TABLE

- A game for a restaurant table: all phones in the middle, app locks them into one timer.
- First person to pick up their phone loses — pays the bill, buys the round.
- Keeps a running tally of who cracks first across the group.
- People use it because phones ruin meals and nobody wants to be the one who says it.
- Every game forces 3–8 friends to install it on the spot. ~10 MB.

## 4. VOICES

- One question a day for your parents, answered by voice.
- They press one button and talk — no typing, no literacy, any language.
- After a year: 300 recordings in their real voice, exportable as an audio book or printed memoir.
- People use it because everyone eventually says "I wish I'd asked them more."
- Only one here with real money in it (₹999–2,999 memoir), but payoff is at month 6, not minute 1.

---

## Decision

**Build Rewind.** Fun, emotional, unique on Android, tiny, one button, better the older the user is.
Rooted second (costs nothing to build, no backend). Table as a cheap viral test. Voices last.

## Rewind — stack

- Flutter + Riverpod + go_router, Drift (SQLite) for the photo index and scores.
- `photo_manager` + `exif` + custom filename-date resolver (WhatsApp strips EXIF — this is the moat).
- `google_mlkit_face_detection` for "who's missing" (Pro only).
- `screenshot` + `share_plus` for score cards. Supabase only for Family Mode rooms.
- ₹199 / $3.99 one-time unlock. Free tier: 3 rounds a day.

## Rewind — 4-week v1

1. Gallery indexer + photo date-confidence resolver.
2. 5 question types + scoring + 90-second round loop.
3. Score card, forgotten-photo-of-the-day, permission/trust flow.
4. Family Mode, paywall, Play Store internal test.
