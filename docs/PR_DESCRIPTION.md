# PR description

## Verification attempted

The first required command is currently blocked in this sandbox because Flutter is not installed:

```sh
flutter pub get
# /bin/bash: line 1: flutter: command not found
```

Because `flutter`/`dart` are unavailable, these required gates could not run in this sandbox:

```sh
dart format .
# /bin/bash: line 1: dart: command not found

flutter analyze
# /bin/bash: line 1: flutter: command not found

flutter test
# /bin/bash: line 1: flutter: command not found

flutter build apk --release
# /bin/bash: line 1: flutter: command not found
```

I did run:

```sh
git diff --check
# clean
```

## Verified by code review

- `PlaybackService.resolvePlayableStreamUrl(VideoId) -> Future<String>` remains intact.
- Downloads use the additive `resolveDownloadStreamUrl(VideoId)` path, while the original resolver signature remains available.
- Real download pipeline remains in `music_download_service.dart`: Dio download to `.part`, magic-byte/container detection, private offline copy, and public `Download/IfallMusic` copy through `NativeBridge.saveToDownloads`.
- LRCLIB lyrics files were not changed.
- 8D spatial audio/equalizer bridge was not removed or weakened.
- Theme/RGB code was not changed.
- UI changes are additive: resolver/cache/skip-silence settings, On device Library section, and a mic button in Search.
- Mid-stream/load source failures evict resolver cache entries and retry `_startSong` with the previous position.

## Changes

- Added Android MediaStore scanning through `NativeBridge.listLocalAudio`.
- Added `LocalMusicService` with cached scan results, album/artist grouping, search, and permission flow.
- Added `TrackSource.localDevice` and optional `Song.localUri`.
- Added Library → On device with Local Songs / Local Albums / Local Artists and re-scan.
- Local songs play through the existing `PlaybackService` via `content://` URIs and skip stream resolution.
- Search shows local results above web results.
- Added skip-silence setting using `AudioPlayer.setSkipSilenceEnabled` guarded with try/catch.
- Added playback cache size display, pruning helper and clear action for likely just_audio cache files.
- Added Android Auto browse roots for Liked, Playlists, Downloads placeholder, and On device.
- Added voice search using `speech_to_text` and a mic button.
- Added tests for Innertube resolver rotation/cipher skipping and local library scan-cache parsing.
- Updated README Playback engine and On device sections.

## Decisions / scope notes

- Ciphered Innertube formats are skipped so rotation continues; the legacy youtube_explode fallback remains the decipher-capable engine.
- Cache pruning targets likely just_audio/LockCaching cache files under app temp/support directories without touching real downloads.
- Home-screen widget and volume normalization were not implemented in this pass because they require additional native/plugin surface and are lowest/optional priority; avoiding playback instability was preferred.
