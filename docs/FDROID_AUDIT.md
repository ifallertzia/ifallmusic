# F-Droid inclusion audit — Sidify (`com.ifallmusic.app`)

Date: 2026-10-15  
ApplicationId: `com.ifallmusic.app`  
pubspec: `version: 2.10.0+39` → versionName `2.10.0`, versionCode `39` (from Flutter Gradle plugin; matches `android/app/build.gradle.kts`)

## 1. Proprietary SDKs / trackers

| Check | Result |
| --- | --- |
| Firebase / Crashlytics / Analytics | **None** in `pubspec.yaml` or Android Gradle files |
| Google Play Services / Ads | **None** |
| Google Mobile Ads | **None** |
| Sentry / Mixpanel / Amplitude | **None** |

Dart dependencies are OSS packages (just_audio, audio_service, youtube_explode_dart, provider, etc.). Android extra deps: `androidx.core:core-ktx`, `desugar_jdk_libs` (Apache 2.0).

### Flags (not blockers if declared)

1. **NonFreeNet** — `youtube_explode_dart` + Innertube/YT Music clients talk to YouTube. Must be listed as an AntiFeature.
2. **google_fonts** — unused; **removed** from `pubspec.yaml`. The UI uses Material / bundled Flutter fonts only. No Google Fonts CDN at runtime. No `assets/fonts/` bundle required.
3. **speech_to_text** — on Android this often uses Google’s speech recognizer if present; it is not a compile-time GMS dependency.
4. **In-app GitHub APK updater** — disabled when compiled with `--dart-define=FDROID=true` and/or `--dart-define=FLAVOR=fdroid` (`lib/config/foss_build.dart`). F-Droid `prebuild` also `sed`-removes `REQUEST_INSTALL_PACKAGES`. GitHub CI builds omit the defines, so sideload updates still work.
5. **Cleartext traffic** is allowed (`usesCleartextTraffic="true"`). Prefer HTTPS-only for inclusion hygiene.

No `foss` / `googlePlay` Gradle product flavors: distribution is selected with dart-defines so existing CI (`flutter build apk --release`) is unchanged.

## 2. License

Previously **missing**. Added **MIT** `LICENSE` (OSI-approved) with copyright holder Siddharth (`lib/config/branding.dart`).

## 3. Prebuilt binaries in Git

No committed `.jar`, `.aar`, `.so`, or `.apk` files. Keystores are gitignored. Launcher PNGs and splash assets are source artwork, not native libraries.

## 4. Fastlane

Created `fastlane/metadata/android/en-US/` with title, short/full description, icon stand-in, and image READMEs.

**Still needed before GitLab MR:** 512×512 icon, 1024×500 feature graphic, 2+ phone screenshots.

## 5. Versioning & CI

- `versionCode` / `versionName` come from `pubspec.yaml` via the Flutter plugin. Consistent.
- `.github/workflows/build.yml` and `build_apk.yml` use **Flutter `channel: stable`** (unpinned) and **JDK 21**.
- Tags: `v*` (e.g. `v2.10.0`). CI may **force-move** the same semver tag when only the build number changes — F-Droid `UpdateCheckMode: Tags` expects **immutable** tags. Prefer a new tag per versionCode (`v2.10.0.39` or bump semver) before relying on fdroid auto-updates.
- `.flutter_version` records channel/revision for reproducibility. **Pin an exact Flutter version** in fdroiddata `srclibs` (do not leave `flutter@stable`).

## 6. Recipe

`metadata/com.ifallmusic.app.yml` is the copy-paste recipe for [fdroiddata](https://gitlab.com/fdroid/fdroiddata).

F-Droid **re-signs** APKs; GitHub Actions release signing is irrelevant to the F-Droid build.

## 7. Manual steps before the GitLab merge request

1. Tag a **immutable** git tag that matches `CurrentVersion`.
2. Replace Fastlane graphics.
3. Pin Flutter SDK version in the recipe after a successful local `fdroid build`.
4. Declare **NonFreeNet**.
5. Decide whether to disable GitHub in-app updates for the F-Droid build.
6. Confirm YouTube scraping remains acceptable under F-Droid policy (NonFreeNet is expected; ToS issues are a reviewer call).
7. Do **not** include signing secrets or the backend’s production config with secrets.

## Files created

- `LICENSE`
- `.flutter_version`
- `fastlane/metadata/android/en-US/title.txt`
- `fastlane/metadata/android/en-US/short_description.txt`
- `fastlane/metadata/android/en-US/full_description.txt`
- `fastlane/metadata/android/en-US/images/icon.png`
- `fastlane/metadata/android/en-US/images/README.md`
- `fastlane/metadata/android/en-US/images/phoneScreenshots/README.md`
- `metadata/com.ifallmusic.app.yml`
- `docs/FDROID_AUDIT.md`
