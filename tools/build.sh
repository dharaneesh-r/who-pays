#!/usr/bin/env bash
# Build the app, surviving the Windows Gradle file lock.
#
# Even with file watching disabled, a build that is killed mid-R8 can leave a
# daemon holding classes.dex. This retries once after stopping the daemons,
# which is the only thing that actually releases the handle.
#
# Usage:
#   tools/build.sh apk                     release APK, arm64
#   tools/build.sh apk --split-per-abi     all ABIs
#   tools/build.sh appbundle               the .aab for Play
#
# Any extra arguments are passed through to `flutter build`, so the AdMob id
# goes in the usual way:
#   tools/build.sh appbundle --dart-define=ADMOB_INTERSTITIAL=ca-app-pub-x/y

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

TARGET="${1:-apk}"
shift || true

# const_finder is missing from this Flutter install's cache, so icon
# tree-shaking has to stay off. See PHASES.md → Known build quirks.
ARGS=(--release --no-tree-shake-icons "$@")
if [[ "$TARGET" == "apk" && ! " $* " =~ " --split-per-abi " ]]; then
  ARGS+=(--target-platform android-arm64)
fi

# Pre-flight. Both of these are invisible until it is far too late: which ad
# unit a build carries, and where its QR codes point. Say them out loud.
warned=0

# AdsService defaults to the REAL unit in release and the test unit in debug,
# so a plain release build serves live ads. Tapping your own live ad is
# invalid traffic, and it is the usual way a small developer loses an AdMob
# account — which makes a warning that says "test ad unit" on a live build
# worse than no warning at all. Report what the build will actually carry.
if [[ " $* " =~ "ADMOB_INTERSTITIAL=" ]]; then
  echo "• ads: using the unit passed on the command line."
else
  echo "⚠ ads: this is a RELEASE build, so it serves LIVE ads."
  echo "    DO NOT tap them — clicking your own ads gets the account banned."
  echo "    For a safe build to poke at, use: flutter run (debug uses test ads),"
  echo "    or pass --dart-define=ADMOB_INTERSTITIAL=ca-app-pub-3940256099942544/1033173712"
  warned=1
fi
if [[ ! " $* " =~ "JOIN_HOST=" ]]; then
  host=$(grep -oE "defaultValue: '[^']+'" lib/features/room/domain/join_link.dart | head -1 | sed "s/defaultValue: '//;s/'//")
  echo "⚠ links: QR codes and the privacy link will point at $host"
  echo "    add --dart-define=JOIN_HOST=https://your-domain if that is not live"
  warned=1
fi
[[ $warned -eq 1 ]] && echo

LOG="$(mktemp -t whopays-build-XXXXXX.log)"

run_build() {
  echo "→ flutter build $TARGET ${ARGS[*]}"
  flutter build "$TARGET" "${ARGS[@]}" > "$LOG" 2>&1
  return $?
}

stop_daemons() {
  echo "→ stopping Gradle daemons"
  (cd android && ./gradlew --stop) > /dev/null 2>&1 || true
}

run_build
status=$?

if [[ $status -ne 0 ]] && grep -q "being used by another process" "$LOG"; then
  echo "✗ Gradle file lock — a stale daemon is holding the build output."
  stop_daemons
  run_build
  status=$?
fi

tail -n 12 "$LOG"

if [[ $status -eq 0 ]]; then
  echo "✓ build succeeded"
else
  echo "✗ build failed — full log: $LOG"
fi

exit $status
