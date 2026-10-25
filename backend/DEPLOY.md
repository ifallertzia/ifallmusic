# Listen Together server — FREE deploy guide

App rooms ke liye `https://party.ifallmusic.app` par baat karta hai.
Wo server yehi Go program hai (`backend/` folder). Is file me use
**bilkul free me live** karne ka pura tareeqa hai — na code download
karna hai, na kuch install. Repo already ready hai.

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

## Step 2 — App ko jodna (do raaste)

### Raasta A (best): `party.ifallmusic.app` custom domain

Agar `ifallmusic.app` domain tumhare paas hai (jahan bhi DNS hai —
Cloudflare/Namecheap/etc.), to app ko **koi update nahi lagega**,
kyunki app pehle se hi `party.ifallmusic.app` par jaata hai:

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

Bas — ab har user ka app seedha connect hoga.

### Raasta B: domain nahi hai to

`onrender.com` wala address bhi chalega, bas app ko batana hoga:

- **Test ke liye abhi**: app me **Listen Together** tab ke neeche
  **Room server** row hai — wahan
  `https://ifallmusic-party.onrender.com` daal do, apne phone par
  turant test ho jayega.
- **Sab users ke liye**: wo URL mujhe bhej do, main app ka default
  server usi par karke chhota sa update nikaal dunga. (Baad me domain
  mil jaye to Raasta A par shift kar sakte ho.)

---

## Free tier ka sach (chhoti si keemat)

- Render free service **15 minute koi na aaye to so jata hai**. Pehla
  user room banane aaye to server jaagne me **~1 minute** lag sakta
  hai (app khud retry/reconnect karta hai, isliye user ko bas thoda
  intezaar dikhega, error nahi).
- Ek baar jaag jaye to jab tak log use kar rahe hai, full speed.
- Hamesha jaagta chahiye to Render ka sabse sasta paid plan
  (Starter, ~$7/month) — baad ki baat hai, shuruaat free se karo.

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
