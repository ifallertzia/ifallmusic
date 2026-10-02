# YouTube Music, lyrics and playback UI

## Phase 1 — music search and saved metadata

- `lib/services/yt_music_service.dart` sends on-device JSON to
  `https://music.youtube.com/youtubei/v1/search?prettyPrint=false` using
  `WEB_REMIX`, client name header `67`, version `1.20250219.01.00`, music Origin/
  Referer and a desktop browser User-Agent. No key, account or new backend.
- Locale comes from the Flutter platform locale, falling back to IN/en.
- Queries lose control characters and are capped at 120 characters. No Hindi
  prefix or music-title regex is applied to this search path.

| Filter | Params |
| --- | --- |
| Songs | `EgWKAQIIAWoMEA4QChADEAQQCRAF` |
| Videos | `EgWKAQIQAWoMEA4QChADEAQQCRAF` |
| Albums | `EgWKAQIYAWoMEA4QChADEAQQCRAF` |
| Artists | `EgWKAQIgAWoMEA4QChADEAQQCRAF` |
| All, including playlists | omitted |

`yt_music_parser.dart` handles responsive rows, top cards, two-row browse cards,
fixed-column durations and shelf continuations. IDs—not translated shelf
headings—classify tracks, albums, artists and playlists. Googleusercontent art
is upscaled to 544-square. ATV / OFFICIAL_SOURCE_MUSIC / ` - Topic` sources get
**High quality music**; other uploads get **Normal quality**. This describes the
source, not bitrate. It is not a lossless/Premium claim.

Songs, unfiltered YTM and plain YouTube searches run in parallel. Partial results
are rendered under YouTube Music / Videos / More from YouTube. Album-master
sources stay first; IDs deduplicate. A top-result track joins its source group
rather than promoting a normal video above album masters. Different video IDs
are **not** title-deduplicated: different recordings/live versions must not be
silently lost. YTM failures leave the YouTube fallback and a muted status note.

Search uses a 300 ms debounce, generation guards and Dio cancellation. Successful
YTM requests cache for 10 minutes (100 entries); non-cancellable consumers share
in-flight requests. UI-owned cancellation is deliberately isolated from those
shared catalog requests. youtube_explode's HTML fallback has an 8-second caller
 timeout and stale results are ignored; that library does not expose a per-search
CancelToken. Continuation support is at the service level; there is not yet a
search-page infinite-scroll control.

`Song` has source, quality, artistId, album, albumId and musicVideoType. Existing
id/thumb/ms/channel/sub JSON keys stay intact. Missing new fields default safely.
Downloads are **SharedPreferences JSON records, not a downloads SQL table** in
this checkout. Their embedded `song.toJson()` persists every new field without
an SQL migration. Playlists, likes and history use the same codec. Shared song
rows show the badge and expose download regardless of source; queue rows also
have a download button. Overflow includes play, next, queue, playlist, download,
lyrics and copy-share-link.

## Phase 2 — lyrics

Files: `lyrics_service.dart`, `lyrics_query.dart`, `lrc_parser.dart`,
`lyrics_clock.dart`, `widgets/lyrics_view.dart`, `widgets/copy_lyrics_button.dart`,
`screens/lyrics_finder_screen.dart`.

Provider order:
1. LRCLIB `/api/get`: cleaned title, artist and known duration.
2. LRCLIB `/api/search`: title only; exact normalized title required. Artist match
   +4; duration within five seconds +2; zero-score ambiguous artists rejected.
3. lyrics.ovh `/v1/<artist>/<title>`: plain lyrics fallback.

At most four query variants per tier run in parallel. Requests have a four-second
deadline, individual cancellation and an IfallMusic/version/repository User-Agent.
404s are misses; timeouts/network/5xx are outages. Outages are not negative-cached.
Successful/instrumental results persist seven days; misses one hour. Cache is
bounded to 100 entries. LRC results cap at 1,200 lines and 500 characters/line.
NFKC normalization is supplied by `unorm_dart`.

The parser supports repeated stamps, global signed offset, metadata and enhanced
word markers. A single zero-time marker does not enable Synced. Synced-only
responses generate plain text for Copy. Static is the default, selectable view.
The shared synced widget follows a 60 Hz media-time clock, 80 ms update buckets,
900 ms drift correction, 500 ms frame cap and playback speed. It seeks on line
tap and pauses auto-follow for five seconds after manual scrolling, with a
Current line button. Reduced motion disables scale/animated scrolling. Long
synced lines use a four-line ellipsis to keep predictable scroll geometry; Static
and Copy always retain the full text.

The Library category opens a standalone Lyrics Finder. “Use the playing song”
binds lyrics to the current media clock and follows track changes. Manual standalone search
is intentionally unbound so a different song's lyrics cannot accidentally seek
the current track. Corrections inside the current player panel retain its binding. The player panel supports manual correction and resets on
track change while following playback. Retry bypasses cache.

## Phase 3 — albums, downloads and app polish

- Real YTM album/artist/playlist browse results replace search-query rewrites.
  `MPREb` browse resolves canonical OLAK playlist URLs. VL playlist IDs lose the
  VL prefix. Existing youtube_explode playlist extraction supplies up to 100
  tracks, with Play all / Download all; artists use YTM song search.
- The stream resolver and its client/HEAD-probe chain remain unchanged. The
  download save step detects MP4/WebM/Ogg/MP3 container bytes and chooses the
  matching extension/MIME instead of writing fake MP3s. Existing files are not
  renamed. **AAC itag preference and embedded MP4 cover/tags are not implemented**:
  they would require changing the shared stream choice or adding a tagging layer.
- The root `ifallmusic logo.jpg` supplies in-app artwork, launch screens and
  Android/iOS/macOS/Windows/web icons. Artwork is fitted, not cropped or redrawn.
- Home removes its mood/genre grid, keeps Made for you strictly YTM, adds real YTM
  playlist discovery from recent artists, and refreshes every 30 minutes and
  after listening/library activity (two-minute throttle). Pull to refresh remains.
  New releases are live YTM album-search discovery with the previous curated
  shelves as offline fallback; Trending is search-based discovery, **not a
  verified chart/ranking API**. Brand logos resolve from official channel metadata
  with an initial fallback when offline. No invented playlist/brand images.
- Library has compact coloured category tiles; accent swatches are compact circles
  hidden under an expandable control. Full player supports downward dragging.
- Back replays tab history (Home → Search → Library → Search → Home). Existing
  Navigator detail routes pop first. Back at Home calls Android moveTaskToBack,
  rather than destroying the audio-owning UI. Home is the exit boundary.
- The old just_audio_background single-source wrapper is removed. An app-owned
  audio_service handler publishes the actual queue and connects previous, play,
  pause, next, seek, like and stop to PlaybackService. New notification channel:
  `com.ifallmusic.app.playback.v2`. Audio session uses music configuration. Removing
  the task invokes stop and cancels notification/media state; pending stream loads
  and autoplay cannot restart the stopped task. Like feedback uses themed floating
  snackbars; existing download/queue/playlist feedback is preserved.

Android controls/layout still depend on Android version and OEM. Android 13+
may expose custom Like in expanded controls rather than the compact three-button
view. Notification permission, foreground-service behavior, screen-off playback,
Bluetooth and recents removal require a **physical-device acceptance pass**.

## Tests and validation

Added fixture/parser, query, LRC, matching/mock HTTP, media-clock, service-cache,
copy-widget, navigation and download-container tests in `test/`.

Run on a Flutter-enabled machine:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

This sandbox had no installed Flutter/Dart. A stable Flutter checkout was fetched,
but Dart SDK downloads from both Google storage and the Flutter mirror failed
with TLS/network errors. Therefore **flutter analyze, flutter test and Android
build/device acceptance have not been run here**. Changed Dart files were parsed
and formatted using the Dart formatter WASM package; `git diff --check` passed.
This is syntax/patch validation, not a substitute for analyzer or runtime tests.

Manual priority: search Kesariya; verify YTM art/source and all row actions; play
and download ATV/OMV; verify offline metadata; block only YTM and verify fallback;
copy static/synced lyrics, seek, scrub, change speed/track; Home/Search/Library back
history; Android Back vs Home key, screen lock, notification actions and recents
removal. Neither real search ranking nor lyrics availability is guaranteed by the
unofficial upstream services.

## 2.3.0 follow-up — song radio and error reports

Search row taps, search “Start radio”, and search-row overflow Play now use
`PlaybackService.playRadio(seed)`. The seed plays immediately while WEB_REMIX
`next` builds a mix from its video ID. Related music and artist-song discovery
are fallbacks; the original search-results list never becomes this queue.
`radio_queue.dart` filters IDs and normalized recording families (covers,
slowed/reverb/remix versions and trailing video metadata) from automatic radio.
Explicit playlist/album queues and user Play next choices retain their order.

Playback epochs suppress duplicate completion/error transitions and stale async
work. Native repeat stays off because the app, not the single-source player,
owns queue repeat/shuffle. Foreground loading gets one fresh URL retry;
mid-stream errors get one fresh-source retry with position restoration. Prefetch
runs near the end of the track, expires after 90 seconds, and is invalidated
across sessions. Failed tracks are skipped; six consecutive failures without
real progress stop retries with a connection/retry message rather than looping
forever offline. No app can guarantee uninterrupted playback of unavailable
upstream tracks.

Errors display “Failed, proceeding to next.” with MAIL ERROR. The player also
has “Mail this error to ifallertzia so he can fix the bug”. Tapping opens the mail
app with version, time, platform, track ID, error type/code/cause, queue position
and stack trace. Send remains the user's decision. Stream URLs, credentials and
local paths are redacted; only the latest bounded report is kept locally.
No automatic emails, SMTP credentials, analytics uploads or new backend.
