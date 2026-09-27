#!/usr/bin/env bash
# Generate a stable release keystore for IfallMusic.
#
# Run once, then keep android/app/upload-keystore.jks backed up safely.
# Future release builds MUST use the SAME keystore, otherwise Android will
# refuse to install the update with:
#   "App not installed as package conflicts with an existing package."
#
# Usage:
#   bash android/generate_keystore.sh
#
# The key.properties file at android/key.properties is already configured
# to use:
#   storeFile  = app/upload-keystore.jks
#   keyAlias   = ifallmusic
#   store/key pass = ifallmusic123
#
# Change passwords here AND in android/key.properties if you want stronger
# credentials.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYSTORE="$SCRIPT_DIR/app/upload-keystore.jks"

if [ -f "$KEYSTORE" ]; then
  echo "Keystore already exists at: $KEYSTORE"
  echo "Delete it first if you really want to start over (this will break updates for existing users!)."
  exit 0
fi

if ! command -v keytool >/dev/null 2>&1; then
  echo "keytool not found. Install a JDK first:"
  echo "  • Windows/macOS/Linux: install Android Studio (bundles JDK) or run 'flutter doctor'"
  echo ""
  echo "After the JDK is on PATH, re-run this script."
  exit 1
fi

echo "Generating release keystore at: $KEYSTORE"
keytool -genkey -v \
  -keystore "$KEYSTORE" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias ifallmusic \
  -storepass ifallmusic123 \
  -keypass ifallmusic123 \
  -dname "CN=Ifallertzia, OU=IfallMusic, O=IfallMusic, L=India, ST=India, C=IN"

echo ""
echo "Done. Building the APK now with:"
echo "  flutter build apk --release"
echo ""
echo "BACK UP android/app/upload-keystore.jks — lose it and you can never push an update again."
