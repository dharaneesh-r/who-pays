# BUILD PHASES — "Who Pays?"

Status as of 2026-11-06. Context: [CONTEXT.md](CONTEXT.md)

## Progress

**All 12 phases built.**

| # | Phase | Status |
|---|---|---|
| 0 | Project setup | ✅ |
| 1 | Pick-up detector | ✅ |
| 2 | Round loop (setup/play/result) | ✅ |
| 3 | Siren, haptics, wakelock | ✅ |
| 4 | Storage, history, tallies | ✅ |
| 5 | Supabase rooms + realtime | ✅ |
| 6 | QR join | ✅ |
| 7 | Result card + share | ✅ |
| 8 | Table Talk cards | ✅ |
| 9 | Streak mode | ✅ |
| 10 | Guest web join page | ✅ (written, not deployed) |
| 11 | IAP, ads, icon, release signing | ✅ (test ad ids, no keystore yet) |

**Verified:** 83 unit tests passing · `flutter analyze` clean · `flutter doctor`
fully green · debug APK, release APKs (arm64 27.6 MB, arm 23.8 MB, x86_64
29.9 MB) and the release `.aab` (56.1 MB) all build with exit 0 · 49 Dart files.

**Not verified:** nothing has run on a physical device. No round, siren, room or
purchase has ever executed.

---

## What is left — none of it is code

| # | Task | Why | Cost |
|---|---|---|---|
| 1 | **Free ~15 GB of disk** | Builds repeatedly ran the drive to zero | Free |
| 2 | **Test on a real Android phone** | The detector's thresholds are informed guesses. This is the single biggest risk in the project | Free |
| 3 | **Deploy the guest page** to Cloudflare Pages | Phase 10 is written but unhosted. See [web_guest/README.md](web_guest/README.md) | Free |
| 4 | **Google Play account** | Publishing + IAP product ids | **$25 one-time** |
| 5 | **Create the upload keystore** | See [android/key.properties.example](android/key.properties.example). **Back it up off this machine** | Free |
| 6 | **Create IAP products in Play Console** | Ids must match `ProductIds` in [entitlements.dart](lib/features/paywall/domain/entitlements.dart) | Free |
| 7 | **AdMob account** → real app id + ad unit id | Currently Google's public *test* ids. Shipping these earns nothing | Free |
| 8 | **Firebase project** → `google-services.json` | Analytics, Crashlytics, and Remote Config for tuning detection thresholds without a release. **Not yet wired** | Free |
| 9 | **12 testers, 14 days** | Required for production access on a new personal account | Free |

### Known build quirks on this machine

| Problem | Fix |
|---|---|
| `IconTreeShakerException: Could not find const_finder.dart.snapshot` | This Flutter install's cache is incomplete and `flutter precache --android` does not restore it. Build with `--no-tree-shake-icons`, or reinstall the Flutter SDK to a path without spaces to get a complete cache. Only cost is a slightly larger icon font. |
| `Cannot lock execution history cache … already locked` | A killed build left a Gradle daemon holding the lock. `cd android && ./gradlew --stop` |
| `NDK … did not have a source.properties file` | Was an empty stub from a failed download. **Resolved:** command-line tools installed and NDK 27.0.12077973 installed via `sdkmanager`; `ndkVersion` is now pinned in `android/app/build.gradle.kts`. The NDK is needed only so release builds can strip debug symbols |
| Build runs the disk to 0 bytes | Gradle caches grow past 4 GB. Keep 15 GB free; `flutter clean` reclaims ~1 GB |

### Replacing the test AdMob ids

1. `android/app/src/main/AndroidManifest.xml` — the
   `com.google.android.gms.ads.APPLICATION_ID` meta-data.
2. The ad unit, at build time:
   `flutter build appbundle --dart-define=ADMOB_INTERSTITIAL=ca-app-pub-xxx/yyy`

Never test against live ad units — it gets the AdMob account banned.

### Deploying the guest page

Cloudflare Pages → upload `web_guest/`. If the project name is not `who-pays`,
rebuild the app with
`--dart-define=JOIN_HOST=https://your-name.pages.dev` so the QR points at it.

---

## The one thing that could still change the design

Detection thresholds in
[detection_config.dart](lib/core/constants/detection_config.dart) were tuned
against a simulated phone, not a real one. Unit tests prove the *logic* is
right — a table bump never catches anyone, repeated bumps never drift the
gravity estimate, a real lift always fires. They cannot prove the *numbers* suit
real hardware.

First session on a real device should be: open **Dev · sensor detector** on the
home screen, put the phone down, and watch the live read-out while bumping the
table, sliding the phone, and picking it up. Adjust the constants, re-run
`flutter test`, repeat. Budget an evening for this and do it before anything else.

---

## After launch

| Step | When |
|---|---|
| 12-tester closed test | 14 calendar days — start the day the AAB builds |
| Threshold tuning from tester reports | Throughout |
| Production release | After Google review |
| 20 creator videos (India) | Week 4, only once stable |
| Watch guest→install conversion | Week 5. >15% = fund US/UK installs. <15% = stop |
