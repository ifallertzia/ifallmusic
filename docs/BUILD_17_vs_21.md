# Build 17 vs Build 21 — kya same hai, kya badla

> Reference note. Build numbers = Flutter `version: x.y.z+build` in `pubspec.yaml`.
> Compared: tag `v2.5.0` (build 17) → tag `v2.5.2` (build 21). Beech mein `v2.5.1`
> (build 19) bhi hai, isliye niche har change ke saath likha hai ki wo 19 mein aaya ya 21 mein.

## 1. Identity

| | Build 17 | Build 21 |
|---|---|---|
| Tag | `v2.5.0` | `v2.5.2` |
| pubspec version | `2.5.0+17` | `2.5.2+21` |
| Release title | IfallMusic v2.5.0 (build 17) | IfallMusic v2.5.2 (build 21) |
| Published | 2026-09-29 10:45 UTC | 2026-09-30 18:27 UTC |
| APK size | 73,298,043 B (~69.9 MB) | 73,117,883 B (~69.7 MB) |
| Assets | `app-release.apk`, `latest.json` | `app-release.apk`, `latest.json` |
| Status | — | **Latest** |

Beech wala release: **build 19 = v2.5.1**, 2026-09-30 15:10 UTC, 73,478,419 B.

Commits between the two tags (4):
`d8cab8b` Improve player, library, and recovery UX (#27) → `0fec31a` bump 2.5.1+19
→ `087920b` feat(ui): 4x4 home grid, bottom lyrics, single-list Library, Spotify Green default
→ `1f1a9ec` bump 2.5.2+21.

## 2. Same: kya bilkul nahi badla

- **Dependencies (100%)** — `pubspec.yaml` mein sirf `version` line badli. just_audio,
  audio_service, youtube_explode_dart, provider, dio, sqflite, workmanager … sab same
  versions. Dart SDK constraint `>=3.5.0 <4.0.0` same.
- **Android config** — `android/app/build.gradle.kts` byte-identical:
  `applicationId = "com.saxify.app"`, `minSdk`/`targetSdk` flutter defaults,
  `versionCode/versionName` pubspec se. Release signing config wahi (isliye 17 ke upar
  21 direct install hota hai, "app not installed" nahi aata).
  Sirf `SaxifyBridge.kt` badla (native cache-repair, niche dekho).
- **63 of 87 lib files identical** — poora playback/streaming core chhua tak nahi:
  `innertube_resolver.dart`, `library_service.dart`, `music_download_service.dart`,
  `recommendation_engine/store/worker/service.dart`, `spatial_audio_service.dart`,
  `playlist_sync_service.dart`, `update_service.dart`, `radio_queue.dart`,
  `media_notification_handler.dart` (Android Auto / media session), sab models,
  `lrc_parser` / `lyrics_service` / `yt_music_parser` / `yt_music_service`.
- **UI screens untouched** — album, artist, artist profile, brands, onboarding,
  playlist detail, backdrop guide, backup sheet, playlist sync sheet, update dialog.
- **Release pipeline** — same signed-APK workflow, same release key, same
  apksigner cert-verification gate. Dono builds usi pipeline se nikle.

## 3. Different: build 19 (v2.5.1) mein aaya

1. **Full player ab scrollable** — art scroll ke saath shrink hota hai, upar se pull-down
   karke wapas niche wali screen; lyrics player ke **bottom** mein, auto-load (static +
   synced), na mile to `iska nhi mila sori🥲`. `lyrics_finder_screen.dart` reworked.
2. **Cache repair safe ho gaya** — `clearLocalPrefs()` → `repairLocalCache()`; Kotlin side
   pe `clearFlutterPrefs` ab `repairLocalCache` call karta hai aur
   **FlutterSharedPreferences clear nahi karta** (likes/playlists/settings bach gaye).
   Recovery screen: "Reset and retry" → "Repair cache & retry".
3. **Library default tab** — Liked → naya **Your Space** overview
   (`LibraryTabs.overview`).
4. **Home recommendations artwork grid** — naya `RecommendationSongCard`
   (`lib/ui/widgets/media_cards.dart`), "Play today's mix" + "Explore".
5. **Theme plumbing** — `ThemeController` mein `paletteAccent` (rotating/custom colour)
   vs `accent` (jo theme paint karta hai); `SaxifyAccentExtension` mein naya
   `qualityAccent`; default look neutral graphite.
6. **Quality badge restyle** — black chip, `white70` text, high-quality text `qualityAccent`
   follow karta hai. Song tile padding tight (9→7, 6→5).
7. **Player open animation** — `MaterialPageRoute` → `PageRouteBuilder` (fade + slide,
   360 ms, `easeOutCubic`).
8. **Auto-rotate ab opt-in** (default `false`).
9. Home backdrop intensity `0.9` → `0.18` (calmer).

## 4. Different: build 21 (v2.5.2) mein aaya

1. **Spotify Green default** — `SettingsService.applyGreenDefault()` one-shot migration
   (`saxify.green_default.v1`): purani install bhi green default pe aa jati hai, exactly
   once. `defaultAccentId = 'neon-green'`, `accentAcrossApp` default true.
2. **Library ekdum rewrite** (sabse bada change, ~1800 lines) — purane tabs
   (`_LibraryTabBar`, `_TabPill`, `_LikedTab`, `_SongsTab` …) hat kar
   **ek single scrollable list + pushed pages**: `LibrarySectionPage`, `LikedSongsPage`,
   `PlaylistsPage`, `LibrarySongsPage`, `LibraryArtistsPage`, `LibraryDownloadsPage`,
   `LibraryHistoryPage`, `OnDevicePage`.
   - Bug fix: har row ko apna `Material` (ink splash dikhe), aur pushed section pages ko
     Material ancestor (pahle "No Material widget found" crash aata tha).
   - Library tab dobara tap karne pe overview pe wapas.
3. **Home = 4x4 grid** — `crossAxisCount: 4`, `childAspectRatio: 0.68`, 16 de-duplicated
   picks (`recommendations → madeForYou → recommended → history → liked → trending`).
4. **Search fast** — `ListView` → `ListView.builder` lazily-built rows; `YoutubeService`
   mein 60-entry LRU **search cache** (repeat query instant, no network); Settings mein
   naya **"Clear search memory"** row.
5. **On-device search fast** — `LocalMusicService` lowercase haystack + result memoization
   (har keystroke pe hazaaron string allocations bach gaye).
6. **Prewarm window 45s → 90s** — next track ka URL pehle resolve hota hai, slow network
   pe bhi gapless chalta rahe.
7. **CI diagnostics** — test log se failure blocks (sirf tail nahi) aur annotations ab
   3000-byte chunks mein (GitHub 4096 byte pe kaat deta tha).
8. **Tests** — 24 → 27 files: naye `library_list_test.dart`,
   `spotify_green_default_test.dart`, `theme_controller_test.dart`.

## 5. Ek line mein

- **Same:** app id, signing key, dependencies, Android config, aur poora
  streaming/download/recommendation/Library-data core — 63/87 lib files identical.
- **Badla:** sirf presentation + performance + 2 UX fixes.
  Build 19 = player/lyrics/recovery UX; build 21 = Library ka single-list rework,
  4x4 home grid, Spotify Green default, search caching, aur CI diagnostics.

> Note: build 17 ke release notes ka header "2.5.0 (build 15)" likha tha (stale number),
> build 19 ke notes ka "2.5.1 (build 18)" — dono me header aur actual build number mismatch
> tha. APK khud sahi build ka tha; sirf notes ki heading galat thi.
