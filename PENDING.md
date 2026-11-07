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
| 9 | **Streak has no reminder** | The streak is the only daily-retention mechanic, and nothing reminds anyone. `flutter_local_notifications` is not even a dependency |
| 10 | **Focus Duel mode not built** | Listed in [CONTEXT.md](CONTEXT.md) as the async mode that gives weekday usage |
| 11 | ~~Errors invisible in the lobby~~ **FIXED** | A dismissible banner now shows room errors in the lobby and during a round |
| 12 | ~~Players who quit are never cleaned up~~ **FIXED** | Phones heartbeat `last_seen` every 15s; anyone quiet for 45s drops out of the standings and no longer blocks the round. Needs `supabase/migration_presence.sql` |
| 13 | ~~No way to rejoin after the app is killed~~ **FIXED** | Home shows a green REJOIN button when the saved table still exists |

## 🟡 Policy and platform — blocks publishing, not playing

| # | What | Notes |
|---|---|---|
| 14 | **UMP consent SDK not integrated** | Google requires a certified consent platform to serve ads in the EEA/UK. Fine for an India-only launch; required before the US/UK push the revenue plan depends on |
| 15 | **Firebase not wired** — no Analytics, Crashlytics or Remote Config | Remote Config is the documented way to tune detection thresholds without shipping a release. Right now every threshold change needs a full store update |
| 16 | ~~No privacy policy~~ **WRITTEN** | [web_guest/privacy.html](web_guest/privacy.html), linked in Settings. **Still needs hosting** on Cloudflare before the Play listing can reference it |
| 17 | **iOS is unconfigured** | The `ios/` folder exists but has no camera or motion usage strings in `Info.plist`, no AdMob id, and has never been built |

## 🟢 Test coverage

| # | What | Notes |
|---|---|---|
| 18 | **No widget or integration tests** | 83 tests, all of pure logic. `GameController` and `RoomSession` — the two pieces holding the game together — have none |
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
