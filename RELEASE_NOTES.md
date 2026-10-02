# IfallMusic 2.6.0 (build 22)

Rebuilt on **build 17** — the layout everybody liked — with only the build-21
improvements that were asked for. Nothing else from build 21 was carried over.

## Player

- The player page now scrolls. The top row (back, lyrics, sleep timer, menu)
  stays exactly where it is; everything below moves and the lyrics live at the
  bottom, below the speed / add / queue row.
- **Add playlist** is gone as a labelled chip — there is a plain **+** in a
  circle next to the equalizer instead.
- The lyrics block shows only the words: no song title (it is already above),
  no "wrong lyrics?" chatter — mismatch reporting stays in the lyrics finder.
  A small **Static / Synced** switch and a reload are all that is left.
- When a track cannot be found the player says:

  > iska nahi dundh paya..sorry🥲
  >
  > shayad ye song playback kisi normal server se play ho raha,ya iska artist
  > understand hai,,ya shayad ye song abhi underrated hai🥲..sorry again,,
  > ifallertzia isko jaldi thik kr denge

## Home

- Home keeps the build-17 layout.
- Nothing sits in a card any more: greeting, trending and recommendations read
  as part of the page.
- Richer, YouTube-Music-like coloured backdrop — vivid but still professional.
  Every screen (Home, Search, Library, Settings) now shares it.

## Navigation bar

- The selection is a **sliding pill**: tap a tab and it glides across, or grab
  the pill and **drag** it sideways (Home → Search → Library) like Instagram on
  iPhone.
- Scroll any page down and the whole bar shrinks to icons; scroll up and it
  comes back with labels.

## Brought in from build 21

- **Spotify Green default**, with the opt-in "use colour across the app" switch
  in Settings.
- **Library** reworked: one clean list ("Your Space") with each section opening
  as its own page, and the ink-splash / Material crash fixed.
- **Faster Search**: lazily built rows, a remembered-results cache and a
  "Clear search memory" row in Settings.
- **Faster on-device search** — results are memoised instead of rescanned on
  every keystroke.
- **Gapless**: the next track's stream is resolved 90 s ahead (was 45 s).
- Cache repair never touches saved preferences any more.

## Fixed

- **Background playback no longer stops on its own.** The notification is now
  ongoing (a stray swipe cannot kill the track) and the app asks once to be
  excluded from battery optimisation — the usual reason a long track dies a few
  minutes after the screen goes off.
- **Your playlists can no longer be wiped by a settings reset.** Resetting
  preferences used to clear the whole shared-preferences file, which is also
  where likes, playlists, history and downloads live.
- **Search puts original songs first** (YouTube-Music order): real tracks, then
  albums / artists, then raw video results.
- **High refresh rate enabled**: the app now asks the display for its fastest
  mode, so 90 / 120 Hz panels animate at full speed instead of 60.
- Quality label: a tiny gold **premium** plate with micro "HD" lettering for
  album-master sources, and nothing at all for normal ones.

## How to update

Download `app-release.apk` below and install it over your current app. The
Android application id and release-signing configuration are unchanged and the
build number has increased to 22, so it installs in place. Your library,
playlists and downloads stay exactly as they are.
