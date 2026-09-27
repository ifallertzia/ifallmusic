# IfallMusic 2.3.3

## What's new

- Tighter lyric line spacing in Static and Synced modes, with room for wrapped lines and larger text.
- Synced lyrics still follow the current line and support tap-to-seek.
- Settings → Website & latest app download links to https://sidify.vercel.app, where the latest APK link will be maintained.
- Restored APK builds without requiring release-signing secrets.
- Keeps the recent player download progress, saved equalizer presets and compact lyrics controls.

## Installation note

This build uses a temporary debug signing key when a permanent release key is
not configured. Android may refuse to install it over an existing version.
Back up your library in Settings first, then uninstall, install the latest APK
and restore the backup. This may be needed again for future builds until stable
signing is configured. The package ID remains `com.saxify.app`.
