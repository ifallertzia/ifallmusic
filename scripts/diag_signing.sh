#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# diag_signing.sh — TEMPORARY diagnostic for the release-signing failure.
#
# NOT part of the release path. It exists only to turn facts that normally
# live in CI logs (which are not retrievable from this environment) into job
# ANNOTATIONS, which are readable through the GitHub API.
#
# Usage:
#   bash scripts/diag_signing.sh keystore   # facts about the SIGNING_KEY
#   bash scripts/diag_signing.sh parse      # apksigner vs keytool digest parse
#   bash scripts/diag_signing.sh apk        # facts about the built APK
# ---------------------------------------------------------------------------
set -uo pipefail

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ann() { # ann <title> <text>
  local title="$1" text="${2:-}"
  text="${text//%/%25}"; text="${text//$'\r'/%0D}"; text="${text//$'\n'/%0A}"
  echo "::notice title=${title}::${text}"
}

ann_b64() { # ann_b64 <title> <file> [bytes]
  local title="$1" file="$2" n="${3:-1200}"
  if [[ ! -f "$file" ]]; then echo "::warning::${title}: missing ${file}"; return 0; fi
  echo "::notice title=${title}::$(head -c "$n" "$file" | base64 -w0)"
}

# The canonical signing-certificate SHA-256: the SHA-256 of the DER encoding of
# the certificate. This is exactly what apksigner reports as
# "Signer #1 certificate SHA-256 digest" and what keytool reports as SHA256.
canon_cert_sha() { # canon_cert_sha <keystore> <alias> <storepass>
  local ks="$1" alias="$2" storepass="$3"
  keytool -exportcert -alias "$alias" -keystore "$ks" -storetype JKS \
    -storepass "$storepass" -file "$TMP/cert.der" >/dev/null 2>&1 || return 1
  openssl dgst -sha256 "$TMP/cert.der" | awk '{print toupper($NF)}'
}

# Same awk the release workflow uses to read apksigner's output.
parse_apksigner() { awk -F': ' '/SHA-256 digest/ {gsub(/:/,"",$2); print toupper($2); exit}' "$1"; }
# Same awk scripts/ci_prepare_signing.sh uses on keytool -list -v.
parse_keytool() { awk -F': ' '/SHA256:/ {gsub(/:/,"",$2); print toupper($2); exit}' "$1"; }

MODE="${1:-keystore}"

case "$MODE" in
# ---------------------------------------------------------------------------
keystore)
  KS="${SIGNING_KEYSTORE_FILE:?SIGNING_KEYSTORE_FILE not set}"
  SUMMARY="$(mktemp)"
  ann "DIAG keystore path" "$KS"
  ann "DIAG keystore digest" "sha256=$(sha256sum "$KS" | cut -d' ' -f1) bytes=$(stat -c %s "$KS")"

  keytool -list -keystore "$KS" -storetype JKS -storepass "$STORE_PASSWORD" \
    > "$TMP/all.txt" 2>&1
  ann_b64 "DIAG keytool -list (all aliases)" "$TMP/all.txt" 1200

  keytool -list -v -keystore "$KS" -storetype JKS -alias "${KEY_ALIAS}" \
    -storepass "$STORE_PASSWORD" > "$TMP/alias.txt" 2>&1
  ann_b64 "DIAG keytool -list -v (alias)" "$TMP/alias.txt" 1500

  KT_PARSED="$(parse_keytool "$TMP/alias.txt")"
  CANON="$(canon_cert_sha "$KS" "${KEY_ALIAS}" "${STORE_PASSWORD}")"
  ann "DIAG keystore cert digests" "keytool-awk=${KT_PARSED:-<empty>} openssl-der=${CANON:-<unread>} script-output=${KEYSTORE_SHA256_OUT:-<none>}"

  # Any other SHA256: lines in the alias dump (chains / multiple entries).
  ann "DIAG all SHA256 lines" "$(grep -c 'SHA256:' "$TMP/alias.txt") SHA256 lines: $(grep -o 'SHA256: [0-9A-Fa-f:]*' "$TMP/alias.txt" | tr '\n' ' ' | head -c 400)"
  ;;

# ---------------------------------------------------------------------------
parse)
  # Does the workflow's apksigner parsing agree with the workflow's keytool
  # parsing for THE SAME key? A throwaway keystore + a throwaway APK answer
  # that without touching the real release key.
  keytool -genkeypair -keystore "$TMP/t.jks" -storetype JKS -alias upload \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=diag, OU=diag, O=diag, L=diag, ST=diag, C=IN" \
    -storepass diagpass -keypass diagpass -noprompt > "$TMP/gen.txt" 2>&1 \
    || { ann_b64 "DIAG keytool -genkeypair failed" "$TMP/gen.txt"; exit 0; }

  mkdir -p "$TMP/apk"
  printf '%s' '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.diag.test"/>' \
    > "$TMP/apk/AndroidManifest.xml"
  printf '%s' 'diag' > "$TMP/apk/classes.dex"
  ( cd "$TMP/apk" && zip -q -r "$TMP/t.zip" . )

  SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  APKSIGNER="$(ls -d "$SDK_ROOT"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1 || true)"
  ann "DIAG tool versions" "sdk_root=${SDK_ROOT:-<unset>} apksigner=${APKSIGNER:-<missing>} java=$(java -version 2>&1 | head -1)"

  if [[ -z "$APKSIGNER" ]]; then
    echo "::warning::apksigner not found; skipping parse check."
    exit 0
  fi

  "$APKSIGNER" sign --ks "$TMP/t.jks" --ks-type JKS --ks-key-alias upload \
    --ks-pass pass:diagpass --key-pass pass:diagpass \
    --out "$TMP/t-signed.apk" "$TMP/t.zip" > "$TMP/sign.txt" 2>&1 \
    || { ann_b64 "DIAG apksigner sign failed" "$TMP/sign.txt"; exit 0; }

  "$APKSIGNER" verify --print-certs -v "$TMP/t-signed.apk" > "$TMP/verify.txt" 2>&1 || true
  ann_b64 "DIAG apksigner verify --print-certs (raw)" "$TMP/verify.txt" 1500
  "$APKSIGNER" --version > "$TMP/apksigner-version.txt" 2>&1 || true
  ann "DIAG apksigner version" "$(head -c 200 "$TMP/apksigner-version.txt" | tr '\n' ' ')"

  APK_PARSED="$(parse_apksigner "$TMP/verify.txt")"
  KS_CANON="$(canon_cert_sha "$TMP/t.jks" upload diagpass)"
  keytool -list -v -keystore "$TMP/t.jks" -storetype JKS -alias upload \
    -storepass diagpass > "$TMP/kt.txt" 2>&1
  KT_PARSED="$(parse_keytool "$TMP/kt.txt")"
  ann "DIAG parse agreement" "apksigner-awk=${APK_PARSED:-<empty>} keytool-awk=${KT_PARSED:-<empty>} openssl-der=${KS_CANON:-<unread>} apk_equals_keytool=$([[ "$APK_PARSED" == "$KT_PARSED" ]] && echo YES || echo NO) apk_equals_openssl=$([[ "$APK_PARSED" == "$KS_CANON" ]] && echo YES || echo NO)"
  ;;

# ---------------------------------------------------------------------------
apk)
  APK="${APK_PATH:-build/app/outputs/flutter-apk/app-release.apk}"
  [[ -f "$APK" ]] || { echo "::error::no APK at $APK"; exit 1; }
  ann "DIAG apk" "$(stat -c %s "$APK") bytes, sha256=$(sha256sum "$APK" | cut -d' ' -f1)"

  unzip -l "$APK" 2>/dev/null | grep -i "META-INF" > "$TMP/meta.txt" || true
  ann "DIAG APK META-INF entries" "count=$(wc -l < "$TMP/meta.txt") names=$(awk '{print $NF}' "$TMP/meta.txt" | tr '\n' ' ' | head -c 300)"

  # Which signing config did Gradle actually use?
  grep -nE "Release signing:|no release keystore|WARNING:" build.log > "$TMP/gradle.txt" 2>/dev/null || true
  ann_b64 "DIAG gradle signing lines from build.log" "$TMP/gradle.txt" 800

  SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  APKSIGNER="$(ls -d "$SDK_ROOT"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1 || true)"
  if [[ -n "$APKSIGNER" ]]; then
    "$APKSIGNER" verify --print-certs -v "$APK" > "$TMP/verify.txt" 2>&1 || true
    ann_b64 "DIAG apksigner verify --print-certs (APK)" "$TMP/verify.txt" 1800
    APK_PARSED="$(parse_apksigner "$TMP/verify.txt")"
    ann "DIAG APK signer digest (apksigner awk)" "${APK_PARSED:-<empty>}"
  fi

  keytool -printcert -jarfile "$APK" > "$TMP/jar.txt" 2>&1 || true
  ann_b64 "DIAG keytool -printcert -jarfile (APK)" "$TMP/jar.txt" 900

  KS="${SIGNING_KEYSTORE_FILE:-}"
  KT_PARSED=""
  if [[ -n "$KS" && -f "$KS" ]]; then
    keytool -list -v -keystore "$KS" -storetype JKS -alias "${KEY_ALIAS}" \
      -storepass "$STORE_PASSWORD" > "$TMP/kt.txt" 2>&1 || true
    KT_PARSED="$(parse_keytool "$TMP/kt.txt")"
    ann "DIAG keystore digest at verify time" "${KT_PARSED:-<empty>} (file=$(sha256sum "$KS" | cut -d' ' -f1 | head -c 16)...)"
  fi

  FINAL="$(grep -oE 'Signer #1 certificate SHA-256 digest: [0-9A-Fa-f]+' "$TMP/verify.txt" 2>/dev/null | head -1)"
  ann "DIAG VERDICT" "apk=${FINAL:-<unread>} keystore=${KT_PARSED:-<unread>} match=$([[ -n "$FINAL" && -n "$KT_PARSED" && "${FINAL##*: }" == "$KT_PARSED" ]] && echo YES || echo NO)"
  ;;

*)
  echo "unknown mode: $MODE" >&2
  exit 2
  ;;
esac

exit 0
