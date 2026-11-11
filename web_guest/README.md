# Guest join page

The viral unlock: the host has the app, everyone else scans the QR and lands
here. No install, no account.

## Deploy (free)

1. Cloudflare dashboard → **Workers & Pages** → **Create** → **Pages** →
   **Upload assets**.
2. Upload this folder (`index.html`, `app.js`, `ballot.js`,
   `_redirects`).
3. Project name `who-pays` → the site is served at `https://who-pays.pages.dev`.

That hostname must match `JoinLink.host` in the app, which defaults to
`https://who-pays.pages.dev`. If you use a different name, rebuild the app with:

```bash
flutter build apk --dart-define=JOIN_HOST=https://your-name.pages.dev
```

## How it differs from the app

| | App | Guest page |
|---|---|---|
| Accelerometer / gyroscope | Yes | Yes, via DeviceMotion |
| Detects leaving to another app | Yes | Yes, via Page Visibility |
| Detects screen unlock | Yes | **No** — a browser cannot see it |
| Siren on catch | Yes | No |
| History, streak, stats | Yes | No |
| Voting on where to eat | Yes | **Yes** |
| Finding places nearby | Yes, host only | No — the host searches, guests vote |
| Locking in the venue | Host only | No |

The guest detector is a direct port of `PickupDetector`, with the same
thresholds. **If `DetectionConfig` changes in the app, `CFG` in `app.js` must
change too** — otherwise app players and web players are playing different
games.

## Where to eat

`ballot.js` is the voting maths, ported from `VenueBallot` in
`lib/features/venue/domain/venue_models.dart`: approval voting, one round, with
the same ranking and the same tie-break. **If the tie-break changes in the app
it must change here too**, or the host's phone and a guest's browser can
disagree about which restaurant won.

Unlike the detector, this port is tested against the same cases as the Dart:

```bash
node --test test/guest_ballot_test.mjs
```

That is not part of `flutter test` — it is JavaScript, and there is no node
runner wired up. Run it by hand when either side changes.

The page keeps working on a database without `supabase/migration_venues.sql`
applied: the first "no such table" answer sets `votingSupported = false` and
the whole section stays hidden.

## iOS note

iOS 13+ refuses motion events until the user makes a gesture, so sensors are
requested on the join tap. If someone joins and the clock never arms, they
likely dismissed that permission prompt — reloading and re-joining re-asks.
