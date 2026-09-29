# Android APK updates — status

> **Superseded by [`docs/RELEASE_SIGNING.md`](RELEASE_SIGNING.md).**
>
> This page used to describe a *temporary* arrangement in which release APKs
> were signed with the CI runner's debug key whenever no keystore was
> configured. That was the direct cause of
> "App not installed as package conflicts with an existing package", because a
> runner debug key is not stable between builds.
>
> A permanent release signing identity is now configured. Read
> `docs/RELEASE_SIGNING.md` for the keystore details, the four GitHub secrets,
> the Gradle contract and the release procedure.

## What is in place now

- **One stable release key** (`upload-keystore.jks`, alias `upload`, RSA-2048,
  valid until 2054) signs every release. It is stored as the encrypted
  `SIGNING_KEY` GitHub Actions secret and decoded to a temporary path at build
  time, then deleted — pass or fail.
- **No hardcoded credentials.** `android/app/build.gradle.kts` reads the alias
  and passwords from environment variables, falling back to the git-ignored
  `android/key.properties` for local builds. A *partial* configuration fails the
  build rather than silently signing with the wrong key.
- **Signature verification in CI.** The built APK's certificate SHA-256 is
  compared with the keystore's before anything is published, so a debug-signed
  APK can never reach a GitHub Release again.
- **Automatic build number.** `versionCode` (pubspec's `+N`) is incremented on
  every release by `scripts/bump_build_number.sh`, so Android always sees the
  new APK as an update.
- **In-app update check** compares version *and* build number against
  GitHub Releases, downloads `app-release.apk` with progress, and opens the
  system installer.

## One-time step for users on an old debug-signed build

Android compares certificates, so an install signed with the old temporary key
still cannot be updated in place — **once**.

1. Back up the library from Settings → **Backup library**.
2. Uninstall the old app.
3. Install the latest APK (in-app updater, GitHub Release, or
   https://sidify.vercel.app).
4. Restore the library backup.

Every update after that installs in place. The package ID is unchanged:
`com.saxify.app`.

## Never do this

- Do not commit `upload-keystore.jks`, `key.properties`, or any password. This
  repository is public.
- Do not generate a new keystore for a routine release. A new key means every
  existing user has to uninstall.
- Do not paste the keystore, its base64 form or its passwords into chat, an
  issue, or a commit message.
