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

## Running it in a browser

Useful for looking at screens without a phone — the menus, the where-to-eat
ballot and the bill split all work. Pick-up detection does **not**: a desktop
browser has no accelerometer, so the round never arms. Detection can only be
tested on a real phone.

```bash
flutter build web --no-tree-shake-icons
```

The flag is required for the same reason `tools/build.sh` passes it: this
Flutter install is missing `const_finder`, and without it the web build fails
with an `IconTreeShakerException` that says nothing about icons.

Serve `build/web` over HTTP (not `file://`) and reach the screens directly by
route, e.g. `/#/where` and `/#/split`. Note that Flutter's service worker
caches aggressively — after a rebuild, serve on a different port or the browser
will quietly keep running the old bundle.

Needs a **real Android device** — emulator sensors are not reliable enough for
pick-up detection, and detection is the product.

## Android toolchain note

`flutter doctor` reports missing `cmdline-tools` and unaccepted licenses. Install
Android Studio (or the standalone command-line tools) and run
`flutter doctor --android-licenses` if Gradle builds fail.

### The NDK pin

Fixed 11 Nov 2026.

`android/app/build.gradle.kts` pins `ndkVersion`. Commit c4eea3c changed that
pin from `27.0.12077973` to `28.2.13676358`, but 28.2 had never been installed,
so every Gradle build failed while *configuring* `:app` — before compiling
anything:

```
com.android.builder.sdk.InstallFailedException: Failed to install the following
SDK components: ndk;28.2.13676358
```

AGP cannot install an SDK component itself, so it only reports the failure.
`cmdline-tools` and the SDK licences were both present and fine; neither was
the cause, despite what the error implies.

Fixed by installing the pinned version:

```bash
"$LOCALAPPDATA/Android/Sdk/cmdline-tools/latest/bin/sdkmanager.bat" "ndk;28.2.13676358"
```

Verified: `flutter build apk --debug` now succeeds — `app-debug.apk`, 185 MB
unstripped, which is normal for a debug build. That also confirms the
`geolocator` native plugin assembles.

Two things worth knowing if this recurs:

- A failed install leaves `ndk/<version>/.installer/` behind and nothing else.
  **Delete that stub before retrying** — a half-present directory is more
  confusing than an absent one, and it is what makes the error look like a
  permissions or licence problem.
- `27.0.12077973` is also installed and complete, so pointing the pin back at
  it is a zero-download alternative. The NDK is used here only to strip symbols
  from prebuilt `.so` files with `llvm-strip` — no plugin in this project
  compiles native code — so either version does the job. CONTEXT.md section 10
  avoids NDK-dependent packages for exactly this reason.
