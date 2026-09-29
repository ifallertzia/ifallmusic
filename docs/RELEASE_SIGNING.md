# Android release signing — permanent setup

This document is the single source of truth for how IfallMusic APKs are signed
and released. It exists to stop the

> *"App not installed as package conflicts with an existing package"*

error for good. That error has exactly one cause: **the new APK is signed with a
different certificate than the one already installed.** Package ID
(`com.saxify.app`) and version code do not matter when the certificate differs.

The fix is to sign every release with the *same* key, forever.

---

## 1. The release signing identity

Generated once with `keytool`-equivalent parameters and validated
cryptographically (integrity digest, key-protection checksum, RSA-2048,
sign/verify round-trip against its own certificate):

| Field | Value |
| --- | --- |
| Keystore file | `upload-keystore.jks` |
| Keystore type | JKS (magic `0xFEEDFEED`, format version 2) |
| Alias | `upload` |
| Key algorithm | RSA, 2048-bit |
| Validity | 10,000 days — 2026-09-29 → **2054-02-14** |
| Signature | `sha256WithRSAEncryption` |
| Distinguished name | `CN=Ifallertzia, OU=IfallMusic Release Signing, O=IfallMusic, L=Mumbai, ST=Maharashtra, C=IN` |
| Certificate SHA-256 | `BD:0C:84:9A:30:7E:66:5E:94:82:B6:54:A4:44:C0:82:E1:66:5C:B3:42:2B:4A:C5:76:9F:0D:D3:04:27:0E:54` |
| Certificate SHA-1 | `C8:5D:08:3A:35:48:B5:22:5F:4D:FA:BC:39:61:06:AB:94:E0:B8:20` |

The fingerprints above are public (they ship inside every APK) and are recorded
here so a built APK can be checked against the intended key at any time.

The keystore binary, its base64 form and its passwords are **never committed**.
`/signing-handoff/`, `*.jks`, `*.keystore` and `/android/key.properties` are all
git-ignored, and this repository is **public**.

### Back it up now

The private key cannot be reconstructed from an APK, and cannot be recovered
from GitHub secrets in readable form. Store these three things somewhere offline
(encrypted drive, password manager attachment):

1. `upload-keystore.jks`
2. the store password
3. the key password (identical to the store password here)

Lose them and every existing user must uninstall before they can update again.

---

## 2. The four GitHub Actions secrets

| Secret | Contents |
| --- | --- |
| `SIGNING_KEY` | `base64 -w 0 upload-keystore.jks` — a single line, no newlines |
| `KEY_ALIAS` | `upload` |
| `KEY_PASSWORD` | the key password |
| `STORE_PASSWORD` | the keystore password |

Set them in **Settings → Secrets and variables → Actions → New repository
secret**.

Automated upload (needs a token with `actions: write` on the repo):

```bash
bash scripts/set_signing_secrets.sh \
  --keystore signing-handoff/upload-keystore.jks --alias upload
```

No terminal? Print the four values and paste them into the web UI:

```bash
bash scripts/set_signing_secrets.sh --print
```

The script validates the keystore with `keytool` *before* uploading, so a wrong
password fails locally instead of in CI.

> The legacy names `ANDROID_RELEASE_KEYSTORE_BASE64`, `ANDROID_RELEASE_KEY_ALIAS`,
> `ANDROID_RELEASE_KEY_PASSWORD` and `ANDROID_RELEASE_STORE_PASSWORD` are still
> accepted by `build_apk.yml` as a fallback.

---

## 3. Gradle contract — no hardcoded credentials

`android/app/build.gradle.kts` resolves signing material in this order:

1. **Environment variables** (what CI sets):
   `SIGNING_KEYSTORE_FILE`, `SIGNING_KEYSTORE_TYPE`, `SIGNING_KEY_ALIAS`,
   `SIGNING_KEY_PASSWORD`, `SIGNING_STORE_PASSWORD`
   (short aliases `KEY_ALIAS` / `KEY_PASSWORD` / `STORE_PASSWORD` also read).
2. **`android/key.properties`** for local builds — git-ignored.

Behaviour:

- **Complete configuration** → the release build type is signed with the stable
  key, and the resolved keystore/alias are logged.
- **Partial configuration** → the build **fails** with a message naming exactly
  which inputs are missing. It never silently signs with a different key,
  because that is what produces un-installable APKs.
- **No configuration at all** → falls back to the debug key with a loud warning.
  Only reachable on fork PRs that have no secret access. Tagged releases never
  take this path.

`storeType` is set explicitly (`JKS`, inferred from the file extension when not
given). This matters: since JDK 9 the platform default keystore type is PKCS12,
and an implicit type mismatch surfaces as a confusing "invalid keystore" error.

Local builds:

```bash
bash android/generate_keystore.sh          # only if you have NO existing key
# writes android/key.properties, then:
flutter build apk --release
```

---

## 4. CI — `.github/workflows/build.yml`

Triggered by `push` of a `v*` tag (and `workflow_dispatch`). Steps:

1. Check out, install JDK 21 (matches AGP 9.1.0 / Gradle 9.3.1) and stable Flutter.
2. **Fail immediately if any of the four secrets is missing** — a release must
   never ship debug-signed.
3. Decode `SIGNING_KEY` into `${RUNNER_TEMP}/signing/upload-keystore.jks` —
   a **temporary path outside the checkout**, mode `600`, parent dir `700`.
   Newlines/whitespace from copy-paste are stripped first.
4. Assert the JKS magic bytes are `feedfeed`.
5. `keytool -list -v -alias upload -storepass … -keypass …` — validates the
   store password, alias **and** key password before any Flutter build, and
   captures the certificate SHA-256.
6. Analyze, test, then `flutter build apk --release` with the credentials
   exported as environment variables.
7. **Verify the APK's own certificate** with `apksigner verify --print-certs`
   (falling back to `keytool -printcert -jarfile`) and compare its SHA-256 with
   the keystore's. A mismatch fails the run — this is the guarantee that a
   debug-signed APK can never be published again.
8. Write `latest.json` (`version`, `build`, `tag`, `apk`, `releasedAt`) and
   publish a GitHub Release with **`app-release.apk`** — that exact asset name
   is what the in-app updater looks for.
9. **Clean up `if: always()`** — removes `${RUNNER_TEMP}/signing` and any stray
   `android/app/upload-keystore.jks` / `android/key.properties`, then fails the
   step if anything key-related survived. On success *and* on failure.

## 5. CI — `.github/workflows/build_apk.yml`

Push/PR gate: analyze → test → release-mode APK → release-mode AAB, signed with
the same key when secrets are available (warning, not failure, when they are
not — fork PRs cannot read secrets).

On a push to `main` it additionally:

1. Runs `scripts/bump_build_number.sh` → `version: x.y.z+**N+1**` in
   `pubspec.yaml`, and `scripts/sync_version.sh` → `lib/config/branding.dart`.
2. Commits with `[skip ci]` so it cannot retrigger itself.
3. Force-moves tag `v<version>`, which triggers `build.yml` to publish the
   signed release.

---

## 6. Version and build-number rule

`pubspec.yaml` carries `version: x.y.z+build`. Flutter maps `x.y.z` →
`versionName` and `build` → `versionCode`.

- **`build` must increase on every release.** Android only treats an APK as an
  update when `versionCode` is strictly higher; a flat or lower value is
  rejected, and that rejection is reported with the same "package conflict"
  wording as a signature mismatch. CI bumps it automatically.
- Bump `x.y.z` for user-visible changes so the in-app updater can detect them
  from the tag alone.
- `lib/config/branding.dart` (`versionLabel`, `buildLabel`, `userAgent`,
  `fullVersionLabel`) is regenerated from `pubspec.yaml` by
  `scripts/sync_version.sh` — never edit those by hand.

Manual bump:

```bash
bash scripts/bump_build_number.sh            # 2.4.0+13 -> 2.4.0+14
bash scripts/bump_build_number.sh 2.5.0      # 2.4.0+13 -> 2.5.0+14
bash scripts/bump_build_number.sh --check    # print, change nothing
```

---

## 7. In-app update flow

`lib/core/services/update_service.dart`:

- `GET https://api.github.com/repos/ifallertzia/Saxify-v1/releases/latest`
- Prefers the `latest.json` asset for an exact `version` + `build` comparison;
  falls back to the release tag (`v2.4.0` → `2.4.0`) when it is absent.
- `UpdateService.isNewerBuild()` compares semantic version first, build number
  second — so a rebuild of the same `x.y.z` with a higher `versionCode` is
  still offered as an update.
- Downloads the `app-release.apk` asset with progress, then hands it to the
  Android installer via `open_filex`.
- `lib/ui/settings/update_dialog.dart` shows the short changelog; the release
  body on GitHub carries the full notes.

Check runs silently on app start (`lib/ui/shell/saxify_shell.dart`) and on
demand from Settings.

---

## 8. Releasing

```bash
# 1. write the user-facing notes for this release
$EDITOR RELEASE_NOTES.md

# 2. bump version + build number (also syncs branding.dart)
bash scripts/bump_build_number.sh 2.5.0

# 3. commit, merge to main, and either let CI move the tag or push it yourself
git tag -f v2.5.0 && git push -f origin v2.5.0
```

`build.yml` then builds, signature-verifies and publishes
`app-release.apk` + `latest.json` to the GitHub Release.

---

## 9. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| "package conflicts with an existing package" on install | Old build signed with a different certificate | One-time uninstall + reinstall. Afterwards signing is stable. |
| Workflow fails: *Missing signing secrets* | Secrets not set (or set on the wrong repo/branch scope) | Add all four under Settings → Secrets and variables → Actions |
| Workflow fails: *not a JKS keystore (magic=…)* | `SIGNING_KEY` truncated, or base64 of the wrong file | Re-run `base64 -w 0 upload-keystore.jks` and replace the secret |
| Workflow fails: *keytool could not read alias 'upload'* | Alias or password does not match the keystore | Re-set `KEY_ALIAS` / `KEY_PASSWORD` / `STORE_PASSWORD` |
| Workflow fails: *APK is NOT signed with the release keystore* | Gradle did not receive the env vars | Check `SIGNING_KEYSTORE_FILE` etc. in the build step |
| Update not offered in-app | Release missing, tag not newer, or no `app-release.apk` asset | Confirm the release is marked *latest* and the asset name is exact |
| `HTTP 403: Resource not accessible by integration` when setting secrets | The automation token lacks `actions: write` | Grant the GitHub App secrets permission, or use an admin token / the web UI |

### Key rotation

Rotating the signing key **breaks updates for every existing user** — they must
uninstall first. Only do it if the key is compromised, and say so prominently in
the release notes.
