# What is still unfinished in the app

Code only. Account setup is in [ADMOB_SETUP.md](ADMOB_SETUP.md); device testing
is in [DEVICE_TEST.md](DEVICE_TEST.md).

Audited against the source on 2026-11-07, not from memory.

---

## 🔴 Broken or misleading — fix before anyone sees it

| # | What | Why it matters |
|---|---|---|
| 1 | ~~A table can only play one round~~ **FIXED** | End-to-end testing showed worse: the round *restarted instantly* on being caught, so the result was never seen. The host now closes the round when decided, phones no longer auto-restart, and the host gets a NEXT ROUND button |
| 2 | ~~Room status never reaches `finished`~~ **FIXED** | The host now sets `finished` once one player is left. `running` is still unused |
| 3 | ~~Paywall advertises custom stakes that do not exist~~ **FIXED** | Built: a "something else" chip plus a text field, locked behind Pro so the paywall claim is real |
| 4 | ~~Four paid card packs sold but not written~~ **FIXED** | Built: Couples, Team Lunch, Deep Talk and Desi, 15–18 prompts each. A test now fails if a product is on sale without a pack file |
| 5 | ~~Pack entitlements never enforced~~ **FIXED** | `hasPack()` now gates the picker and the deck; locked packs show a padlock and open the paywall |

## 🟠 Real gaps — needed for a credible v1

| # | What | Notes |
|---|---|---|
| 6 | ~~No settings screen~~ **FIXED** | Built: name, siren toggle, Pro status, restore purchases |
| 7 | ~~Solo rounds always saved as "You"~~ **FIXED** | Name is now set in Settings and used for solo rounds. Home shows "Set your name" in amber until one is saved |
| 8 | ~~No pack picker~~ **FIXED** | Built in the setup screen as "Talk about…", with padlocks on paid packs |
| 9 | ~~Streak has no reminder~~ **FIXED** | A 7:30pm notification, only while a streak is alive and today is unplayed. Toggle in Settings, inexact alarms so no special permission is needed |
| 10 | ~~Focus Duel mode not built~~ **BUILT** | Async daily challenge: play whenever, longest round that day wins. Needs `supabase/migration_duels.sql` |
| 11 | ~~Errors invisible in the lobby~~ **FIXED** | A dismissible banner now shows room errors in the lobby and during a round |
| 12 | ~~Players who quit are never cleaned up~~ **FIXED** | Phones heartbeat `last_seen` every 15s; anyone quiet for 45s drops out of the standings and no longer blocks the round. Needs `supabase/migration_presence.sql` |
| 13 | ~~No way to rejoin after the app is killed~~ **FIXED** | Home shows a green REJOIN button when the saved table still exists |

## 🟡 Policy and platform — blocks publishing, not playing

| # | What | Notes |
|---|---|---|
| 14 | ~~UMP consent SDK not integrated~~ **FIXED** | Resolved before the first ad request; outside the EEA/UK it shows nothing. "Ad privacy options" appears in Settings only where required. The GDPR message must still be published in the AdMob console |
| 15 | **Firebase not wired** — no Analytics, Crashlytics or Remote Config | Remote Config is the documented way to tune detection thresholds without shipping a release. Right now every threshold change needs a full store update |
| 16 | ~~No privacy policy~~ **WRITTEN** | [web_guest/privacy.html](web_guest/privacy.html), linked in Settings. **Still needs hosting** on Cloudflare before the Play listing can reference it |
| 17 | **iOS is unconfigured** | The `ios/` folder exists but has no camera or motion usage strings in `Info.plist`, no AdMob id, and has never been built |

## 🔵 Venue voting and bill splitting — new, 11 Nov 2026

Spec and audit: [VENUES.md](VENUES.md) §12–§17.

| # | What | Notes |
|---|---|---|
| 20 | **Location is gated off** | `GeolocatorLocationSource` is **built** (coarse, one fix, 15 s limit) but unused: needs `ACCESS_COARSE_LOCATION` uncommented in the manifest *and* `--dart-define=LOCATION=true`. Deliberate — declaring the permission restarts the Data Safety review, so it waits for the closed test. **Never run on a device** |
| 21 | **Places need a key** | `GooglePlacesProvider` is **built and tested** (16 tests against recorded response shapes). Without `--dart-define=PLACES_KEY=…` the app uses the six fake restaurants, so a debug build spends nothing. Still needs an API key, a billing account with a **hard quota cap**, and a first real call — no live place data has ever been fetched |
| 22 | **`migration_venues.sql` not applied** | Voting silently does nothing until it is run in the Supabase SQL editor |
| 23 | ~~Guests cannot vote~~ **BUILT** | `web_guest/ballot.js` + a ballot in the lobby. The tally is tested against the Dart cases via `node --test test/guest_ballot_test.mjs` — not part of `flutter test`, so run it by hand. Degrades to hidden on a database without the migration |
| 24 | **Neither new screen has a widget test** | Domain, session and provider layers are covered; see #18. Both screens were walked by hand in Chrome on 11 Nov — search, vote, lock in, split with 1/2/3 people all correct — but that is a one-off, not a regression test |
| 26 | **Add-person field loses focus after each name** | Adding five people means five taps on the same box. A `FocusNode` + `requestFocus()` is in place, **but unverified**: browsers block programmatic focus outside a user gesture, so the fix cannot be confirmed on web, and the defect itself may be web-only. Check it on a phone |
| 25 | ~~Android builds cannot be verified~~ **FIXED** | Cause was the `ndkVersion` pin: c4eea3c bumped it to `28.2.13676358`, which was never installed, so Gradle failed while configuring `:app`. Installed it with `sdkmanager "ndk;28.2.13676358"`. `cmdline-tools` and the licences were never the problem. See README, "The NDK pin" |

## 🟢 Test coverage

| # | What | Notes |
|---|---|---|
| 18 | ~~Controllers had no tests~~ **FIXED** | 12 GameController + 14 RoomSession tests via injectable Detector, Alarm and RoomRepo interfaces. Widget tests still absent |
| 19 | **Detection partly verified on hardware** (Realme RMX2030, Android 10, BMI160). Arming, the leave-app catch, the siren and the full round flow all work. **Still untested: physical pick-up, rotation, table-bump false positives** — those need a human moving the phone | See [DEVICE_TEST.md](DEVICE_TEST.md) |

---

## Suggested order

1. **Device test first** (#19). If the thresholds are wrong, some of the above changes anyway.
2. **#1 and #2** — make a table able to play more than one round.
3. **#3 and #4** — either build custom stakes and the four packs, or remove both claims from the paywall. Removing is honest and takes ten minutes.
4. **#6, #7, #8** — a small settings screen closes three gaps at once.
5. **#15** — Firebase Remote Config, so thresholds can be tuned from tester feedback without a release. Do this *before* the 12-tester closed test, or you waste it.
6. **#16** then publish.
7. **#9, #10, #13** — retention features, after launch.
8. **#14** before any Europe or US push.
9. **#17** only if iOS is worth it.

---

## Fixed after on-device testing (2026-11-07)

Bugs that only appeared once the app ran on real hardware and a real browser:

| What | How it showed up |
|---|---|
| Guest page 404'd on its own script | `./app.js` resolved to `/j/app.js` — **every QR scan** landed on a dead page |
| Guest stuck in lobby if the round had started | `followStatus()` only ran on realtime *changes*, never after joining |
| Room round restarted the instant it ended | Room stayed in `settling`, so the result screen was never seen and the timer ran forever |
| "So you pays the bill" | Third-person stake label used where second person was needed |
| "You has cracked first 6 times" | The fallback name is a pronoun |
| Paywall said "That's today's free rounds" when you tapped a locked pack | One headline for three different reasons |
| DONE stranded the player on the setup screen | The ad returned after `reset()` had unmounted the widget, so `context.pop()` was skipped |
| Next round could start behind a full-screen ad | `InterstitialAd.show()` resolves when the ad *appears*, not when it is dismissed |

---

## Repair pass — 7 Nov 2026

### Fixed in code

| What | Why it mattered |
|---|---|
| Join no longer requires `last_seen` | The app sent the column on every join; the live database does not have it, so PostgREST rejected the whole request and **nobody could join a table at all**. Now it retries without the column and carries on. |
| Heartbeat stops after one refusal | It would otherwise retry a guaranteed-failing write every 15s for the whole round. |
| AdMob app id is a build placeholder | It was hardcoded to Google's test id in the manifest, where `--dart-define` cannot reach it. Now `-PadmobAppId=...` at build time. |
| `tools/make_keystore.sh` | Release builds were silently falling back to the **debug** signing key, which Play rejects outright. |
| `supabase/migration_fix.sql` | One idempotent script: the missing column, the standings view, and the four purge jobs that had never been scheduled. |

Tests: 143 passing (5 new, covering the missing-column predicate).

### Still needs an account, not code

1. Run `supabase/migration_fix.sql` — **check the project ref is `uhslpvssmpmhtmlmncxo` first.** The previous run reported success against what was almost certainly a different project.
2. `bash tools/make_keystore.sh`, then back both files up off this machine.
3. Deploy `web_guest/` — `who-pays.pages.dev` does not resolve, so the privacy URL and every QR code are dead.
4. Real AdMob ids, passed at build time.
5. Record a sensor trace so the detector thresholds can be fitted (`DETECTOR_TUNING.md`).

---

## RLS lockdown — 7 Nov 2026

**Was:** both room tables were `for all to anon using (true)`. The publishable
key ships in the app and is served in `web_guest/app.js`, so anyone could
delete any table or edit anyone's result. Table codes are 4 characters from a
24-letter alphabet — about 331,000 combinations, trivially enumerated.

**Now:** every client sends an `x-device-id` header and the policies only
allow writes to rows carrying that id.

| Table | select | insert | update / delete |
|---|---|---|---|
| `rooms` | anyone | yourself as host | host only |
| `room_players` | anyone | your own row | your own row |

"Play again" clears every player's row, which per-row policies rightly forbid,
so it moved to `reset_round()` — a definer function that checks the caller is
that room's host.

**What this is not.** It is not authentication. A caller can put any device id
in the header. It raises the bar from "guess a 4-letter code" to "already know
someone's random UUID", which kills enumeration but not targeted
impersonation. Real auth means anonymous sign-in and `auth.uid()` — a bigger
change than belongs in launch week, and worth doing later.

**Run order matters:** `migration_fix.sql` first, then `migration_rls.sql`.
Both are idempotent. The app tolerates either not having run yet — a missing
`last_seen` column and a missing `reset_round` function both fall back.

**Not yet tightened:** `duels` and `duel_scores` still use blanket policies.
Lower risk (no destructive operation exposed), but they should get the same
treatment eventually.
