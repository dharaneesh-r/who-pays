# What is still unfinished in the app

Code only. Account setup is in [ADMOB_SETUP.md](ADMOB_SETUP.md); device testing
is in [DEVICE_TEST.md](DEVICE_TEST.md).

Audited against the source on 2026-11-07, not from memory.

---

## 🔴 Broken or misleading — fix before anyone sees it

| # | What | Why it matters |
|---|---|---|
| 1 | **A table can only play one round.** `RoomSession.backToLobby()` exists but nothing calls it. After a room round ends, "PLAY AGAIN" restarts only the local phone — the room stays in `settling` and the other phones never follow | The multiplayer loop is a dead end. The *second* round is when a group decides they like this |
| 2 | **Room status never reaches `running` or `finished`.** Only `lobby` and `settling` are ever written | Nothing is visibly wrong yet, but the status field is half-wired and anything built on it will be subtly wrong |
| 3 | **The paywall advertises "Custom stakes", which do not exist.** `Stake.custom` is excluded from the setup UI (`if (stake != Stake.custom)`) and there is no text field | Charging ₹149 for a listed feature that is not there is a refund request and a 1-star review |
| 4 | **Four paid card packs are sold but not written.** `ProductIds` lists `pack_couples`, `pack_team`, `pack_deep_talk`, `pack_desi`; only `friends.json` and `family.json` exist | Same problem as #3 — purchasable, undeliverable |
| 5 | **Pack entitlements are never enforced.** `Entitlements.hasPack()` is written and tested but called from nowhere | Once packs exist, they would be free to everyone |

## 🟠 Real gaps — needed for a credible v1

| # | What | Notes |
|---|---|---|
| 6 | **No settings screen at all** | No way to change your name, mute the siren, or restore purchases outside the paywall |
| 7 | **Solo rounds are always saved as "You"** | `setPlayerName` is only called from the join screen, so the stats leaderboard is meaningless until you have joined a room once |
| 8 | **No pack picker** | `selectedPackProvider` exists and is wired into the deck, but nothing ever sets it — the first pack always wins |
| 9 | **Streak has no reminder** | The streak is the only daily-retention mechanic, and nothing reminds anyone. `flutter_local_notifications` is not even a dependency |
| 10 | **Focus Duel mode not built** | Listed in [CONTEXT.md](CONTEXT.md) as the async mode that gives weekday usage |
| 11 | **Errors are invisible in the lobby** | `RoomSessionState.error` is only rendered on the join and host screens. A realtime failure mid-round shows the user nothing |
| 12 | **Players who quit mid-round are never cleaned up** | Their row stays "still in" forever, so `isDecided` never becomes true for that table |
| 13 | **No way to rejoin a room after the app is killed** | The device id persists and the server would accept a rejoin, but there is no UI for it |

## 🟡 Policy and platform — blocks publishing, not playing

| # | What | Notes |
|---|---|---|
| 14 | **UMP consent SDK not integrated** | Google requires a certified consent platform to serve ads in the EEA/UK. Fine for an India-only launch; required before the US/UK push the revenue plan depends on |
| 15 | **Firebase not wired** — no Analytics, Crashlytics or Remote Config | Remote Config is the documented way to tune detection thresholds without shipping a release. Right now every threshold change needs a full store update |
| 16 | **No privacy policy, in app or hosted** | Mandatory for any ad-serving app on Play |
| 17 | **iOS is unconfigured** | The `ios/` folder exists but has no camera or motion usage strings in `Info.plist`, no AdMob id, and has never been built |

## 🟢 Test coverage

| # | What | Notes |
|---|---|---|
| 18 | **No widget or integration tests** | 83 tests, all of pure logic. `GameController` and `RoomSession` — the two pieces holding the game together — have none |
| 19 | **Detection is unverified on hardware** | The single biggest risk. See [DEVICE_TEST.md](DEVICE_TEST.md) |

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
