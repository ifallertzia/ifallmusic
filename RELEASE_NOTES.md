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
