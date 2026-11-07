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
