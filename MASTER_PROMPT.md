# MASTER PROMPT — Saxify v2.1.0 (post-merge completion)

## Repo & context
- Repo: `ifallertzia/ifallmusic` — Flutter app `com.ifallmusic.app`.
- PR #1 (Hindi-first search, mood grid, download button, onboarding, report-Gmail, YT unblock, release notes, UpdateService→`ifallertzia/ifallmusic`, version 2.1.0+4) **already merged from another session — DO NOT redo it.** First `git pull` and read current `main`.
- Tumhara kaam: **saari bachi hui incomplete cheezein + naye requirements complete karna.**

## Hard rules
1. **CI ki tension mat le.** GitHub Actions/main build/migrations wo main alag session se handle karunga. Tumhe sirf **code changes/add karke push karna hai aur PR merge kar dena hai** (branch `arena/…` se). Failing checks ignore kar dena — merge karke chale jao.
2. **Playlist sync / cloud code (Generate code, paste-import, Render playlist backend) — BILKUL chhod do.** Ye baad me alag se karwaunga. Ab koi playlist-backend ka kaam mat karna.
3. **Downloader ke liye KOI backend (Render/wagaira) mat use karo.** Download app ke andar hi honi chahiye.
4. Player architecture apna waisa hi rehne do — bas jo bola hai wo add karna (EQ/sound panel), replace mat karo.
5. Version **`2.1.0`** (`+4` ya aage bump) rakho; releases **isi repo `ifallertzia/ifallmusic`** se link hon (UpdateService + release config dono me).

---

## A. Saxify Downloader — 100% local, backend-free (PRIORITY)
- App me `yt-dlp` ka support check karo — **nahi hai to add karo** (package/native bridge jo chahiye, e.g. existing `SaxifyBridge.kt` me wire karo ya plugin lagao). Abhi download backend (`saxify-downloader.onrender.com`) pe depend karti hai aur **wo Render service mar chuka hai (dead/not found)** — isliye kaam nahi kar rahi.
- Requirement: **jaise in-app song play hota hai, waise hi app se hi download ho** — YouTube video links samet koi bhi supported link, **bina kisi backend ke**.
- Features:
  - Har song ka **working download button** with **live % progress**.
  - Options: **video-only / video+audio / always high-quality**.
  - Library → **Your Downloads** tab + **offline playback**.
  - Bulk/“Add link” bhi local pipeline pe chale.
- `lib/downloader/platform_detect.dart` wagaira me jo legacy backend paths hain unhe local yt-dlp path pe route karo (YT block pehle hat chuka hai — re-check karna).
- Acceptance: airplane mode me (ya Render bilkul dead hone ke baad bhi) download start → % badhta hai → file Library→Downloads me → offline play hoti hai.

---

## B. Background me gaana rukna (3–4 min par stop) — app-code fix
- Root cause: `playback_service.dart` me `errorStream`/mid-stream errors ka koi subscriber nahi; `play().catchError` mid-stream errors **pakadta nahi** (just_audio 0.9.46 `sendError` play-future fail nahi karta); single `AudioSource` hone se auto-skip bhi nahi chalta; `androidStopForegroundOnPause: true` + Doze.
- Fix: **`errorStream` subscribe karo** → track error aate hi **URL re-resolve → seek current position → play** (auto-recover, next track agar URL hi dead ho). `playbackEventStream`/state pe swallowing band karo.
- Notification/wake-lock: background me playback ke dauran foreground notification + wake-lock bana rahe (Doze se bachne ke liye), `notification_bootstrap.dart` revisit karo.
- Acceptance: 6–7 min ka gaana background me poori chale; network blip pe gaana rukke dobara wahi second se chale.

---

## C. Home page — faces, top artists, auto-load
1. **Artist chehre:** home pe abhi sab jagah app-logo placeholder dikhta hai; individual page khole to chehra aata hai. **Home (top artists, rails, lists) pe sab artists ka asli chehra/cover dikhe** — thumb fallback sirf tab jab image hi na mile.
2. **Top artists me `Darshan Raval` add karo** (Hindi-first section me).
3. Home auto-load: fresh launch pe content **bina pull-refresh ke apne aaye** (agar merged code me `loading=true` guard abhi bhi hai to fix karo).

---

## D. Categories = Spotify-style solid colors (theme accent same-same nahi)
- Abhi mood/genre/explore/brand categories **theme ke ek hi colour** me dikhti hain — boring/faded.
- **Requirement (mood & genres buttons + har category UI):** app code me **predefined colour list** se har category ko **distinct solid colour (gradient codes allowed)** assign karne ka **rendering logic** daalo — **dynamic & vibrant, Spotify "Browse categories" jaisa**. Har tile ka apna alag solid colour ho, theme se independent.
- **Same treatment Explore ke saare categories** (devotional, workout, Osho, etc.) aur **Music Brand** pe bhi.

---

## E. Music Brand page — abhi lame hai
- Click karne pe jo bada/empty-lam section aata hai usse redo karo:
  - **Category-wise grid** (upar wale Spotify-style solid colours ke saath).
  - Category ke andar / uske neeche **artists-wise listing** (faces ke saath).
  - Tap → wahi artist page / search jaise pure app me chalta hai.

---

## F. Player — Sound + EQ panel (liquid glass)
- Player me **speed button ke LEFT side wala sound wala button**:
  - Click → **niche panel khule** jisme **volume/sound controls + poora EQ** (bands, presets jo available ho) dikhe.
  - UI **liquid-glassy** ho (blur, translucency, soft highlights) — but player controls waise ke waise hi kaam karte rahe.
- Ye existing button ka enhancement hai, player replace nahi.

---

## G. Full UI polish (app-wide)
1. **Font:** pure app me **Apple-jaisa professional font** (SF Pro–style; bundle asset me — Google Fonts runtime fetch mat chhodo taaki offline/pehli launch me na toote). Consistent type scale.
2. **Buttons:** sab buttons **liquid-glassy**, proper padding, **kahin overlap/overflow na ho**.
3. **RenderFlex overflow:** `NeonButton(expand:true)` Row me bina Expanded — Library header, artist, playlist, album pages sab me fix karo.
4. **TextScaler clamp** (large-text phones pe UI na toote).
5. `_ChoiceTile` Wrap me `runSpacing` missing — fix.
6. **Appearance & Theme:**
   - Abhi sirf **6 colours** hain — **aur add karo, including `Silver`**.
   - Saare theme colours **ekdam solid/vivid** — abhi faded/fike lag rahe hain.
   - **Apple Music app jaisa** feel: solid accent + proper contrast (light/dark dono me).
7. **Bottom menu / labels:**
   - Song items me **Download** wala sign/label **waise hi rehne do**.
   - Jahan abhi **“Save”** likha hai (icon + text), wahan **“Exclusive”** likh do.
8. **Boot log / debug info hata do** — startup pe sirf clean **status** dikho; ye saari technical info UI me mat lao.

---

## H. Report / Contact → Gmail (bug fix)
- Problem select karke Gmail khulta hai — **har word ke baad `+` sign aa raha hai** (words `+` se join ho rahe hain). **Ye `+` encoding hatao**: subject/body me normal spaces aane chahiye, `mailto:`/`Intent` sahi se banao. Body me error examples + suggestions section formatted dikhe.

---

## I. Settings / quality / misc cleanup (merged PR ke residual gaps)
1. `qualityWifi` / `qualityMobile` settings ab resolver padhta nahi — **wire karo** (download/resolve quality pe effect dikhao) ya dead controls hatao.
2. Sony Music India ka stale `channelId` (`UC56gTxA3uTQqKqHCejS3g9A` → correct `UC56gTxNs4f9xZ7Pa2i5xNzg`) fix karo — "Go to artist" me wrong channel na jaaye; **"No uploads found" na dikhe**.
3. `looksLikeSong` 1h+ duration reject karta hai → **Osho / long mixes** filter ho jaate hain — duration early-return ke baad Osho/long-form check karo; **Osho (aur 1h+ mixes) search me aayein**.
4. Dead code hatao: CrashGuard (kabhi install nahi hota), dupe `brand_page` / `models/music_brand.dart` / `core/services/downloader/platform_detect.dart` (jo actually use nahi ho rahe).
5. `pubspec.lock` commit karo.
6. What's new / Release notes: `RELEASE_NOTES.md` **v2.1.0** ke content se sync — in-app “What's new” bhi wahi dikhae.

---

## J. Search / moods / Hindi-first (verify only, already in merged PR)
- Mood/genre click → search actually chalta hai; Trending “Show all” chalta hai; Hindi/Indian-first ranking; search me sirf songs (normal videos nahi); **“Play today's mix” Hindi-first** kaam kare. Inhe todna mat — sirf regressions ho to fix.

---

## Definition of done
- [ ] Download **bina backend ke** local yt-dlp se, live %, offline playback, YT video link bhi.
- [ ] Background me full song chalti hai; error pe auto-recover.
- [ ] Home pe artist faces + Darshan Raval + auto-load.
- [ ] Saare category grids Spotify-style distinct solid colours; Music Brand category+artist wise.
- [ ] Sound button → bottom sound+EQ liquid-glass panel.
- [ ] Apple font + glassy buttons + no overflow; Theme me Silver samet solid colours; “Save”→“Exclusive”; boot-log gone.
- [ ] Gmail me `+` nahi; Sony channel fix; Osho/long search OK.
- [ ] Version `2.1.0`, UpdateService/release → `ifallertzia/ifallmusic`.
- [ ] **Playlist sync untouched. CI ki fikr nahi — sirf code, push, merge.**
