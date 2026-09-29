#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# bump_build_number.sh — auto-increment the Android build number.
#
#   pubspec.yaml   version: 2.4.0+13   ->   version: 2.4.0+14
#
# The build number is pubspec's `+N`, which Flutter feeds to Gradle as
# `versionCode`. Android only treats a new APK as an update when versionCode
# INCREASES, so this must move on every release — even when x.y.z stays the
# same. A flat or falling versionCode shows up as
# "App not installed as package conflicts with an existing package."
#
# Usage:
#   scripts/bump_build_number.sh            # +1 on the build number
#   scripts/bump_build_number.sh 2.5.0      # set x.y.z AND +1 the build number
#   scripts/bump_build_number.sh --set 42   # force build number to 42
#   scripts/bump_build_number.sh --check    # print current, change nothing
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBSPEC="$REPO_ROOT/pubspec.yaml"

[[ -f "$PUBSPEC" ]] || { echo "pubspec.yaml not found at $PUBSPEC" >&2; exit 1; }

current_line="$(awk '/^version:/ { print; exit }' "$PUBSPEC")"
[[ -n "$current_line" ]] || { echo "pubspec.yaml has no 'version:' line" >&2; exit 1; }

current_raw="${current_line#version:}"
current_raw="$(printf '%s' "$current_raw" | tr -d '[:space:]')"
current_version="${current_raw%%+*}"
current_build="${current_raw##*+}"
[[ "$current_build" =~ ^[0-9]+$ ]] || current_build=0

case "${1:-}" in
  --check)
    echo "$current_version+$current_build"
    exit 0
    ;;
  --set)
    new_build="${2:-}"
    [[ "$new_build" =~ ^[0-9]+$ ]] || { echo "--set needs a numeric build number" >&2; exit 1; }
    new_version="$current_version"
    ;;
  "")
    new_version="$current_version"
    new_build=$((current_build + 1))
    ;;
  *)
    new_version="${1#v}"
    [[ "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
      echo "version must look like x.y.z (got '$1')" >&2; exit 1; }
    new_build=$((current_build + 1))
    ;;
esac

new_line="version: ${new_version}+${new_build}"

if [[ "$new_line" == "$current_line" ]]; then
  echo "pubspec.yaml already at ${new_version}+${new_build} — nothing to do."
  exit 0
fi

# Replace only the first `version:` line, leaving dependency constraints alone.
awk -v repl="$new_line" '
  !done && /^version:/ { print repl; done=1; next }
  { print }
' "$PUBSPEC" > "$PUBSPEC.tmp"
mv "$PUBSPEC.tmp" "$PUBSPEC"

echo "pubspec.yaml: ${current_version}+${current_build}  ->  ${new_version}+${new_build}"

# Keep lib/config/branding.dart in step so the About card and the HTTP
# User-Agent never advertise a stale version.
if [[ -x "$REPO_ROOT/scripts/sync_version.sh" ]]; then
  "$REPO_ROOT/scripts/sync_version.sh"
fi
