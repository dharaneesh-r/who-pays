# BUILD PHASES — "Who Pays?"

End-to-end phase list. Work phase by phase; each one ends in something you can actually test.
Context: [CONTEXT.md](CONTEXT.md)

---

## Overnight reality check

| Question | Honest answer |
|---|---|
| Can the whole app be built in one day? | No. ~17 hours of work total. |
| What **can** be done in one long day? | **Phases 0–6 (~9 h) = a fully playable multiplayer game on 3 real phones.** That is a real, demoable product. |
| What must wait? | Phases 7–11 (polish, money, guest web, release build) — a second day. |
| What *cannot* be compressed at all? | Play Store: $25 signup, then a **12-tester closed test for 14 calendar days** before production. Start that clock the day the AAB builds. Also: detection-threshold tuning needs days of real-world use. |

**Target for tonight: end of Phase 6.** If you're flying, continue into 7–8.

---

## Phases

| # | Phase | Time | Deliverable / checkpoint | Priority |
|---|---|---|---|---|
| **0** | **Project setup** | 30 m | `flutter create`, deps in pubspec, feature folders, git init, app runs on a real phone | MUST |
| **1** | **Pick-up detector** | 2 h | A debug screen showing live accel/gyro values + a state machine: `settling → armed → CAUGHT`. Put the phone down, pick it up, it fires. **This is the product — do not rush it.** | MUST |
| **2** | **Single-player game loop** | 1.5 h | Lobby → set stake → "put phones down" → 5-sec arm countdown → running timer → caught → result screen. Fully local, no network. **Playable game exists at the end of this phase.** | MUST |
| **3** | **Siren, haptics, wakelock** | 1 h | Loud siren + vibration on catch, screen stays awake, big readable timer. The sound *is* the shame mechanic. | MUST |
| **4** | **Local storage** | 45 m | Drift (SQLite): game history, per-player tally, "cracked first 7× this month" | MUST |
| **5** | **Supabase rooms + realtime** | 2.5 h | Schema (rooms, players, events), create room with 4-letter code, join by code, presence, catch broadcast to all phones, live leaderboard | MUST |
| **6** | **QR join** | 45 m | Host shows QR (`qr_flutter`), guest scans (`mobile_scanner`) → joins room. **Test with 3 phones at a real table.** | MUST |
| **7** | **Result card + share** | 1 h | Screenshot-to-image result card → `share_plus` → WhatsApp. This is your growth loop. | HIGH |
| **8** | **Table Talk cards** | 45 m | JSON card packs, prompt rotates on screen while the timer runs | HIGH |
| **9** | **Streak mode** | 1 h | Daily phone-free dinner streak + local notification reminder. Only real D30 lever. | MEDIUM |
| **10** | **Guest web join page** | 2 h | Static page on Cloudflare Pages: DeviceMotion + Page Visibility, joins the same Supabase room, no install. Keep it under 50 KB for restaurant wifi. | MEDIUM — but it's the viral unlock |
| **11** | **Money + analytics + release** | 2 h | AdMob test ads, `in_app_purchase` Pro unlock, Firebase Analytics + Crashlytics, app icon, splash, package name, keystore, signed AAB | MUST before launch |

**Totals:** Phases 0–6 = **9 h** · Phases 7–11 = **7 h 45 m** · Full build ≈ **17 h**

---

## What to cut if you run out of time tonight

| Cut this | Not this |
|---|---|
| Streak mode (9) | Pick-up detector (1) |
| Guest web page (10) | Siren (3) |
| Table Talk cards (8) | Supabase rooms (5) |
| Ads and Pro unlock (11) | QR join (6) |
| Pretty UI | Working catch detection |

---

## After the build — not tonight, but start the clock

| Step | When | Note |
|---|---|---|
| Google Play account, $25 | Day 2 | Nothing ships without it |
| 12 testers, closed test | Day 2–16 | **14 calendar days minimum.** Line the people up now |
| Threshold tuning on cheap Androids | Days 3–16 | Use the closed test to collect false-positive reports |
| Production release | Day ~17 | After Google review |
| 20 creator videos (India) | Week 4 | Only after the app is stable |
| Watch guest→install | Week 5 | >15% = fund US/UK installs. <15% = stop |

---

## Phase 1 detail — because everything depends on it

| Sub-step | What |
|---|---|
| 1a | Stream `accelerometerEvents` + `gyroscopeEvents` via `sensors_plus` |
| 1b | Compute gravity-magnitude deviation and rotation rate; low-pass filter both |
| 1c | **Settling state:** phone must be flat and still for 2 s before the game arms |
| 1d | **Armed state:** watch for deviation above threshold sustained ~150 ms (so a table bump doesn't fire) |
| 1e | Also catch: `AppLifecycleState.paused/inactive` (switched away) and screen unlock |
| 1f | Debug overlay printing live values + what tripped the catch — keep this in the app behind a dev flag forever |
| 1g | Thresholds in one constants file now, Firebase Remote Config later |
