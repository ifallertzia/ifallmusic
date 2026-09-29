#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# sync_version.sh — copy pubspec.yaml's version into lib/config/branding.dart.
#
# branding.dart holds compile-time constants (About card, User-Agent header,
# diagnostics). If pubspec is bumped without updating them the app reports a
# stale version, which makes it impossible to tell a new build from an old one.
# This script is called by bump_build_number.sh and by CI.
#
# Idempotent: running it twice changes nothing the second time.
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBSPEC="$REPO_ROOT/pubspec.yaml"
BRANDING="$REPO_ROOT/lib/config/branding.dart"

[[ -f "$PUBSPEC" ]]  || { echo "missing $PUBSPEC" >&2; exit 1; }
[[ -f "$BRANDING" ]] || { echo "missing $BRANDING" >&2; exit 1; }

raw="$(awk '/^version:/ { sub(/^version:[[:space:]]*/, ""); print; exit }' "$PUBSPEC" | tr -d '[:space:]')"
[[ -n "$raw" ]] || { echo "pubspec.yaml has no version" >&2; exit 1; }

VERSION="${raw%%+*}"
BUILD="${raw##*+}"
[[ "$BUILD" =~ ^[0-9]+$ ]] || BUILD=0

before="$(sha256sum "$BRANDING" | cut -d' ' -f1)"

sed -i \
  -e "s|^\(\s*static const String versionLabel = \)'.*';|\1'${VERSION}';|" \
  -e "s|^\(\s*static const String buildLabel = \)'.*';|\1'${BUILD}';|" \
  -e "s|^\(\s*static const String userAgent = \)'IfallMusic/[^ ]*\(.*\)';|\1'IfallMusic/${VERSION}\2';|" \
  "$BRANDING"

after="$(sha256sum "$BRANDING" | cut -d' ' -f1)"

if [[ "$before" == "$after" ]]; then
  echo "branding.dart already in sync with ${VERSION}+${BUILD}."
else
  echo "branding.dart synced to version ${VERSION} (build ${BUILD})."
fi
