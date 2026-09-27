# IfallMusic 2.3.1

## What's new

- **Lyrics support added** — view synced lyrics for songs from the player.
- **Important bug fixes** — playback, queue and download stability improvements.

## Update note

This release is signed with a stable release keystore so future updates install
over the existing app cleanly. If you are upgrading from a very old build that
was signed with a different key and Android shows
**"App not installed as package conflicts with an existing package"**:

1. Open IfallMusic → Settings → **Backup library** to save your liked songs and
   playlists.
2. Uninstall the old IfallMusic from your phone.
3. Install the new `app-release.apk`.
4. Restore your library from the backup.

After this one-time migration, every future in-app update will install without
conflicts.

## Build instructions

From the repo root:

```bash
# First time only — generate the release keystore (keeps it consistent across builds)
bash android/generate_keystore.sh

# Build the signed release APK
flutter build apk --release
```

The signed APK lands at `build/app/outputs/flutter-apk/app-release.apk` — upload
that to the GitHub release as `app-release.apk` so the in-app updater picks it up.
