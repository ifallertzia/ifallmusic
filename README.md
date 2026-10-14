# Sidify

Sidify — *Stream beyond limits.* A premium, Apple-Music-style player built with
Flutter, from `ifallertzia/ifallmusic`. Version **2.9.0 (build 34)**.

## What changed in 2.9

The entire interface was rebuilt to match [sidify.vercel.app](https://sidify.vercel.app):
five tabs (Home, Explore, Search, Library, Listen Together) under one floating
**glass tab bar** with a pill mini-player above it, a full-screen Now Playing
with an artwork-mesh backdrop and karaoke lyrics, and iOS-style Settings
groups. The playback engine (stream resolver, queue, downloads, rooms) is the
same one that has always powered this app — only the clothes are new.

The app is **Sidify** everywhere a person can look: the launcher label, the
splash, the About page. Underneath, the Android identity is unchanged —
`com.ifallmusic.app`, signed with the same release key as every build since
the start — so this APK installs straight over the old app: no package
conflict, library, settings and downloads all survive the update.
See `docs/RELEASE_SIGNING.md`.

## Features

- **Home** — greeting with your name, Top picks, Quick picks, Recently
  played, New releases, Top artists with real faces, and picks from your
  Liked Songs.
- **Explore** — new releases, trending songs, mood tiles (Chill, Workout,
  Romance, Party, Sleep…) and genre stations.
- **Search** — recent searches, browse categories, and Top results / Songs /
  Albums / Artists filters.
- **Player** — full-screen Now Playing: artwork-mesh backdrop, artwork that
  breathes with the music (and eases down when paused), karaoke lyrics that
  follow the line, queue with Play next / shuffle, AutoPlay, crossfade,
  equalizer, sleep timer, speed, and a glass mini-player + floating tab bar.
- **Library** — Your Replay stats, Liked Songs, History, Downloads, the
  Lyrics finder, on-device music, playlists you can pin, and followed artists.
- **Listen Together** — start a room, share the six-character code, and
  everyone hears the same song at the same moment.
- **Settings** — Profile, Appearance (Dark / Light / Auto, colour from
  artwork), Playback, Sound (streaming quality, normalization, equalizer),
  Lyrics, Listen Together, Downloads & storage, backup & playlist codes, and
  update checks with in-place install.

## Building

```bash
flutter pub get
flutter build apk --release
```

Release signing is provided by CI (`docs/RELEASE_SIGNING.md`); local debug
builds need no keystore.
