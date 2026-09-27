# Android APK signing and manual updates

## Current distribution mode: no signing secrets required

At the owner's request, release APK builds temporarily use the runner's debug
key when no release keystore is configured. CI still runs Flutter analysis,
all unit/widget tests, and **release-mode APK and AAB builds** on branches/PRs
as well as main. Only a successful push build on main publishes a GitHub Release.
The debug signing fallback does not turn the release build into a debug build.

**This is not stable production signing and is not suitable for Play Store
publication.** Runner debug keys can change on every build. Keeping the package
ID (`com.saxify.app`) and increasing the version code does not fix a certificate
mismatch. In-place updates are not guaranteed, even between future releases.

## Download and install

Settings → **Website & latest app download** opens https://sidify.vercel.app.
The site owner maintains the current APK download link there; the app does not
assume a download path or scrape the site. The existing GitHub update check is
also available.

If Android reports a package/signature conflict:

1. Back up the library from Settings **before uninstalling**.
2. Uninstall the old app.
3. Install the latest APK from the website's download link.
4. Restore the library backup.

This may be necessary again until a permanent signing key is configured.

## Optional stable signing later

Recover the original private signing key if possible. It cannot be reconstructed
from a published APK. A newly generated key will not update an installation
signed with another key.

For local builds, put the key at `android/app/upload-keystore.jks` and create
`android/key.properties` (both are ignored by Git):

```properties
storeFile=upload-keystore.jks
keyAlias=YOUR_ALIAS
keyPassword=YOUR_KEY_PASSWORD
storePassword=YOUR_STORE_PASSWORD
```

For main-branch GitHub Actions builds, configure **all four** repository secrets:

- `ANDROID_RELEASE_KEYSTORE_BASE64` — base64 of the `.jks` / `.keystore` file
- `ANDROID_RELEASE_STORE_PASSWORD`
- `ANDROID_RELEASE_KEY_ALIAS`
- `ANDROID_RELEASE_KEY_PASSWORD`

No secrets: explicitly warned debug-key fallback. Partial/invalid configuration:
build fails rather than silently ignoring a configured signing identity.
Never commit private keys/passwords or paste them into chat. Back up the key and
credentials securely and reuse the same key for all subsequent releases.
