"""
Smoke-probes a running party server the way two phones would.

    python jam_probe.py [server]   (default: the production Render service)

Creates one real party, joins it as a guest, opens both WebSockets,
pushes a queue as the host and a chat message, and checks the guest
sees both. Every step prints one `PROBE <name> PASS|FAIL <detail>`
line; the exit code is 0 only if everything passed. CI runs this on
demand (.github/workflows/party_server.yml) so "does the live server
actually work" never has to be answered by installing an APK.

The first requests are given minutes, on purpose: a free-tier server
may be asleep, and one patient request riding out the cold start is
exactly what the app does. Their timings are printed, so a slow
wake-up is visible instead of mysterious.
"""

import asyncio
import json
import sys
import time
import uuid
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import websockets

DEFAULT_SERVER = "https://ifallmusic-party.onrender.com"

_results = []


def report(name, ok, detail=""):
    _results.append(ok)
    print(f"PROBE {name} {'PASS' if ok else 'FAIL'} {detail}".rstrip(), flush=True)


def call(method, url, body=None, timeout=60):
    data = json.dumps(body).encode() if body is not None else None
    req = Request(
        url, data=data, headers={"Content-Type": "application/json"}, method=method
    )
    t0 = time.time()
    try:
        with urlopen(req, timeout=timeout) as resp:
            return resp.status, json.loads(resp.read() or b"{}"), time.time() - t0
    except HTTPError as e:
        raw = e.read() or b"{}"
        try:
            parsed = json.loads(raw)
        except Exception:
            parsed = {"raw": raw[:200].decode(errors="replace")}
        return e.code, parsed, time.time() - t0


def identity(name):
    suffix = uuid.uuid4().hex[:12]
    return {
        "userId": f"probe-{suffix}",
        "deviceId": f"dev-{suffix}",
        "displayName": name,
    }


def track(n):
    return {
        "videoId": f"probevid{n:03d}",
        "title": f"Probe Track {n}",
        "artist": "Probe",
        "thumbnailUrl": "",
        "durationMs": 180000,
        "fromAutoplay": False,
    }


class Member:
    """One phone: its socket, and every frame the server has sent it."""

    def __init__(self, code, token, base):
        self.code = code
        self.token = token
        self.ws_url = base.replace("https://", "wss://").replace("http://", "ws://")
        self.ws = None
        self.frames = []

    async def connect(self):
        self.ws = await asyncio.wait_for(
            websockets.connect(
                f"{self.ws_url}/ws/parties/{self.code}",
                additional_headers={"Authorization": f"Bearer {self.token}"},
            ),
            timeout=30,
        )
        asyncio.create_task(self._read())

    async def _read(self):
        try:
            async for raw in self.ws:
                self.frames.append(json.loads(raw))
        except Exception:
            pass

    async def wait_frame(self, pred, timeout=15):
        deadline = time.time() + timeout
        while time.time() < deadline:
            for frame in self.frames:
                if pred(frame):
                    return frame
            await asyncio.sleep(0.1)
        return None

    async def send(self, frame):
        await self.ws.send(json.dumps(frame))

    async def close(self):
        if self.ws:
            await self.ws.close()


def queue_items(frame):
    queue = frame.get("queue") or (frame.get("party") or {}).get("queue") or {}
    return queue.get("items") or []


async def main():
    base = (sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SERVER).rstrip("/")
    print(f"probing {base}", flush=True)

    status, body, dt = call("GET", f"{base}/healthz", timeout=240)
    report(
        "healthz",
        status == 200 and body.get("ok") is True,
        f"status={status} {dt:.1f}s",
    )

    status, body, dt = call(
        "POST",
        f"{base}/api/parties",
        {**identity("ProbeHost"), "maxMembers": 5, "autoplayEnabled": True},
        timeout=240,
    )
    code, host_token = body.get("code"), body.get("token")
    report(
        "create",
        status in (200, 201) and bool(code) and bool(host_token),
        f"status={status} {dt:.1f}s code={code} body={body if status not in (200, 201) else ''}",
    )
    if not (code and host_token):
        print("PROBE ALL FAIL cannot continue without a room", flush=True)
        return 1

    status, body, dt = call("GET", f"{base}/api/parties/{code}/preview", timeout=60)
    report(
        "preview",
        status == 200 and body.get("memberCount", 0) >= 1,
        f"status={status} members={body.get('memberCount')}",
    )

    status, body, dt = call(
        "POST", f"{base}/api/parties/{code}/join", identity("ProbeGuest"), timeout=60
    )
    guest_token = body.get("token")
    report(
        "join",
        status in (200, 201) and bool(guest_token),
        f"status={status} {dt:.1f}s",
    )
    if not guest_token:
        print("PROBE ALL FAIL cannot continue without a guest", flush=True)
        return 1

    host = Member(code, host_token, base)
    guest = Member(code, guest_token, base)
    try:
        await host.connect()
        await guest.connect()
        welcomed = await guest.wait_frame(lambda f: f.get("type") == "welcome")
        report("websockets", welcomed is not None, "guest welcomed" if welcomed else "no welcome frame")

        await host.send(
            {
                "type": "control",
                "action": "setQueue",
                "queue": [track(1), track(2)],
                "queueIndex": 0,
            }
        )
        seen = await guest.wait_frame(
            lambda f: [t.get("videoId") for t in queue_items(f)]
            == ["probevid001", "probevid002"]
        )
        report("queue-sync", seen is not None, "guest saw host queue" if seen else "guest queue never matched")

        chat_id = str(uuid.uuid4())
        await host.send({"type": "chat", "id": chat_id, "text": "probe hello"})

        def is_chat(frame):
            if frame.get("type") != "chat":
                return False
            message = frame.get("message") or {}
            return message.get("text") == "probe hello" or frame.get("text") == "probe hello"

        heard = await guest.wait_frame(is_chat)
        report("chat", heard is not None, "guest got host chat" if heard else "chat never arrived")
    finally:
        await guest.close()
        await host.close()

    ok = all(_results)
    print(f"PROBE ALL {'PASS' if ok else 'FAIL'} {sum(_results)}/{len(_results)} steps", flush=True)
    return 0 if ok else 1


sys.exit(asyncio.run(main()))
