# IfallMusic 2.5.0 (build 15)

## What's new

- Some known bugs fixed.
- Playlist button added at the bottom of the player — add the song that is
  playing to a playlist, or start a new one, without leaving the player.
- The sleep timer now sits in the top bar of the player, next to the lyrics
  button.
- Settings tidied up: streaming quality options removed, small gaps added
  between rows, and Contact / Report / Feedback moved into its own section at
  the bottom.

## How to update

Download `app-release.apk` below and install it over your current app. It is
signed with the same release key as before, so it installs in place — your
library, playlists and downloads stay exactly as they are.

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
