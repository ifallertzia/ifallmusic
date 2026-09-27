# IfallMusic 2.3.4

## What's new

- Fixed the Home "Playlists you may like" section — playlists and albums now open and play reliably instead of showing "Tracks unavailable".
- Playlist and album pages are fetched more robustly, with better handling of long playlists.
- All-new ifallertzia server branding across search headings, playlists, albums and the About card.
- Removed the song "Share · copy link" action.
- Removed external channel-open shortcuts from artist and label pages.

## Installation note

This build uses a temporary debug signing key when a permanent release key is
not configured. Android may refuse to install it over an existing version.
Back up your library in Settings first, then uninstall, install the latest APK
and restore the backup. This may be needed again for future builds until stable
signing is configured. The package ID remains `com.saxify.app`.
