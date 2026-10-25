# Listen Together server — FREE deploy guide

App ka default room server `https://ifallmusic-party.onrender.com`
hai — yehi Go program (`backend/` folder), Render ke free plan par
live. Is file me use live rakhne / dobara deploy karne ka pura
tareeqa hai.

> **Status (Oct 2026): server LIVE hai** upar wale address par aur app
> ka default yahi set hai. Neeche ki guide dobara-deploy ya custom
> domain lagane ke kaam aayegi.

---

## Pehle ek sach: Vercel par ye server NAHI chalega

Vercel ka kaam hai *serverless functions* — chhota sa code jo ek
request par jaagta hai aur 10–60 second me band ho jata hai. Humara
server usse ulta hai:

- **WebSocket** connection ghanton khula rehta hai (wahi sync ka jaadu hai).
- Rooms, chat, invites — sab server ki **memory (RAM)** me rehte hai.

Vercel par rooms har kuch seconds me gayab ho jayenge aur WebSocket
connect hi nahi hoga. Isliye hum **Render.com** use karenge — wahan
free me *asli hamesha-chalne-wala server* milta hai, aur is repo ke
liye sab taiyaar hai: repo ki root me `render.yaml` aur `backend/`
me `Dockerfile` pada hai.

---

## Step 1 — Render par ek-click deploy (≈5 minute)

1. [render.com](https://render.com) par free account banao
   (GitHub se sign up sabse aasan).
2. Dashboard me **New +** → **Blueprint**.
3. Apna **`ifallmusic`** GitHub repo select karo → **Connect**.
4. Render khud `render.yaml` padh lega — service ka naam
   `ifallmusic-party` dikhega → **Apply** dabao.
5. 3–5 minute build hoga. Ho jane par server is address par live hoga:

   ```
   https://ifallmusic-party.onrender.com
   ```

6. Browser me kholkar test karo:

   ```
   https://ifallmusic-party.onrender.com/healthz
   ```

   `{"ok":true,...}` dikha matlab server chal raha hai. 🎉

*Region agar Singapore select karne me dikkat aaye to `render.yaml`
se `region:` wali line hata kar dubara try karo — kaam kisi bhi
region me karega, Singapore bas India ke liye sabse tez hai.*

---

## Step 2 — App ko jodna

Step 1 ke baad kuch karna hi nahi hai: app ka default server
`https://ifallmusic-party.onrender.com` set hai, deploy hote hi app
connect hone lagta hai. Apna phone test karne ke liye app me
**Listen Together → Create room** dabao — code ban gaya matlab sab
set hai.

### Optional, baad me: `party.ifallmusic.app` custom domain

Sirf sundarta ke liye (invite links me onrender ki jagah apna naam).
Agar `ifallmusic.app` domain tumhare paas hai (jahan bhi DNS hai —
Cloudflare/Namecheap/etc.):

1. Render dashboard → `ifallmusic-party` service → **Settings →
   Custom Domains → Add Custom Domain** → `party.ifallmusic.app` likho.
2. Render ek **CNAME** value dega. Apne DNS provider me record banao:
   - Type: `CNAME`
   - Name/Host: `party`
   - Value/Target: Render ki di hui value (kuch aisi:
     `ifallmusic-party.onrender.com`)
3. 5–30 minute me Render domain verify karke **free HTTPS certificate**
   laga dega.
4. Test: `https://party.ifallmusic.app/healthz`

Domain lagte hi us par jo invite links banenge wo bhi app me
khulenge (deep link dono hosts ke liye registered hai). Jab domain
chalu ho jaye to bata dena — app ka default bhi
`party.ifallmusic.app` kar dunga taaki sab jagah wahi naam dikhe.
Tab tak onrender wala address hi kaafi hai.

---

## Free tier ka sach — aur uska ilaaj (BitChord wala tareeqa)

Render free service **15 minute koi na aaye to so jata hai**, aur
jaagne me ~1 minute leta hai. BitChord (jis app se ye server design
aaya hai) production me isse bilkul nahi ladta — unka server ek
**hamesha-jaagti free VM** (Oracle Cloud Always Free) par chalta hai,
aur Render ke liye unki salah hai: *"free uptime monitor, har 12
minute `/healthz` ping kare"*. Humne wahi ilaaj do jagah lagaya hai,
taaki server soye hi na:

1. **Server khud ko jagaye rakhta hai** (`backend/keepalive.go`):
   chalte hue process har 10 minute apne public `/healthz` ko
   request karta hai (Render khud `RENDER_EXTERNAL_URL` deta hai).
   Band karna ho to env `JAM_SELF_PING=off`.
2. **GitHub bhi har 10 minute ping karta hai**
   (`.github/workflows/party_server.yml`, Actions tab me dikhta hai)
   — agar server kabhi gir bhi gaya to ye use jaga dega. Yehi
   workflow **Run workflow** dabane par asal server par poora test
   chalata hai (create, join, queue, chat) — `backend/tools/jam_probe.py`.
   Bina APK download kiye server ki sehat dekhni ho to yahi dabao.

Aur agar kisi din dono ke bawajood server thanda mila, to app ab
haar nahi maanta: Create/Join tab tak sabr se koshish karte hai jab
tak room na ban jaye (screen par "Waking up the room server…" aur
**Cancel** button ke saath), bilkul BitChord ke app ki tarah jiska
create-request bina timeout ke server ke jaagne ka intezaar karta hai.

- Ek baar jaag jaye to jab tak log use kar rahe hai, full speed.
- Aur pakka upay chahiye to wahi BitChord wala: Oracle Always Free VM
  par `backend/deploy/setup.sh` se install (repo me taiyaar hai),
  ya Render Starter (~$7/month).

## Kuch kaam ki baatein

- **Updates automatic hain**: GitHub ke `main` branch par `backend/`
  me koi fix merge hote hi Render khud naya version deploy kar deta
  hai (`autoDeploy: true`). Rooms deploy ke time reset ho jate hai
  (sab data memory me hai — ye by-design hai).
- **Logs**: Render dashboard → service → **Logs** tab.
- Settings (env vars) defaults sahi hai; sirf ye Render par set hai:
  - `PORT` — Render khud deta hai, server use padhta hai.
  - `JAM_TRUST_PROXY=true` — invite links `https://` wale banne ke liye.
  - `JAM_PUBLIC_ORIGIN` — **abhi khaali chhodo**. Server khud sahi
    address pehchanta hai. Galat/hara-hua address daal diya to purane
    invite links users ko mare hue server par bhej denge.

## Local chalana ho to

```bash
cd backend
go run .          # ya: docker build -t party . && docker run -p 8000:8000 party
# http://localhost:8000/healthz
```
