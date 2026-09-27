#!/usr/bin/env bash
# Generate a stable release keystore for IfallMusic.
#
# Only generate a brand-new app signing identity if no previous release must
# be updated in place. This key cannot be reconstructed from an APK.
# Future release builds MUST use the SAME keystore, otherwise Android will
# refuse to install the update with:
#   "App not installed as package conflicts with an existing package."
#
# Usage:
#   bash android/generate_keystore.sh
#
# Configure android/key.properties to use:
#   storeFile  = upload-keystore.jks
#   keyAlias   = ifallmusic
# The script prompts for a strong password and writes the ignored
# android/key.properties file. Securely back up both files.

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

read -r -s -p "Choose a keystore password (at least 6 characters): " KEYSTORE_PASSWORD
printf "\n"
if [ "${#KEYSTORE_PASSWORD}" -lt 6 ]; then
  echo "Password must be at least 6 characters." >&2
  exit 1
fi
read -r -s -p "Confirm keystore password: " CONFIRM_PASSWORD
printf "\n"
if [ "$KEYSTORE_PASSWORD" != "$CONFIRM_PASSWORD" ]; then
  echo "Passwords do not match." >&2
  exit 1
fi

echo "Generating release keystore at: $KEYSTORE"
keytool -genkey -v \
  -keystore "$KEYSTORE" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias ifallmusic \
  -storepass "$KEYSTORE_PASSWORD" \
  -keypass "$KEYSTORE_PASSWORD" \
  -dname "CN=Ifallertzia, OU=IfallMusic, O=IfallMusic, L=India, ST=India, C=IN"
cat > "$SCRIPT_DIR/key.properties" <<EOF
storeFile=upload-keystore.jks
keyAlias=ifallmusic
keyPassword=$KEYSTORE_PASSWORD
storePassword=$KEYSTORE_PASSWORD
EOF
chmod 600 "$SCRIPT_DIR/key.properties"
unset KEYSTORE_PASSWORD CONFIRM_PASSWORD

echo ""
echo "A new private signing identity was generated. It will NOT update an app already signed with another key."
echo "Done. Building the APK now with:"
echo "  flutter build apk --release"
echo ""
echo "BACK UP android/app/upload-keystore.jks — lose it and you can never push an update again."
