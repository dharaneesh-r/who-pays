# Who Pays?

Phones face down on the table. First one to pick up loses — and pays the bill.

- Product & business context: [CONTEXT.md](CONTEXT.md)
- Build phases: [PHASES.md](PHASES.md)
- Candidate ideas considered: [APPS.md](APPS.md)

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

Needs a **real Android device** — emulator sensors are not reliable enough for
pick-up detection, and detection is the product.

## Android toolchain note

`flutter doctor` reports missing `cmdline-tools` and unaccepted licenses. Install
Android Studio (or the standalone command-line tools) and run
`flutter doctor --android-licenses` if Gradle builds fail.
