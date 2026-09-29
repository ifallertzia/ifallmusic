#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# set_signing_secrets.sh — upload the release signing identity to GitHub.
#
# Sets these four repository secrets (Settings -> Secrets and variables ->
# Actions), which .github/workflows/build.yml reads at release time:
#
#   SIGNING_KEY      base64 of upload-keystore.jks
#   KEY_ALIAS        alias inside the keystore
#   KEY_PASSWORD     key password
#   STORE_PASSWORD   keystore password
#
# The keystore itself is NEVER committed — it lives only in GitHub secrets and
# in your own offline backup.
#
# Usage
#   scripts/set_signing_secrets.sh                     # interactive
#   scripts/set_signing_secrets.sh --keystore path/to/upload-keystore.jks \
#       --alias upload --key-password PW --store-password PW
#   scripts/set_signing_secrets.sh --print             # just print the values,
#                                                      # for pasting into the
#                                                      # GitHub web UI
#
# Requires either `gh` authenticated with permission to write Actions secrets,
# or GITHUB_TOKEN in the environment.
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${REPO:-$(cd "$REPO_ROOT" && git remote get-url origin 2>/dev/null \
  | sed -e 's#^https://github.com/##' -e 's#^git@github.com:##' -e 's#\.git$##')}"

KEYSTORE="" ALIAS="" KEY_PW="" STORE_PW="" PRINT_ONLY=0

while (( $# )); do
  case "$1" in
    --keystore)       KEYSTORE="$2"; shift 2 ;;
    --alias)          ALIAS="$2"; shift 2 ;;
    --key-password)   KEY_PW="$2"; shift 2 ;;
    --store-password) STORE_PW="$2"; shift 2 ;;
    --repo)           REPO="$2"; shift 2 ;;
    --print)          PRINT_ONLY=1; shift ;;
    -h|--help)        sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$KEYSTORE" ]]; then
  for candidate in \
      "$REPO_ROOT/signing-handoff/upload-keystore.jks" \
      "$REPO_ROOT/android/app/upload-keystore.jks"; do
    [[ -f "$candidate" ]] && { KEYSTORE="$candidate"; break; }
  done
fi
[[ -f "$KEYSTORE" ]] || {
  echo "Keystore not found. Pass --keystore /path/to/upload-keystore.jks" >&2
  echo "(Generate one with: bash android/generate_keystore.sh)" >&2
  exit 1; }

: "${ALIAS:=upload}"
if [[ -z "$KEY_PW" ]]; then
  read -r -s -p "Key password for alias '$ALIAS': " KEY_PW; printf '\n'
fi
if [[ -z "$STORE_PW" ]]; then
  read -r -s -p "Keystore (store) password: " STORE_PW; printf '\n'
fi

[[ -n "$KEY_PW" && -n "$STORE_PW" ]] || { echo "passwords must not be empty" >&2; exit 1; }

# Prove the credentials work BEFORE uploading them, so CI does not fail later.
if command -v keytool >/dev/null 2>&1; then
  if keytool -list -keystore "$KEYSTORE" -alias "$ALIAS" \
        -storepass "$STORE_PW" -keypass "$KEY_PW" >/dev/null 2>&1; then
    echo "✓ keytool accepted the keystore, alias and both passwords."
  else
    echo "✗ keytool rejected these credentials for '$KEYSTORE'." >&2
    echo "  Fix them here — uploading a wrong pair just moves the failure to CI." >&2
    exit 1
  fi
else
  echo "! keytool not installed — skipping local keystore validation."
fi

B64="$(base64 -w 0 "$KEYSTORE" 2>/dev/null || base64 "$KEYSTORE" | tr -d '\n')"
echo "Keystore : $KEYSTORE ($(stat -c %s "$KEYSTORE" 2>/dev/null || wc -c <"$KEYSTORE") bytes)"
echo "Base64   : ${#B64} characters"
echo "Repo     : $REPO"

if (( PRINT_ONLY )); then
  cat <<EOF

Paste these into GitHub -> $REPO -> Settings -> Secrets and variables -> Actions
-> New repository secret (four separate secrets):

  Name: SIGNING_KEY
  Value:
$B64

  Name: KEY_ALIAS
  Value: $ALIAS

  Name: KEY_PASSWORD
  Value: $KEY_PW

  Name: STORE_PASSWORD
  Value: $STORE_PW
EOF
  exit 0
fi

command -v gh >/dev/null 2>&1 || {
  echo "GitHub CLI (gh) not found. Re-run with --print and paste into the web UI." >&2
  exit 1; }

set_secret() {
  local name="$1" value="$2"
  if printf '%s' "$value" | gh secret set "$name" --repo "$REPO" --body - >/dev/null 2>&1; then
    echo "✓ $name"
  else
    echo "✗ $name failed" >&2
    return 1
  fi
}

FAILED=0
set_secret SIGNING_KEY    "$B64"      || FAILED=1
set_secret KEY_ALIAS      "$ALIAS"    || FAILED=1
set_secret KEY_PASSWORD   "$KEY_PW"   || FAILED=1
set_secret STORE_PASSWORD "$STORE_PW" || FAILED=1

if (( FAILED )); then
  cat >&2 <<EOF

Could not write secrets. This needs a token with 'actions: write' on $REPO
(the usual cause is HTTP 403 "Resource not accessible by integration").

Options:
  1. Re-run with --print and paste the four values into the GitHub web UI.
  2. Or use an admin token:  GH_TOKEN=ghp_xxx $0
EOF
  exit 1
fi

echo
echo "All four secrets are set. Next release build will be signed with this key."
echo "BACK UP $KEYSTORE and its passwords offline — losing them means every"
echo "existing user has to uninstall before they can update again."
