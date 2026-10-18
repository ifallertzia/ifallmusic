# Sidify 2.10.0

## Unreleased — refreshed app identity

- Replaced the launcher, in-app, splash-screen, web, desktop and store-listing
  icons with the newly uploaded Spotify + YouTube Music merged mark.
- Fixed the logo asset generator: it now uses the committed uploaded artwork as
  its single source instead of missing mascot source files, and keeps the
  generated platform assets in sync.
- Kept the Android application ID, signing identity and build-number release
  flow unchanged so this remains an in-place update for compatible installs.


## Unreleased — the dock folds, the player goes quiet

### Bottom bar & mini player

- **The bar folds into the player instead of vanishing.** Scrolling down now
  slides the tab bar's cells away one by one: Home remains as a small round
  glass button on the left, the mini player slimmed drops into the row the bar
  just gave up, and Search keeps its seat on the right of both. Scrolling up
  walks the exact same path back. It is one animation driving three surfaces —
  the pieces look like they come out of each other, because they do.
- **Liquid glass, for real.** The panes dropped most of their opacity and got a
  stronger frost, a second inner rim, and a specular streak that travels while
  the dock folds — the page shows straight through the chrome. Settings ›
  Liquid glass turns it off; high-performance mode thins the blur.
- **Sheets wear the same glass** — playback, queue menus and the track menu are
  frosted panes now, not flat cards.

### Now Playing

- **The oversized glow is gone.** The backdrop used to light four 340px radial
  blobs from the sleeve's quadrants, which turned any yellow cover into a
  spotlight behind the artwork and a second one under the controls. It is now
  one deep colour sampled from the actual artwork — hue kept, saturation cut to
  a third, lightness pinned under 0.17 so white type stays readable — plus a
  single low-alpha wash for depth.
- **A real timeline.** The progress card became a 2px line: soft white played,
  translucent unplayed, a thumb that only exists while you hold it, elapsed and
  remaining under it. Tap or drag anywhere along the 26px band to seek; the
  line is still driven by the player's own position stream and nothing else.
- **Transport, re-weighted.** Shuffle and repeat moved up beside the primaries
  (same toggles as before, marked with a dot when on), like and "…" are bare
  icons on the title row, and the "OFFLINE" word moved from under the timeline
  to the artist line. Every existing action — queue, lyrics, download, speed,
  equalizer, sleep, crossfade, playlist, share — is still one tap away.
- **Colour cross-fades between tracks** instead of flashing, and missing or
  unreadable artwork lands on a neutral graphite screen rather than a brand
  colour.
The floating chrome got a proper glass pass — and a pile of polish underneath.
Same package (`com.ifallmusic.app`), same release key: install straight over
your current app, no conflict. Your library, settings, playlists and downloads
all carry over untouched.

## Bottom bar & mini player

- **Redesigned tab bar** — Home · Explore · Library live in one glass pill, with
  a separate round glass Search button beside it. Listen Together steps out of
  the bar for now.
- **Scroll-aware chrome** — scroll down and the tab bar tucks away while the
  mini player slides into its slot; the smallest scroll up brings the bar back
  with the mini player riding above it. Works on every page.
- **Heavier glassmorphism** — deep frosted blur, a soft diagonal sheen and lit
  rims, matching the site's bar glass.
- **No more overflow stripes** — labels and titles now shrink or ellipsize
  instead of overflowing on narrow screens and large font scales.

## Explore

- **Mood & genre tiles show photos again** — each tile carries a duotone sleeve
  from the top YouTube Music result for its seed, just like sidify.vercel.app.

## Catalog

- **Top picks, Trending and New releases are YouTube Music only** — real songs
  and albums, never plain YouTube video results.

## Player

- **Live artwork backdrop** — the sleeve's colours now follow the track the
  moment it changes; no more reopening the player to refresh them.
- **Buttons swapped** — the playback panel opens from the left button, and the
  lyrics toggle moved into the capsule where playback used to sit.
- **Playback sheet** — the Speed row is icon + rate chips only, so nothing
  squeezes on narrow screens.

## Library & on-device music

- **On-device songs show a music note** instead of the app logo wherever a
  cover is missing.

## Settings

- **Streaming quality · Wi-Fi / Mobile rows removed** — they were dead
  controls.

## Listen Together

- **Coming soon** — the rooms feature is parked behind a Coming soon card while
  it gets finished.
