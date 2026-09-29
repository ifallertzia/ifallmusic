# IfallMusic 2.4.0 (build 13)

## What's new

- **Stable release signing.** Every release APK is now signed with one permanent
  release key (`upload`, RSA-2048, valid until 2054) that is stored as an
  encrypted GitHub Actions secret and decoded to a temporary path at build time.
  Because the signing certificate never changes, **new versions install straight
  over the old one** — the "App not installed as package conflicts with an
  existing package" error is fixed for good.
- **Signature verified before publishing.** CI reads the certificate out of the
  built APK and compares its SHA-256 fingerprint with the release keystore. A
  debug-signed or mismatched APK can no longer be published by accident.
- **Automatic build number.** The Android `versionCode` (`+13` in
  `pubspec.yaml`) is incremented on every release, so Android always treats the
  new APK as an update rather than a downgrade or a duplicate.
- **Smarter update check.** The in-app updater now reads a `latest.json`
  manifest published with each release and compares the build number as well as
  the version, so a rebuilt release is still detected.
- **Version visible in the app.** Settings → About now shows the exact installed
  version *and* build number read from the APK itself
  (`IfallMusic · 2.4.0 (build 13)`), which makes it obvious at a glance whether
  you are running the new build.
- Keystore material is never committed: the signing key, alias and passwords
  live only in GitHub secrets and in the owner's offline backup.

## One-time note for existing installs

If the copy currently on your phone was signed with the older temporary debug
key, Android will reject *this* update once. Back up your library from
Settings → Backup library, uninstall, install this APK, then restore. Every
update after this one installs in place. The package ID remains `com.saxify.app`.

# IfallMusic 2.3.6

## What's new

- **Library screen fixed:** a missing tab counter made the whole Library page crash into a blank screen on open. Counters now cover every tab (including the new On-device tab), with a regression test guarding the mapping.
- **Playback fixed:** the Innertube stream resolver was re-synced with YouTube's current player clients (lead client corrected and refreshed from yt-dlp's live roster), so tracks load again after YouTube's latest client changes.
- Smarter stream validation: HEAD-probe timeouts and transient errors no longer blacklist good formats or burn the resolution budget; unproven URLs are handed to the player instead of stalling the queue.
- Tighter resolve budgets (Innertube 18s + legacy 12s) fit inside the song-load timeout, so a failing track fails fast with a clear reason and auto-advances instead of hanging for half a minute.

# IfallMusic 2.3.5

## What's new

- Playback resolver overhaul: rotating Innertube clients with a decipher-capable fallback engine, so streams keep working when YouTube changes signatures.
- Mid-stream failures now evict the stale stream URL and resume playback at the same position from a working source.
- New **On device** music library — browse and play the songs, albums and artists already stored on your phone via the MediaStore, with a fast re-scan and cached results.
- Local results now appear in search above web results, alongside a new voice-search mic button.
- New playback settings: skip silence, plus a playback cache manager with size display, pruning and a clear action.
- Android Auto browse roots for Liked songs, playlists, downloads and your on-device library.
