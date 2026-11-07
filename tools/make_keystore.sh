#!/usr/bin/env bash
# Creates the upload keystore that signs every Play release.
#
# Run it once. The password you type never leaves this machine — it goes into
# android/key.properties, which is gitignored, and into the keystore itself.
#
#   bash tools/make_keystore.sh
#
# IMPORTANT: back up android/upload-keystore.jks and android/key.properties
# somewhere off this machine. If you lose the keystore you can never publish
# an update to this app again — Play identifies the app by its signature, and
# there is no recovery. Treat it like the deed to the app.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STORE="$ROOT/android/upload-keystore.jks"
PROPS="$ROOT/android/key.properties"

if [[ -e "$STORE" ]]; then
  echo "✗ $STORE already exists."
  echo "  Refusing to overwrite it — replacing a keystore makes every"
  echo "  previous release un-updatable. Delete it yourself if you are sure."
  exit 1
fi

# keytool ships with the JDK. Flutter and Android Studio each bundle one, so
# look there before giving up: a missing JAVA_HOME is not a missing JDK.
find_keytool() {
  if command -v keytool >/dev/null 2>&1; then command -v keytool; return; fi
  for base in \
    "${JAVA_HOME:-}" \
    "/c/Program Files/Android/Android Studio/jbr" \
    "$HOME/AppData/Local/Programs/Android Studio/jbr" \
    "/c/Program Files/Java"/*; do
    [[ -n "$base" && -x "$base/bin/keytool.exe" ]] && { echo "$base/bin/keytool.exe"; return; }
    [[ -n "$base" && -x "$base/bin/keytool"     ]] && { echo "$base/bin/keytool";     return; }
  done
  return 1
}

KEYTOOL="$(find_keytool || true)"
if [[ -z "$KEYTOOL" ]]; then
  echo "✗ Could not find keytool. Install a JDK, or set JAVA_HOME to the"
  echo "  'jbr' folder inside your Android Studio install."
  exit 1
fi
echo "→ using $KEYTOOL"

read -r -p "Your name or company (shown in the certificate): " CN
CN="${CN:-Who Pays}"

# Asked twice because a typo here is unrecoverable later.
read -r -s -p "Choose a keystore password (min 6 chars): " PW1; echo
read -r -s -p "Type it again: " PW2; echo
if [[ "$PW1" != "$PW2" ]]; then echo "✗ They don't match."; exit 1; fi
if [[ ${#PW1} -lt 6 ]]; then echo "✗ Too short — keytool requires 6+."; exit 1; fi

# 10000 days: Play requires the key to outlive 2033, and a key that expires
# is as unusable as a key that is lost.
"$KEYTOOL" -genkeypair \
  -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -keystore "$STORE" \
  -storetype JKS \
  -storepass "$PW1" -keypass "$PW1" \
  -dname "CN=$CN, OU=, O=, L=, S=, C=IN"

umask 077
cat > "$PROPS" <<EOF
storePassword=$PW1
keyPassword=$PW1
keyAlias=upload
storeFile=upload-keystore.jks
EOF

unset PW1 PW2

echo
echo "✓ Created:"
echo "    $STORE"
echo "    $PROPS"
echo
echo "Release builds will now be signed with it automatically."
echo
echo "⚠ Back BOTH files up off this machine before you publish."
echo "  Lose them and this app can never be updated again."
