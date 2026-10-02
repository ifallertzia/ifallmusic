# Android release signing — permanent setup

This document is the single source of truth for how IfallMusic APKs are signed
and released. It exists to stop the

> *"App not installed as package conflicts with an existing package"*

error for good. That error has exactly one cause: **the new APK is signed with a
different certificate than the one already installed.** Package ID
(`com.ifallmusic.app`) and version code do not matter when the certificate differs.

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
| Validity | 10,000 days — 2026-10-02 → **2054-02-17** |
| Signature | `sha256WithRSAEncryption` |
| Distinguished name | `CN=Ifallertzia, OU=IfallMusic Release Signing, O=IfallMusic, L=Mumbai, ST=Maharashtra, C=IN` |
| Certificate SHA-256 | `55:0A:94:D9:9F:33:34:A2:71:1B:09:AF:9F:80:18:26:F5:C4:B5:C9:87:7D:0F:71:5C:54:3A:B2:03:87:BA:11` |
| Certificate SHA-1 | `20:69:98:7A:57:4B:22:06:41:04:A5:5E:6F:E6:D1:83:29:A2:FA:7F` |
| Keystore SHA-256 | `5602548528bd545e929211b4331b8147a40f506a755bf9ae93f3490b7976d2a2` (2298 bytes) |

These values were re-pinned on 2026-09-29 to the key that is actually held in the
`SIGNING_KEY` secret (`scripts/ci_prepare_signing.sh` carries the same constants).
Every release up to v2.3.6 was **debug-signed**, because the signing secrets did
not exist until 2026-09-29 — so no published APK is tied to any earlier release
certificate, and existing installs need one uninstall/reinstall whichever key is
used from here on.

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

## 4. CI — `scripts/ci_prepare_signing.sh`

Both workflows call this one script, so a release build and a PR build validate
the signing identity identically. It:

1. Checks that all four secrets are present. `SIGNING_REQUIRED=true`
   (`build.yml`) fails when none are set, because a release must never ship
   debug-signed; `SIGNING_REQUIRED=false` (`build_apk.yml`) warns instead, since
   a fork PR has no secret access. A *partially* configured set always fails,
   naming exactly which keys are missing.
2. Decodes `SIGNING_KEY` into `${RUNNER_TEMP}/signing/upload-keystore.jks` —
   a **temporary path outside the checkout**, dir `700`, file `600`. Newlines,
   tabs and spaces from a copy/paste are stripped first, so a line-wrapped
   secret still works.
3. Prints **lengths and SHA-256 digests only** — never a secret value. Those
   digests are what make a truncated or wrong paste obvious.
4. Asserts the JKS magic bytes are `feedfeed`.
5. Validates with `keytool` in **three stages**, because each credential fails
   differently and the message says exactly which secret to fix. `keytool` writes
   its diagnostics to **stdout**, not stderr, so both streams are captured —
   reading only stderr is what first produced an empty explanation.
   - `keytool -list` with no `-alias` → proves `STORE_PASSWORD` and keystore
     integrity, and inventories the aliases actually present.
   - `keytool -list -v -alias …` → proves `KEY_ALIAS` exists. On mismatch the
     error names the real aliases in the keystore.
   - `keytool -importkeystore` into a throwaway PKCS12 → proves `KEY_PASSWORD`.
     `-list` never checks it, because it reads certificate metadata and does not
     decrypt the private key; importing does. The throwaway file is deleted
     immediately.

   It also captures the certificate SHA-256, DN and validity for the report.
6. Compares the decoded file against the **pinned fingerprint** of the release
   key. This runs *after* `keytool` deliberately: a corrupted paste and a
   legitimately different keystore hash differently in exactly the same way, but
   only `keytool` can tell them apart — a tampered JKS fails its SHA-1 integrity
   digest, whereas a different valid key opens cleanly. So by this point
   corruption has already been rejected, and a mismatch means "a real, valid
   keystore — just not the pinned one", which is a policy question. It therefore
   warns by default and prints the exact constants needed to re-pin.
7. Writes a pass/fail diagnostics table to the job summary.

Every failure path emits a `::error::` annotation, because Actions log archives
are not always retrievable and annotations always are.

### Rotating the key

The pinned constants live at the top of `scripts/ci_prepare_signing.sh`:
`EXPECTED_KEYSTORE_SHA256`, `EXPECTED_KEYSTORE_BYTES`, `EXPECTED_BASE64_SHA256`,
`EXPECTED_BASE64_CHARS`, `EXPECTED_CERT_SHA256`. After a *deliberate* rotation,
regenerate them:

```bash
sha256sum upload-keystore.jks
wc -c < upload-keystore.jks
base64 -w 0 upload-keystore.jks | tr -d '\n' | sha256sum
base64 -w 0 upload-keystore.jks | tr -d '\n' | wc -c
keytool -list -v -alias upload -keystore upload-keystore.jks | awk -F': ' '/SHA256:/{print $2}' | tr -d ':'
```

To make a mismatch **fatal** instead of advisory, set `SIGNING_ENFORCE_FINGERPRINT: 'true'`
in the workflow env. The default is advisory on purpose: the two hard guarantees
are that `keytool` proves the keystore is structurally valid with all three
passwords correct, and that `build.yml` proves the finished APK carries *this*
keystore's certificate. Pinning hard would block a legitimate key that simply
is not the one this script was first written against.

## 5. CI — `.github/workflows/build.yml`

Triggered by `push` of a `v*` tag (and `workflow_dispatch`). Steps:

1. Check out, install JDK 21 (matches AGP 9.1.0 / Gradle 9.3.1) and stable Flutter.
2. `scripts/ci_prepare_signing.sh` with `SIGNING_REQUIRED=true` — fails the run
   immediately if the signing identity is absent or wrong.
3. Analyze and test.
4. `flutter build apk --release` with `SIGNING_KEYSTORE_FILE` pointing at the
   temporary path and the credentials exported as environment variables. Fails
   if Gradle logs its debug-signing warning despite the secrets being present.
5. **Verify the APK's own certificate** with `apksigner verify --print-certs`
   (falling back to `keytool -printcert -jarfile`) and compare its SHA-256 with
   the keystore's. The digest is extracted by matching the 64-hex payload on the
   `certificate SHA-256 digest:` line, never by field position, because
   apksigner renamed that line in build-tools 37 (`Signer #1 certificate SHA-256
   digest:` → `V2 Signer: certificate SHA-256 digest:`) and a positional parser
   then read the label as if it were the digest. A mismatch fails the run, and an
   unreadable certificate now fails the run too — this is the guarantee that a
   debug-signed or unverifiable APK can never be published.
6. Write `latest.json` (`version`, `build`, `tag`, `apk`, `releasedAt`) and
   publish a GitHub Release with **`app-release.apk`** — that exact asset name
   is what the in-app updater looks for.
7. **Clean up `if: always()`** — removes `${RUNNER_TEMP}/signing` and any stray
   `android/app/upload-keystore.jks` / `android/key.properties`, then fails the
   step if anything key-related survived. On success *and* on failure.

## 6. CI — `.github/workflows/build_apk.yml`

Push/PR gate: analyze → test → release-mode APK → release-mode AAB, signed with
the same key when secrets are available (warning, not failure, when they are
not — fork PRs cannot read secrets). It calls the same
`ci_prepare_signing.sh` with `SIGNING_REQUIRED=false`, and cleans up the
temporary keystore with `if: always()` too.

On a push to `main` it additionally:

1. Runs `scripts/bump_build_number.sh` → `version: x.y.z+**N+1**` in
   `pubspec.yaml`, and `scripts/sync_version.sh` → `lib/config/branding.dart`.
2. Commits with `[skip ci]` so it cannot retrigger itself.
3. Force-moves tag `v<version>`, which triggers `build.yml` to publish the
   signed release.

This job is skipped when the build job fails, so a failed signing step never
leaves a stray version bump or a moved tag behind.

---

## 7. Version and build-number rule

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

## 8. In-app update flow

`lib/core/services/update_service.dart`:

- `GET https://api.github.com/repos/ifallertzia/ifallmusic/releases/latest`
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

## 9. Releasing

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

## 10. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| "package conflicts with an existing package" on install | Old build signed with a different certificate | One-time uninstall + reinstall. Afterwards signing is stable. |
| Workflow fails: *Missing signing secrets* | Secrets not set (or set on the wrong repo/branch scope) | Add all four under Settings → Secrets and variables → Actions |
| Workflow fails: *not the pinned release key* | `SIGNING_KEY` truncated or a different keystore | Compare the printed sha256 with `EXPECTED_KEYSTORE_SHA256`; re-paste the correct base64 |
| Workflow fails: *KEY_PASSWORD does not unlock alias* | Key password wrong | Re-set `KEY_PASSWORD` |
| Workflow fails: *not a JKS keystore (magic=…)* | `SIGNING_KEY` truncated, or base64 of the wrong file | Re-run `base64 -w 0 upload-keystore.jks` and replace the secret |
| Workflow fails: *keytool could not read alias 'upload'* | Alias or password does not match the keystore | Re-set `KEY_ALIAS` / `KEY_PASSWORD` / `STORE_PASSWORD` |
| Workflow fails: *APK is NOT signed with the release keystore* | Gradle did not receive the env vars, **or** the parser read apksigner's label instead of its digest | Check `SIGNING_KEYSTORE_FILE` etc. in the build step. The base64 `apksigner verify` annotation on the run shows the raw output; build-tools 37 prints `V2 Signer: certificate SHA-256 digest: <hex>` where 35 and older printed `Signer #1 certificate SHA-256 digest: <hex>` |
| Workflow fails: *Signature not verified* | Neither apksigner nor keytool could read the APK certificate | Read the base64 tool annotation on the run, then update the extraction in the verify step to the new label |
| Update not offered in-app | Release missing, tag not newer, or no `app-release.apk` asset | Confirm the release is marked *latest* and the asset name is exact |
| `HTTP 403: Resource not accessible by integration` when setting secrets | The automation token lacks `actions: write` | Grant the GitHub App secrets permission, or use an admin token / the web UI |

### Key rotation

Rotating the signing key **breaks updates for every existing user** — they must
uninstall first. Only do it if the key is compromised, and say so prominently in
the release notes.
