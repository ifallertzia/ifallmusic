# IfallMusic 2.5.1 (build 18)

## What's new

- Lyrics now live at the bottom of the full player and load automatically when
  you scroll to them. Both static and synced lyrics remain available; if lyrics
  cannot be found, the player shows `iska nhi mila sori🥲` in the current UI accent.
- The full player now scrolls vertically: artwork smoothly shrinks as you move
  through playback controls, and pulling down at the top returns to the screen
  underneath.
- Startup cache repair no longer clears saved app preferences, protecting your
  likes, playlists, library and settings.
- Library opens on a neutral **Your Space** overview instead of selecting Liked
  songs.
- Home recommendations are presented as a compact, listening-based artwork grid,
  with **Play today's mix** and **Explore** below it. Search brand strips now use
  their logos.
- The default look is a calmer dark theme, with tighter spacing and an optional
  app-wide accent that leaves custom RGB colors intact.

## How to update

Download `app-release.apk` below and install it over your current app. The Android
application id and release-signing configuration are unchanged; the build number
has increased so Android can install this as an update. Your saved library and
playlists remain in place.

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
