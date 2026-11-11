# Who Pays?

Phones face down on the table. First one to pick up loses — and pays the bill.

- Product & business context: [CONTEXT.md](CONTEXT.md)
- Build phases: [PHASES.md](PHASES.md)
- Candidate ideas considered: [APPS.md](APPS.md)
- Venue attribution & restaurant sponsorship: [VENUES.md](VENUES.md)

## Stack

Flutter (Dart 3.10) · Riverpod · go_router · sqflite · Supabase Realtime ·
`sensors_plus` for pick-up detection · AdMob + `in_app_purchase` (phase 11).

## Layout

```
lib/
  core/
    constants/   detection thresholds — the most important numbers in the app
    router/      go_router routes
    theme/       dark, high-contrast, table-readable
  data/
    local/       sqflite database
    remote/      Supabase client
  features/
    home/        landing screen
    detector/    sensor state machine + dev read-out
    game/        round loop, timer, catch, result
    room/        room codes, QR join, realtime
    cards/       Table Talk prompt packs
    stats/       group tallies and history
assets/
  audio/         siren
  cards/         prompt packs (JSON)
```

## Run

```bash
flutter run
```

## Build

Use the wrapper rather than `flutter build` directly — it carries the flags
this project needs and recovers from the Windows Gradle file lock:

```bash
tools/build.sh apk
```

```bash
tools/build.sh appbundle --dart-define=ADMOB_INTERSTITIAL=ca-app-pub-xxx/yyy
```

Where-to-eat voting ([VENUES.md](VENUES.md)) is off unless the build says
otherwise. Without these it runs on fake places from a fixed point, which is
why a debug build never spends anything:

```bash
tools/build.sh appbundle --dart-define=PLACES_KEY=AIza... --dart-define=LOCATION=true
```

`LOCATION=true` also needs `ACCESS_COARSE_LOCATION` uncommented in
`android/app/src/main/AndroidManifest.xml` — the flag alone does nothing, and
the comment there says why it is off.

Needs a **real Android device** — emulator sensors are not reliable enough for
pick-up detection, and detection is the product.

## Android toolchain note

`flutter doctor` reports missing `cmdline-tools` and unaccepted licenses. Install
Android Studio (or the standalone command-line tools) and run
`flutter doctor --android-licenses` if Gradle builds fail.

### Gradle builds currently fail here — empty NDK directories

Checked 11 Nov 2026. `tools/build.sh` and `flutter build apk` fail while
*configuring* `:app`:

```
com.android.builder.sdk.InstallFailedException: Failed to install the following
SDK components: ndk;28.2.13676358
```

The cause is not the pin in `android/app/build.gradle.kts`. Both
`%LOCALAPPDATA%/Android/Sdk/ndk/27.0.12077973` and
`%LOCALAPPDATA%/Android/Sdk/ndk/28.2.13676358` exist but are **empty** — no
`source.properties`, no binaries. AGP therefore cannot recognise either as
installed, tries to install one, and cannot, because `cmdline-tools` is
missing. SDK licences are already accepted, so that is not the blocker.

Fix: install `cmdline-tools`, then `sdkmanager "ndk;28.2.13676358"` (or tick
that NDK in Android Studio → SDK Manager → SDK Tools → show package details).
Delete the empty directories first; a stub directory is what confuses AGP.

Until that is done **no Android build can be verified on this machine**, so any
change touching a native plugin is untested on the native side even when
`flutter analyze` and `flutter test` are clean.
