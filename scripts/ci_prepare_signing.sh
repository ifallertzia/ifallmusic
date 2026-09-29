#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# ci_prepare_signing.sh — decode and VALIDATE the release keystore in CI.
#
# Shared by .github/workflows/build.yml and build_apk.yml so both release paths
# validate the signing identity identically.
#
# Reads (environment):
#   SIGNING_KEY      base64 of upload-keystore.jks
#   KEY_ALIAS        alias inside the keystore
#   KEY_PASSWORD     key password
#   STORE_PASSWORD   keystore password
#   SIGNING_REQUIRED "true"  -> missing/invalid input fails the step
#                    "false" -> missing input warns and exits 0 (fork PRs have
#                               no access to secrets); invalid input still fails
#
# Writes to $GITHUB_OUTPUT when set:
#   keystore_path     absolute path of the decoded .jks (in $RUNNER_TEMP)
#   keystore_sha256   SHA-256 of the signing certificate, uppercase, no colons
#   signed            "true" when a valid release keystore is ready
#
# Also appends a diagnostics table to $GITHUB_STEP_SUMMARY.
#
# SECURITY
#   * Secret VALUES are never printed. Only lengths and SHA-256 digests, which
#     are not secret and exist to catch a truncated or wrong paste.
#   * The keystore is written under $RUNNER_TEMP/signing (outside the checkout),
#     directory 700, file 600.
#   * Every failure path emits a ::error:: annotation, because CI log files are
#     not always retrievable and annotations are.
# ---------------------------------------------------------------------------
set -uo pipefail

# The release key this repository is supposed to sign with. A SHA-256 digest is
# not secret — it is the fingerprint of a certificate that ships inside every
# public APK. Pinning it means a truncated, garbled or wrong keystore paste is
# caught before anything is built, instead of surfacing later as
# "App not installed as package conflicts with an existing package."
#
# After a DELIBERATE key rotation, update these two values:
#   sha256sum upload-keystore.jks
#   keytool -list -v -alias upload -keystore upload-keystore.jks | awk -F': ' '/SHA256:/{print $2}'
EXPECTED_KEYSTORE_SHA256="41556bab5f72d540200871f1a9be3d20f420a12d582782733d3d712a1ce70b76"
EXPECTED_KEYSTORE_BYTES=2361
EXPECTED_BASE64_SHA256="8352b7b1a2844f376f4116f71344c7e2f4cbf079f3567d54a23ea33d84fbc972"
EXPECTED_BASE64_CHARS=3148
EXPECTED_CERT_SHA256="BD0C849A307E665E9482B654A444C082E1665CB3422B4AC5769F0DD304270E54"

# Advisory by default: a mismatch warns loudly (annotation + job summary +
# the exact constants needed to re-pin) but does not block the build, because
# the two HARD guarantees live elsewhere - keytool proves the keystore is
# structurally valid and that all three passwords are right, and build.yml
# proves the finished APK carries this keystore's certificate. Pinning to a
# hard failure would block a legitimate key that simply is not the one this
# script was written against.
#
# Set SIGNING_ENFORCE_FINGERPRINT=true to make a mismatch fatal.
ENFORCE_FINGERPRINT="${SIGNING_ENFORCE_FINGERPRINT:-false}"

REQUIRED="${SIGNING_REQUIRED:-false}"

err()  { echo "::error title=Release signing::$*"; }
warn() { echo "::warning title=Release signing::$*"; }

summary() {
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && cat >> "$GITHUB_STEP_SUMMARY"
  return 0
}

emit_output() { # emit_output key value
  [[ -n "${GITHUB_OUTPUT:-}" ]] && printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
  return 0
}

fail() { # fail <message>
  err "$1"
  summary <<EOF
### ❌ Release signing: $1

See the job annotations for detail. Nothing was built and no release can be
published with an unverified signing identity.
EOF
  exit 1
}

# ---------------------------------------------------------------------------
# 1. Presence
# ---------------------------------------------------------------------------
missing=()
[[ -n "${SIGNING_KEY:-}" ]]    || missing+=(SIGNING_KEY)
[[ -n "${KEY_ALIAS:-}" ]]      || missing+=(KEY_ALIAS)
[[ -n "${KEY_PASSWORD:-}" ]]   || missing+=(KEY_PASSWORD)
[[ -n "${STORE_PASSWORD:-}" ]] || missing+=(STORE_PASSWORD)

if (( ${#missing[@]} == 4 )); then
  if [[ "$REQUIRED" == "true" ]]; then
    fail "all four signing secrets are missing (${missing[*]}). Set them under Settings -> Secrets and variables -> Actions. A release must never ship debug-signed."
  fi
  warn "no signing secrets configured - this APK will be DEBUG-signed and must not be distributed (it will not install over a release-signed build)."
  summary <<'EOF'
### ⚠️ Signing: debug-key fallback

No release signing secrets are available to this run, so the APK is signed with
the runner's debug key. **Do not distribute it** — it will not install over a
release-signed build. See `docs/RELEASE_SIGNING.md`.
EOF
  emit_output signed false
  emit_output keystore_path ""
  emit_output keystore_sha256 ""
  exit 0
fi

if (( ${#missing[@]} > 0 )); then
  fail "incomplete signing configuration - missing: ${missing[*]}. Set all four secrets (SIGNING_KEY, KEY_ALIAS, KEY_PASSWORD, STORE_PASSWORD), or none at all."
fi

# ---------------------------------------------------------------------------
# 2. Decode to a temporary path OUTSIDE the checkout
# ---------------------------------------------------------------------------
KEYSTORE_DIR="${RUNNER_TEMP:-/tmp}/signing"
rm -rf "$KEYSTORE_DIR"
mkdir -p "$KEYSTORE_DIR" || fail "could not create $KEYSTORE_DIR"
chmod 700 "$KEYSTORE_DIR"
KEYSTORE_PATH="$KEYSTORE_DIR/upload-keystore.jks"

# Report what arrived WITHOUT revealing it. These four numbers uniquely identify
# a correct paste, so a wrong one is obvious at a glance.
B64_CLEAN="$(printf '%s' "$SIGNING_KEY" | tr -d '\r\n\t ')"
B64_LEN="${#B64_CLEAN}"
B64_SHA="$(printf '%s' "$B64_CLEAN" | sha256sum | cut -d' ' -f1)"
echo "SIGNING_KEY received: ${B64_LEN} base64 chars (expected ${EXPECTED_BASE64_CHARS})"
echo "SIGNING_KEY base64 sha256: ${B64_SHA}"
echo "KEY_ALIAS length: ${#KEY_ALIAS} | KEY_PASSWORD length: ${#KEY_PASSWORD} | STORE_PASSWORD length: ${#STORE_PASSWORD}"

if ! printf '%s' "$B64_CLEAN" | base64 --decode > "$KEYSTORE_PATH" 2>/tmp/b64err; then
  fail "SIGNING_KEY is not valid base64: $(head -c 200 /tmp/b64err | tr '\n' ' '). Re-create the secret with: base64 -w 0 upload-keystore.jks"
fi
chmod 600 "$KEYSTORE_PATH"

BYTES="$(stat -c %s "$KEYSTORE_PATH" 2>/dev/null || wc -c < "$KEYSTORE_PATH")"
FILE_SHA="$(sha256sum "$KEYSTORE_PATH" | cut -d' ' -f1)"
echo "Decoded keystore: ${BYTES} bytes (expected ${EXPECTED_KEYSTORE_BYTES})"
echo "Decoded keystore sha256: ${FILE_SHA}"

if [[ ! -s "$KEYSTORE_PATH" ]]; then
  fail "SIGNING_KEY decoded to an empty file. The secret is probably blank or whitespace only."
fi

MAGIC="$(od -An -tx1 -N4 "$KEYSTORE_PATH" | tr -d ' \n')"
if [[ "$MAGIC" != "feedfeed" ]]; then
  fail "decoded file is not a JKS keystore (magic=0x${MAGIC}, expected 0xfeedfeed). SIGNING_KEY is the wrong file or was truncated."
fi

# ---------------------------------------------------------------------------
# 3. Validate with keytool (structure, store password, alias, key password)
#
#    `keytool -list` proves the STORE password and that the alias exists, but it
#    never decrypts the private key, so it does NOT prove the KEY password.
#    `-importkeystore` into a throwaway PKCS12 does decrypt the key, so it
#    validates all three credentials. Both are run.
# ---------------------------------------------------------------------------
KEYSTORE_SHA256=""
if command -v keytool >/dev/null 2>&1; then
  if ! keytool -list -v -keystore "$KEYSTORE_PATH" -storetype JKS \
        -alias "$KEY_ALIAS" -storepass "$STORE_PASSWORD" \
        > "$KEYSTORE_DIR/keytool-list.txt" 2> "$KEYSTORE_DIR/keytool-list.err"; then
    DETAIL="$(head -c 400 "$KEYSTORE_DIR/keytool-list.err" | tr '\n' ' ')"
    fail "keytool could not read alias '$KEY_ALIAS' with STORE_PASSWORD. ${DETAIL}"
  fi
  echo "keytool -list: store password and alias '$KEY_ALIAS' are valid."

  KEYSTORE_SHA256="$(awk -F': ' '/SHA256:/ {gsub(/:/,"",$2); print toupper($2); exit}' "$KEYSTORE_DIR/keytool-list.txt")"
  echo "Certificate SHA-256: ${KEYSTORE_SHA256:-<unread>}"

  PROBE="$KEYSTORE_DIR/keypass-probe.p12"
  if ! keytool -importkeystore \
        -srckeystore "$KEYSTORE_PATH" -srcstoretype JKS \
        -srcalias "$KEY_ALIAS" -srcstorepass "$STORE_PASSWORD" -srckeypass "$KEY_PASSWORD" \
        -destkeystore "$PROBE" -deststoretype PKCS12 -deststorepass "$STORE_PASSWORD" \
        -noprompt > "$KEYSTORE_DIR/keytool-import.txt" 2> "$KEYSTORE_DIR/keytool-import.err"; then
    DETAIL="$(head -c 400 "$KEYSTORE_DIR/keytool-import.err" | tr '\n' ' ')"
    rm -f "$PROBE"
    fail "KEY_PASSWORD does not unlock alias '$KEY_ALIAS' (the private key could not be decrypted). keytool said: ${DETAIL}"
  fi
  rm -f "$PROBE"
  echo "keytool -importkeystore: KEY_PASSWORD unlocks the private key."

  CERT_DN="$(awk -F': ' '/^Owner:/ {sub(/^Owner:[ ]*/,""); print; exit}' "$KEYSTORE_DIR/keytool-list.txt")"
  CERT_VALID="$(awk -F': ' '/^Valid from:/ {sub(/^Valid from:[ ]*/,""); print; exit}' "$KEYSTORE_DIR/keytool-list.txt")"
  echo "Certificate DN: ${CERT_DN:-<unread>}"
  echo "Certificate validity: ${CERT_VALID:-<unread>}"
else
  warn "keytool not found on this runner - skipping keystore validation. Only the byte-level checks applied."
  CERT_DN=""; CERT_VALID=""
fi

# ---------------------------------------------------------------------------
# 4. Fingerprint pin
#
#    Runs AFTER keytool on purpose. A truncated or corrupted paste and a
#    legitimately different keystore hash differently in exactly the same way,
#    but only keytool can tell them apart: a tampered JKS fails its SHA-1
#    integrity digest, while a different valid key opens cleanly. By this point
#    a corrupted paste has already been rejected above, so a mismatch here means
#    "this is a real, valid keystore - just not the pinned one".
#
#    That is a policy question, not a corruption question, so it warns by
#    default. The guarantee that actually prevents a package conflict is
#    downstream: build.yml compares the built APK's certificate against this
#    keystore, so every release is internally consistent whichever key is used.
#    Set SIGNING_ENFORCE_FINGERPRINT=true to make a mismatch fatal.
# ---------------------------------------------------------------------------
if [[ "$FILE_SHA" != "$EXPECTED_KEYSTORE_SHA256" ]]; then
  MSG="the keystore in SIGNING_KEY is NOT the pinned release key. got sha256=${FILE_SHA} (${BYTES} bytes, cert ${KEYSTORE_SHA256:-unknown}, DN '${CERT_DN:-unknown}'), expected sha256=${EXPECTED_KEYSTORE_SHA256} (${EXPECTED_KEYSTORE_BYTES} bytes, cert ${EXPECTED_CERT_SHA256}). base64 was ${B64_LEN} chars, sha256 ${B64_SHA}."
  if [[ "$ENFORCE_FINGERPRINT" == "true" ]]; then
    fail "${MSG} If this is a deliberate key rotation, update the EXPECTED_* constants in scripts/ci_prepare_signing.sh."
  fi
  warn "${MSG} Continuing because SIGNING_ENFORCE_FINGERPRINT is not 'true'. Every release will still be signed consistently with THIS key, and build.yml verifies the APK against it - but it will NOT install over an app signed with the pinned key."
  echo "::notice title=Release signing::Using an unpinned keystore. If this is intentional, pin it: set EXPECTED_KEYSTORE_SHA256=${FILE_SHA} EXPECTED_KEYSTORE_BYTES=${BYTES} EXPECTED_BASE64_SHA256=${B64_SHA} EXPECTED_BASE64_CHARS=${B64_LEN} EXPECTED_CERT_SHA256=${KEYSTORE_SHA256:-} in scripts/ci_prepare_signing.sh"
  PINNED="no"
else
  echo "Keystore matches the pinned release key."
  PINNED="yes"
fi

# ---------------------------------------------------------------------------
# 5. Report
# ---------------------------------------------------------------------------
summary <<EOF
### ✅ Release signing ready

| Check | Value | Expected | |
| --- | --- | --- | --- |
| base64 chars | ${B64_LEN} | ${EXPECTED_BASE64_CHARS} | $([[ "$B64_LEN" == "$EXPECTED_BASE64_CHARS" ]] && echo '✅' || echo '⚠️') |
| base64 sha256 | \`${B64_SHA:0:16}…\` | \`${EXPECTED_BASE64_SHA256:0:16}…\` | $([[ "$B64_SHA" == "$EXPECTED_BASE64_SHA256" ]] && echo '✅' || echo '⚠️') |
| keystore bytes | ${BYTES} | ${EXPECTED_KEYSTORE_BYTES} | $([[ "$BYTES" == "$EXPECTED_KEYSTORE_BYTES" ]] && echo '✅' || echo '⚠️') |
| keystore sha256 | \`${FILE_SHA:0:16}…\` | \`${EXPECTED_KEYSTORE_SHA256:0:16}…\` | $([[ "$FILE_SHA" == "$EXPECTED_KEYSTORE_SHA256" ]] && echo '✅' || echo '⚠️') |
| JKS magic | 0x${MAGIC} | 0xfeedfeed | $([[ "$MAGIC" == "feedfeed" ]] && echo '✅' || echo '❌') |
| cert SHA-256 | \`${KEYSTORE_SHA256:0:16}…\` | \`${EXPECTED_CERT_SHA256:0:16}…\` | $([[ -z "$KEYSTORE_SHA256" || "$KEYSTORE_SHA256" == "$EXPECTED_CERT_SHA256" ]] && echo '✅' || echo '⚠️') |
| pinned key | ${PINNED:-unknown} | yes | $([[ "${PINNED:-}" == "yes" ]] && echo '✅' || echo '⚠️') |

Certificate DN: `${CERT_DN:-<unread>}`
Validity: `${CERT_VALID:-<unread>}`

Keystore decoded to a temporary path outside the checkout; removed by the
\`Clean up temporary keystore\` step on success **and** failure.
EOF

emit_output keystore_path   "$KEYSTORE_PATH"
emit_output keystore_sha256 "$KEYSTORE_SHA256"
emit_output signed          true

echo "Release keystore ready at $KEYSTORE_PATH"
exit 0
