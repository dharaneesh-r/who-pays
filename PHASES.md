# BUILD PHASES — "Who Pays?"

Status as of 2026-11-06. Context: [CONTEXT.md](CONTEXT.md)

## Progress

**10 of 12 phases done. 2 pending.**

| # | Phase | Status | Blocked by |
|---|---|---|---|
| 0 | Project setup | ✅ Done | — |
| 1 | Pick-up detector | ✅ Done | — |
| 2 | Round loop (setup/play/result) | ✅ Done | — |
| 3 | Siren, haptics, wakelock | ✅ Done | — |
| 4 | Storage, history, tallies | ✅ Done | — |
| 5 | Supabase rooms + realtime | ✅ Done | — |
| 6 | QR join | ✅ Done | — |
| 7 | Result card + share | ✅ Done | — |
| 8 | Table Talk cards | ✅ Done | — |
| 9 | Streak mode | ✅ Done | — |
| 10 | Guest web join page | ⛔ Blocked | Phase 5 + **Cloudflare account** |
| 11 | Money, analytics, release build | ⛔ Blocked | **AdMob + Firebase + Play account + keystore** |
| — | Verify APK on a real device | ⛔ Blocked | **Disk space + an Android phone** |

Verified so far: 70 unit tests passing, `flutter analyze` clean, 9 commits, 42 Dart files.
Not verified: nothing has run on a real phone yet.

---

## What you need to get, and when

### Blocking right now

| What | Unlocks | Cost | How long |
|---|---|---|---|
| **Supabase project** — URL + anon key | Phases 5, 6, 10 | Free | 5 min |
| **Disk space** — 15 GB+ free | Any Android build | Free | — |
| **Android phone + USB cable**, USB debugging on | Testing the detector | Free | 5 min |

Supabase: create a project at supabase.com → SQL Editor → paste
[supabase/schema.sql](supabase/schema.sql) → Run. Then Settings → API, copy the
**Project URL** and the **anon public** key. The anon key is safe in the app;
the `service_role` key is not — never put that in the client.

### Needed before release (phase 11)

| What | Unlocks | Cost | Notes |
|---|---|---|---|
| **Google Play developer account** | Publishing, IAP products | **$25 one-time** | The only mandatory spend |
| **Upload keystore** | Signed release build | Free | Generated locally with `keytool` |
| **Firebase project** → `google-services.json` | Analytics, Crashlytics, Remote Config | Free | Remote Config is how detection thresholds get tuned without a release |
| **AdMob account** → app ID + ad unit IDs | Ads | Free | Payout setup needs bank/tax details |
| **Cloudflare account** | Guest web join page | Free | Phase 10 |
| **12 testers** | Production access | Free | **14 calendar days** — start this early |

### Not needed yet

| What | Cost | When |
|---|---|---|
| Apple Developer | $99/yr | Only when shipping iOS |
| Custom domain for the guest link | ~₹800/yr | Optional polish; `*.pages.dev` is free |
| Creator seeding | ₹50k–2.5L | Only after v1 works |
| Paid installs | ₹50k–1L | Only if guest→install clears 15% |

---

## Phases

| # | Phase | Time | Deliverable |
|---|---|---|---|
| 5 | Supabase rooms + realtime | 2.5 h | 4-letter room code, join, presence, catch broadcast, live leaderboard |
| 6 | QR join | 45 m | Host shows QR, guest scans. Test with 3 phones at a real table |
| 7 | Result card + share | 1 h | Screenshot-to-image card → WhatsApp. The growth loop |
| 8 | Table Talk cards | 45 m | JSON prompt packs rotating on screen during the round |
| 9 | Streak mode | 1 h | Daily phone-free dinner streak + reminder. Only real D30 lever |
| 10 | Guest web join page | 2 h | Cloudflare Pages, DeviceMotion + Page Visibility, under 50 KB |
| 11 | Money, analytics, release | 2 h | AdMob, Pro unlock, Firebase, icon, keystore, signed AAB |

**~10 hours of work left.**

---

## Suggested order from here

1. **Phases 7, 8, 9 now** (~2h 45m) — no accounts needed, and they make the solo
   game genuinely good rather than a tech demo.
2. **Free up disk, plug in a phone** → verify the detector in the real world.
   Nothing else matters if detection feels wrong.
3. **Supabase keys** → phases 5 and 6 → test with 3 phones at a real table.
4. **Phase 10** → the guest web page, which is the viral unlock.
5. **Phase 11** → release build, then start the 12-tester clock immediately.

## After the build

| Step | When | Note |
|---|---|---|
| Play account, $25 | Before closed test | |
| 12 testers, closed test | 14 calendar days | Line people up now |
| Threshold tuning | Throughout | Use the closed test to collect false-positive reports |
| Production release | After Google review | |
| 20 creator videos (India) | Week 4 | Only once stable |
| Watch guest→install | Week 5 | >15% = fund US/UK installs. <15% = stop |
