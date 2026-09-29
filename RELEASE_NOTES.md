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

## Installation note

This build uses a temporary debug signing key when a permanent release key is
not configured. Android may refuse to install it over an existing version.
Back up your library in Settings first, then uninstall, install the latest APK
and restore the backup. This may be needed again for future builds until stable
signing is configured. The package ID remains `com.saxify.app`.
