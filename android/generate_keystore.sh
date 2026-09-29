#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# generate_keystore.sh — create the stable Android release signing key.
#
# ⚠️  READ THIS FIRST ⚠️
#   Only generate a BRAND-NEW key if no previously published APK must keep
#   receiving updates. A signing key cannot be reconstructed from an APK.
#   Every later release MUST reuse the SAME keystore, or Android refuses the
#   update with:
#     "App not installed as package conflicts with an existing package."
#
#   If a keystore already exists, this script refuses to overwrite it.
#
# Interactive (prompts for a password):
#   bash android/generate_keystore.sh
#
# Non-interactive (used to produce the key that now lives in GitHub secrets):
#   KEYSTORE_PASSWORD='...' bash android/generate_keystore.sh --yes
#
# Then upload it to GitHub:
#   bash scripts/set_signing_secrets.sh
# or  bash scripts/set_signing_secrets.sh --print   (paste into the web UI)
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYSTORE="$SCRIPT_DIR/app/upload-keystore.jks"
ALIAS="upload"
ASSUME_YES=0
[[ "${1:-}" == "--yes" ]] && ASSUME_YES=1

if [[ -f "$KEYSTORE" ]]; then
  echo "Keystore already exists at: $KEYSTORE"
  echo "Delete it first ONLY if you accept that every existing user must"
  echo "uninstall the app before they can install a new build."
  exit 0
fi

if ! command -v keytool >/dev/null 2>&1; then
  echo "keytool not found. Install a JDK first:" >&2
  echo "  • Android Studio bundles one, or 'flutter doctor' points at it." >&2
  echo "  • Linux: sudo apt-get install openjdk-21-jdk" >&2
  exit 1
fi

if [[ -n "${KEYSTORE_PASSWORD:-}" ]]; then
  PASSWORD="$KEYSTORE_PASSWORD"
elif (( ASSUME_YES )); then
  echo "--yes requires KEYSTORE_PASSWORD in the environment." >&2
  exit 1
else
  read -r -s -p "Choose a keystore password (at least 6 characters): " PASSWORD
  printf "\n"
  if [[ "${#PASSWORD}" -lt 6 ]]; then
    echo "Password must be at least 6 characters." >&2
    exit 1
  fi
  read -r -s -p "Confirm keystore password: " CONFIRM
  printf "\n"
  if [[ "$PASSWORD" != "$CONFIRM" ]]; then
    echo "Passwords do not match." >&2
    exit 1
  fi
fi

echo "Generating release keystore at: $KEYSTORE"
mkdir -p "$(dirname "$KEYSTORE")"

# RSA 2048, ~27 years of validity — the standard Android upload-key recipe.
# The same password protects the key and the store, which is what AGP expects
# when keyPassword and storePassword are supplied separately but equal.
keytool -genkeypair -v \
  -keystore "$KEYSTORE" \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias "$ALIAS" \
  -storepass "$PASSWORD" \
  -keypass "$PASSWORD" \
  -dname "CN=Ifallertzia, OU=IfallMusic Release Signing, O=IfallMusic, L=Mumbai, ST=Maharashtra, C=IN"

chmod 600 "$KEYSTORE"

# Local builds read this file; it is git-ignored.
cat > "$SCRIPT_DIR/key.properties" <<EOF
storeFile=upload-keystore.jks
storeType=JKS
keyAlias=$ALIAS
keyPassword=$PASSWORD
storePassword=$PASSWORD
EOF
chmod 600 "$SCRIPT_DIR/key.properties"

# Prove the credentials work before we tell anyone they do.
keytool -list -keystore "$KEYSTORE" -storetype JKS -alias "$ALIAS" \
        -storepass "$PASSWORD" -keypass "$PASSWORD" >/dev/null
echo "✓ Keystore verified: alias '$ALIAS' readable with the given passwords."
echo "  Certificate SHA-256:"
keytool -list -v -keystore "$KEYSTORE" -storetype JKS -alias "$ALIAS" \
        -storepass "$PASSWORD" 2>/dev/null | awk -F': ' '/SHA256:/ {print "    "$2; exit}'

unset PASSWORD CONFIRM KEYSTORE_PASSWORD

cat <<EOF

Base64 for the GitHub SIGNING_KEY secret:
  base64 -w 0 $KEYSTORE

Upload all four secrets automatically:
  bash scripts/set_signing_secrets.sh --keystore $KEYSTORE --alias $ALIAS

BACK UP $KEYSTORE AND ITS PASSWORD OFFLINE. Lose them and you can never push
an update that existing users can install.
EOF
