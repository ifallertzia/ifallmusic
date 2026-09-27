# Fixing the "App not installed / package conflicts" error

## Problem
When installing a new APK over the old IfallMusic, Android says:

> **App not installed as package conflicts with an existing package.**

Two things cause this:

1. **Different signing keys.** The previous `build.gradle.kts` signed release
   APKs with the Android `debug` keystore, which is auto-generated per machine.
   A release built on a different computer (or after the debug keystore was
   wiped) carries a different signature, so Android rejects it as a "conflict".
2. **Version code not bumped.** Android will not replace an existing install
   unless the new APK has a higher `versionCode`.

## What's fixed in this repo

- `android/app/build.gradle.kts` now has a dedicated **release signing config**
  that reads from `android/key.properties` and signs release APKs with a
  consistent keystore at `android/app/upload-keystore.jks`.
- `android/key.properties` contains the keystore path and passwords.
- `android/generate_keystore.sh` generates the release keystore the first time.
- `versionCode` / `versionName` bumped to `2.3.1+7` in `pubspec.yaml`.
- The in-app update dialog no longer dumps the full GitHub release body; it
  shows a clean two-line changelog:
  - Lyrics support added
  - Important bug fixes
- The "What's new" card on the Home screen was simplified to the same two
  lines (no more long list of old changes).
- A migration message is shown after download if installation still fails,
  telling users to back up → uninstall → reinstall (one-time only).
- `key.properties` and `*.jks` are added to `.gitignore` so credentials aren't
  accidentally pushed.

## How to build the signed release APK

From the repo root, on a machine with Flutter + Android SDK + JDK installed:

```bash
# 1. One-time: generate the stable release keystore.
#    (Creates android/app/upload-keystore.jks — BACK THIS FILE UP.)
bash android/generate_keystore.sh

# 2. Build the signed APK.
flutter build apk --release
```

The signed APK lands at:

```
build/app/outputs/flutter-apk/app-release.apk
```

Upload **that exact file** to the GitHub release with asset name
`app-release.apk` — the in-app updater looks for that name.

## One-time migration for existing users

Users who already have an older IfallMusic installed (signed with the old
debug key) will still see "package conflicts" the first time they try to
install this new APK. They need to:

1. Open the **old** app → Settings → **Backup library** (saves liked songs,
   playlists, etc. as a code).
2. **Uninstall** the old IfallMusic.
3. Install the new `app-release.apk`.
4. In Settings → **Import playlist code**, paste their backup.

After this migration, **all future in-app updates will install over the
existing app** because they will all be signed with the same release
keystore.

## Important: keep the keystore safe!

- Back up `android/app/upload-keystore.jks` to a password manager or private
  cloud.
- **Never** delete it after releasing. If you lose the keystore, you can never
  publish another update for `com.saxify.app` — you'd have to change the
  package name and release a "new app", forcing everyone to migrate again.
