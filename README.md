# IfallMusic

IfallMusic — *Stream beyond limits.* A premium, liquid-glass music player built with
Flutter, from `ifallertzia/Saxify-v1`. Version **2.2.0**.

## Features

- **Home** — a black-canvas dashboard: *Made for you*, big colourful **Mood & genres**
  buttons, trending chart, new releases, music brands, top artists with real faces,
  smart rails and *Recommended for you*.
- **Search** — song-focused results biased toward Hindi and Indian music, plus
  one-tap mood/genre stations and music-brand channels.
- **Player** — the existing playback engine, with a persistent mini-player, full
  player, queue, gapless pre-load, auto-next, sleep timer, speed control and
  background media-session initialisation. The **Sound** sheet adds volume plus the
  full equalizer and 8D templates in one place.
- **Library** — tap Library and the tabs come to *you*: **Liked · Playlists · Songs ·
  Artists · Downloads · History**, each a big colourful button with a live counter.
  Liked Songs only opens when you ask for it.
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

## In-app updater and releases

The updater checks the latest release from `ifallertzia/Saxify-v1` and looks for an APK
asset named `app-release.apk`. The Actions workflow builds on feature branches and pull
requests but **never publishes a release from those runs**. A versioned GitHub Release
(`v<version>`) with the APK is created only when the complete build job succeeds on the
default `main` branch. Release notes come from `RELEASE_NOTES.md`.

To prepare a later release, bump `version:` in `pubspec.yaml`, keep
`IfallBranding.versionLabel` and `RELEASE_NOTES.md` aligned, then merge.

## Build

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

CI also builds a release app bundle. Flutter analysis, all unit/widget tests, APK and
AAB builds are blocking steps; any failure prevents release publication.
