# IfallMusic

IfallMusic — *Stream beyond limits.* A premium, liquid-glass music player built with
Flutter, from `ifallertzia/Saxify-v1`. Version **2.6.0 (build 22)**.

## Features

- **Home** — a coloured, YouTube-Music-like canvas: *Made for you*, **Mood & genres**
  buttons, trending chart, new releases, music brands, top artists with real faces,
  smart rails and *Recommended for you*. Nothing is boxed in: the content sits on
  the page itself.
- **Search** — song-focused results biased toward Hindi and Indian music, plus
  one-tap mood/genre stations and music-brand channels.
- **Player** — the existing playback engine, with a persistent mini-player, full
  player, queue, gapless pre-load, auto-next, sleep timer, speed control and
  background media-session initialisation. The page scrolls and the lyrics live at
  the bottom with a Static / Synced switch. The **Sound** sheet adds volume plus the
  full equalizer and 8D templates in one place.
- **Library** — a neutral **Your Space** list: Liked · Playlists · Songs · Artists ·
  On device · Downloads · History, each a row with a live counter that opens its own
  page. Liked Songs only opens when you ask for it.
- **Navigation** — a floating bar whose selection is a sliding pill: tap a tab or
  drag the pill sideways. Scroll down and the bar shrinks to icons.
- **Downloads** — tap the download icon on any song and it saves to this phone
  (`Download/IfallMusic` where the platform allows it, plus a private offline copy).
  Progress is shown everywhere a download is running — song rows, the Downloads tab
  and the mini-player.
- **Equalizer & 8D spatial audio** — the real Android session equalizer (bands,
  presets) plus seven 8D templates (Orbit, Swift, Cinematic, Dreamy, Focus, Club) with
  orbit-speed, depth and reverb controls and a live orbit meter.
- **Appearance & Themes** — 18 deep accents including **Silver**, plus a fully custom
  RGB mixer you can paint across the whole app, and an auto-rotating theme with a
  1 / 2 / 2.5 / 3 / 5-minute cadence.
- **Profile & Settings** — first-launch display name, playback quality, gapless,
  autoplay, resume positions, storage, background-playback guide, diagnostics,
  backup tools and a "Made with ❤️ by Siddharth ifallertzia" footer whose heart follows
  the live theme colour.

There is **no downloader backend** and no YTDL/yt-dlp service. Everything — search,
playback and downloads — happens on the device.

## Playback engine

Playback now uses a dual-engine resolver inside `lib/core/services/playback_service.dart`:

1. **Innertube primary** (`lib/core/services/innertube_resolver.dart`) posts directly to
   YouTube's on-device `youtubei/v1/player` endpoint and rotates through Android,
   VR, VisionOS, embedded, Music and TV clients. Direct audio URLs are HEAD-probed
   before use.
2. **Legacy fallback** keeps `youtube_explode_dart` with the app's existing
   `androidSdkless` → `ios` → `androidVr` order, plus manifest/probe timeouts,
   per-itag probe blacklisting and one network retry.

Settings → Playback includes **Stream resolver** for Smart / Innertube only / Legacy
only debugging. Resolved stream URLs are cached per video for four hours with
in-flight coalescing, and mid-stream source failures evict the cache and retry from the
same position. `LockCachingAudioSource` is used for streamed network sources so replayed
tracks can start from just_audio's local cache; real file downloads remain separate and
continue to use the Dio → `.part` → container detection pipeline.

The 8D processor and equalizer ride on top and never touch the resolver.

## On device music

Library now includes an additive **On device** section for audio files already on the
phone. On Android it requests `READ_MEDIA_AUDIO` on Android 13+ or
`READ_EXTERNAL_STORAGE` on older devices, scans `MediaStore.Audio.Media` for real music
files longer than 30 seconds, and stores the scan result locally for instant relaunch.
The section exposes Local Songs, Local Albums and Local Artists; local tracks use
`content://media/external/audio/media/<id>` sources in the same `PlaybackService`, so
they can sit in the same queue as streamed tracks without going through Innertube or the
legacy resolver. Search also shows a small **On device** group above web results.

The existing Downloads tab is unchanged and remains only for files downloaded by
IfallMusic.

## Local library JSON vs. playlist codes

- **Library JSON** is exported/imported locally from Library → backup or Settings →
  Backup library. It covers likes, songs, playlists, history and followed artists.
  It is never uploaded anywhere. Clipboard paste and merge/replace are supported.
- **Playlist codes** are server-backed and require the playlist service
  (`BackendConfig.playlistBase`). Generating a single code uses `POST /playlist`;
  generating all playlists uses `POST /playlist/all`. Restoring one playlist uses
  `GET /playlist/:code`; restoring all playlists uses `GET /playlist/all/:code`.
  The app tries the bulk route first and falls back to the single-playlist route.
  If the service does not implement a route, local JSON backup/import still works.

## 8D spatial audio

See [`docs/SPATIAL_AUDIO.md`](docs/SPATIAL_AUDIO.md) for the DSP structure, the
Flutter/native layout, the recommended native libraries (AndroidX Media3
`AudioProcessor`, Oboe/AAudio, `Virtualizer`/`EnvironmentalReverb`) and the tuning
table behind each template.

## Releases, signing and the in-app updater

Full details: [`docs/RELEASE_SIGNING.md`](docs/RELEASE_SIGNING.md).

**Signing.** Every release APK is signed with one permanent release key
(`upload-keystore.jks`, alias `upload`, RSA-2048, valid until 2054). The key lives
only in the GitHub Actions secrets `SIGNING_KEY`, `KEY_ALIAS`, `KEY_PASSWORD` and
`STORE_PASSWORD`; CI decodes it to a temporary path outside the checkout, uses it,
verifies the built APK's certificate fingerprint against it, and deletes it — on
success *and* on failure. `android/app/build.gradle.kts` reads the credentials from
environment variables (or the git-ignored `android/key.properties` for local builds)
and contains **no hardcoded credentials**. A partial configuration fails the build
instead of silently signing with a different key, which is what caused the
"App not installed as package conflicts with an existing package" error.

**Publishing.** `.github/workflows/build_apk.yml` is the gate for every push and pull
request (analyze, all tests, release-mode APK *and* AAB) and never publishes a release
from a feature branch or PR. On `main` it also bumps the Android build number and moves
the `v<version>` tag, which triggers `.github/workflows/build.yml` to build, signature-
verify and publish the GitHub Release with `app-release.apk` plus a `latest.json`
manifest. Release notes come from `RELEASE_NOTES.md`. Pushing a `v*` tag directly does
the same thing.

**Build number.** `pubspec.yaml`'s `version: x.y.z+build` feeds Gradle's `versionCode`.
Android only treats an APK as an update when `versionCode` strictly increases, so CI
increments it automatically via `scripts/bump_build_number.sh`, which also regenerates
`lib/config/branding.dart` through `scripts/sync_version.sh`. To bump by hand:

```sh
bash scripts/bump_build_number.sh            # 2.4.0+13 -> 2.4.0+14
bash scripts/bump_build_number.sh 2.5.0      # 2.4.0+13 -> 2.5.0+14
```

**Updater.** `lib/core/services/update_service.dart` checks the latest release from
`ifallertzia/Saxify-v1`, prefers the `latest.json` asset so it can compare the build
number as well as the version, downloads `app-release.apk` with progress and hands it
to the system installer. It runs silently on app start and on demand from Settings.

## Build

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

For a locally *signed* release build, create `android/key.properties` (git-ignored):

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storeType=JKS
keyAlias=upload
keyPassword=YOUR_KEY_PASSWORD
storePassword=YOUR_STORE_PASSWORD
```

or export `SIGNING_KEYSTORE_FILE`, `SIGNING_KEY_ALIAS`, `SIGNING_KEY_PASSWORD` and
`SIGNING_STORE_PASSWORD`. With neither, Gradle signs with the debug key and warns
loudly — that APK must not be distributed, because it will not install over a
release-signed build.

CI also builds a release app bundle. Flutter analysis, all unit/widget tests, APK and
AAB builds are blocking steps; any failure prevents release publication.
