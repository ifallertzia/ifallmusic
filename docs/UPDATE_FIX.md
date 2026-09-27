# Android package identity and update signing

The Android application ID is intentionally kept as `com.saxify.app`, and the
version in `pubspec.yaml` is incremented for each release. That preserves the
package identity and gives Android a higher `versionCode`.

## Critical: updates require the original private signing key

Android accepts an APK update only when its signing certificate matches the
installed app's certificate. A package ID or version bump cannot fix a
certificate mismatch. This checkout does **not** contain a signing keystore
(`android/app/upload-keystore.jks` is gitignored), and a signing certificate
cannot be reverse-engineered into its private key from an APK.

Before publishing, recover the exact keystore used to sign the app that users
already have installed. Do **not** run `android/generate_keystore.sh` as a fix
for a signature conflict: that generates a new identity and will make the
conflict permanent for existing installs. If the app was previously released
with an ephemeral GitHub Actions/debug key, the original key or its source
machine's debug keystore is required; if it has been lost, Android cannot
install a differently signed APK over that app. Users would need a one-time
uninstall/reinstall and library restore.

## Local signed APK

Put the recovered key at `android/app/upload-keystore.jks` and create the
ignored `android/key.properties` file:

```properties
storeFile=upload-keystore.jks
keyAlias=YOUR_ORIGINAL_ALIAS
keyPassword=YOUR_KEY_PASSWORD
storePassword=YOUR_STORE_PASSWORD
```

Then build with `flutter build apk --release`. Release builds now refuse to
fall back to the machine-specific debug key.

## GitHub Actions release signing

Configure these repository Actions secrets with values for that **same** key:

- `ANDROID_RELEASE_KEYSTORE_BASE64` — base64 of the original `.jks` file
- `ANDROID_RELEASE_STORE_PASSWORD`
- `ANDROID_RELEASE_KEY_ALIAS`
- `ANDROID_RELEASE_KEY_PASSWORD`

The workflow materializes the ignored key files only during the build. Never
commit or paste a signing keystore or its passwords into source/chat. The
published APK should be versioned above the installed one and signed with this
same keystore on every release.
