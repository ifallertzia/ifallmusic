# IfallMusic 2.2.0

## What’s new

- **The whole app is now IfallMusic** — new name, new icon wordmark, new notification
  channel, new download folder and new release notes. Nothing is branded “Saxify” on
  screen any more.
- **Liquid-glass redesign on true black.** Every panel, sheet, button and row is frosted
  glass over absolute black, with Apple-leaning typography, deep vivid accents and
  black button backgrounds so the colour pops.
- **18 accents + your own mix.** Violet, Indigo, Blue, Aqua, Teal, Emerald, Neon, Lime,
  Gold, Amber, Sunset, Crimson, Rose, Pink, Magenta, Purple, **Silver** and Graphite —
  plus an RGB mixer that paints your custom colour across the entire app, and an
  auto-rotating theme you can set to 1 / 2 / 2.5 / 3 / 5 minutes.
- **Library opens with its tabs in front of you** — Liked, Playlists, Songs, Artists,
  Downloads and History are big colourful buttons with live counters. Liked Songs no
  longer opens by itself, and the Home heart icon jumps straight to your downloads.
- **Downloads, everywhere.** Download percentages now show on song rows, in the
  Downloads tab and in the mini-player. Files save to `Download/IfallMusic` plus a
  private offline copy; existing downloads are migrated from the old folder.
- **The Save/Universal-Downloader section is gone.** The downloader backend, its
  screens, models and Android worker have been removed, which is why downloads are
  faster, lighter and finally reliable again. Songs download and save on the device,
  exactly as before.
- **8D spatial audio — a brand-new template.** Seven ready-made spatial presets with
  orbit speed, depth and reverb sliders, a live orbit meter, and a real native
  processor (LFO left/right orbit + synthetic reverb) documented in
  `docs/SPATIAL_AUDIO.md`.
- **Equalizer rebuilt in glass** — real Android audio-session bands, its own presets,
  and the spatial controls on the same screen.
- **A Sound panel in the player** — volume, the equalizer link and the 8D templates sit
  one tap away next to speed, sleep timer and queue.
- **Top artists show real faces** again (Darshan Raval included) instead of the app
  logo placeholder.
- **“Play today’s mix” fits every phone** — the hero stacks on small screens and the
  whole UI clamps text scaling, so nothing overflows on any device.
- **Contact / Report fixed** — the email draft is percent-encoded, so words no longer
  arrive with `+` signs between them (Gmail composer fallback included).
- **Settings now ends with** “Made with ❤️” and “by Siddharth ifallertzia”, with the
  heart cycling through the live theme colours.
- **This update notice** — the What’s-new card, the in-app update dialog and
  `RELEASE_NOTES.md` all describe 2.2.0, and smoke tests cover the palette, the spatial
  templates and the branding.

## Notes

- Playback still uses the existing engine; only additions were made around it.
- Downloads are 100% on-device. There is no downloader server, and no YTDL/yt-dlp
  component anywhere in the app.
- The in-app updater reads the latest release from `ifallertzia/Saxify-v1` and expects
  the `app-release.apk` asset.

## 2.3.0 — Music discovery, lyrics and reliable queues

- Your supplied IfallMusic logo across icons and launch screens.
- YouTube Music-first search, source-quality badges, personal playlists and lyrics.
- Search selections now start song radio: different recordings with a similar vibe,
  not the next cover/remix/duplicate in the search list.
- Guarded queue transitions, fresh-URL retry and bounded recovery for failed tracks.
- Optional redacted playback-error email drafts; no automatic diagnostic uploads.
- Background media controls, tab back history, swipe-down player and library polish.
