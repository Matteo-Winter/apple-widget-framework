#!/usr/bin/env python3
"""Host-side experiment driver for the Simulator (stdlib + Pillow).

  lab.py events [--since MS]           print App Group events (JSON lines)
  lab.py write <surface.json|preset>   write surface.json directly into the App Group (NO reload)
  lab.py push silent|widget|activity|alert|text [surface.json]   send a push via simctl
  lab.py open <agentlab://...>         open automation URL (brings app to foreground)
  lab.py watch --timeout S [--region x0,y0,x1,y1] [--label NAME]
                                        screenshot-poll until the region changes; prints latency
  lab.py shot <file.png>
  lab.py outbox | surface

Environment: AWL_SIM (default: booted), AWL_BUNDLE (default: AWL_APP_BUNDLE_ID from prototype/Config/Local.xcconfig).
"""
import json, os, subprocess, sys, tempfile, time

SIM = os.environ.get("AWL_SIM", "booted")
def _bundle_from_xcconfig():
    p = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "prototype", "Config", "Local.xcconfig")
    try:
        for line in open(p):
            if line.strip().startswith("AWL_APP_BUNDLE_ID"):
                return line.split("=", 1)[1].strip()
    except OSError:
        pass
    return "com.example.AgentWidgetLab"


BUNDLE = os.environ.get("AWL_BUNDLE") or _bundle_from_xcconfig()
GROUP = "group." + BUNDLE
HERE = os.path.dirname(os.path.abspath(__file__))
RUNTIME = os.path.join(HERE, "runtime"); os.makedirs(RUNTIME, exist_ok=True)


def now_ms():
    return int(time.time() * 1000)


def sh(*a, check=True):
    return subprocess.run(a, check=check, capture_output=True, text=True).stdout.strip()


def group_dir():
    return sh("xcrun", "simctl", "get_app_container", SIM, BUNDLE, GROUP)


def events(since=0):
    p = os.path.join(group_dir(), "events.jsonl")
    if not os.path.exists(p):
        return []
    out = []
    for line in open(p):
        try:
            e = json.loads(line)
            if e["t"] >= since:
                out.append(e)
        except Exception:
            pass
    return out


def write_surface(obj):
    p = os.path.join(group_dir(), "surface.json")
    tmp = p + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f)
    os.replace(tmp, p)
    return now_ms()


def current_surface():
    with open(os.path.join(group_dir(), "surface.json")) as f:
        return json.load(f)


def write_config(**kw):
    p = os.path.join(group_dir(), "config.json")
    cfg = {"bridgeURL": "http://127.0.0.1:8787", "pullOnReload": False, "postResponses": True}
    if os.path.exists(p):
        cfg.update(json.load(open(p)))
    cfg.update(kw)
    json.dump(cfg, open(p, "w"))
    return cfg


def push(kind, surface=None, extra=None):
    """Simulator pushes. Topic suffixes follow Apple's APNs topic conventions."""
    target = BUNDLE
    if kind == "silent":
        payload = {"aps": {"content-available": 1}}
        if surface:
            payload["surface"] = surface
    elif kind == "widget":
        target = BUNDLE + ".push-type.widgets"
        payload = {"aps": {"content-changed": True}}
    elif kind == "activity":
        target = BUNDLE + ".push-type.liveactivity"
        payload = {"aps": {"timestamp": int(time.time()), "event": "update",
                           "content-state": {"surface": surface, "sentAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}}}
    elif kind in ("alert", "text"):
        s = surface or {}
        payload = {"aps": {"alert": {"title": s.get("agent", "Agent"), "body": "Needs a decision" if kind == "alert" else "Reply with text"},
                           "category": "AGENT_CHOICE" if kind == "alert" else "AGENT_TEXT",
                           "interruption-level": "time-sensitive"},
                   "surfaceId": s.get("id"), "revision": s.get("revision")}
    else:
        raise SystemExit("unknown push kind")
    if extra:
        payload.update(extra)
    if kind == "silent" and (surface or extra):
        # Simulator drops content-available payloads (delivered as background fetch);
        # the app reads this file instead. On device, APNs carries the payload itself.
        with open(os.path.join(group_dir(), "sim-push-payload.json"), "w") as f:
            json.dump({k: v for k, v in payload.items() if k != "aps"}, f)
    payload["Simulator Target Bundle"] = target
    fd, path = tempfile.mkstemp(suffix=".json", dir=RUNTIME)
    with os.fdopen(fd, "w") as f:
        json.dump(payload, f)
    t = now_ms()
    r = subprocess.run(["xcrun", "simctl", "push", SIM, target, path], capture_output=True, text=True)
    return t, r.returncode, (r.stdout + r.stderr).strip()


def home(times=2):
    """Home button via the Simulator's Cmd+Shift+H shortcut (needs macOS Accessibility permission)."""
    for _ in range(times):
        subprocess.run(["osascript", "-e", 'tell application "Simulator" to activate', "-e", "delay 0.2", "-e",
                        'tell application "System Events" to keystroke "h" using {command down, shift down}'],
                       capture_output=True)
        time.sleep(0.8)


def shot(path):
    subprocess.run(["xcrun", "simctl", "io", SIM, "screenshot", path], capture_output=True)


def watch(timeout=60.0, region=None, baseline=None):
    """Polls screenshots until the region differs from the baseline. Returns (ms_detected, n_frames, frame_ms).
    Resolution is limited by screenshot time (~150–400 ms per frame on this Mac)."""
    from PIL import Image, ImageChops
    tmp = os.path.join(RUNTIME, "watch.png")
    def grab():
        shot(tmp)
        im = Image.open(tmp).convert("L")
        return im.crop(region) if region else im
    base = baseline or grab()
    t0 = time.time(); n = 0; frame_times = []
    while time.time() - t0 < timeout:
        f0 = time.time()
        cur = grab(); n += 1
        frame_times.append(time.time() - f0)
        diff = ImageChops.difference(base, cur)
        hist = diff.histogram()
        changed = sum(hist[30:])  # pixels that changed by > 30 levels
        if changed > 400:
            return now_ms(), n, int(1000 * sum(frame_times) / len(frame_times))
    return None, n, int(1000 * sum(frame_times) / max(1, len(frame_times)))


def baseline(region=None):
    from PIL import Image
    tmp = os.path.join(RUNTIME, "baseline.png")
    shot(tmp)
    im = Image.open(tmp).convert("L")
    return im.crop(region) if region else im


# Medium widget region on iPhone 17 Pro (1206x2622 px) in the lab layout: below the small widget row.
MEDIUM = (80, 870, 1130, 1360)
SMALL = (80, 270, 570, 760)


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__); return
    cmd = a[0]
    if cmd == "events":
        since = int(a[a.index("--since") + 1]) if "--since" in a else 0
        for e in events(since):
            print(json.dumps(e))
    elif cmd == "write":
        obj = json.load(open(a[1]))
        print(write_surface(obj))
    elif cmd == "push":
        s = json.load(open(a[2])) if len(a) > 2 else None
        print(push(a[1], s))
    elif cmd == "open":
        print(now_ms()); sh("xcrun", "simctl", "openurl", SIM, a[1])
    elif cmd == "shot":
        shot(a[1])
    elif cmd == "surface":
        print(json.dumps(current_surface(), indent=1))
    elif cmd == "outbox":
        print(open(os.path.join(group_dir(), "outbox.json")).read())
    elif cmd == "watch":
        to = float(a[a.index("--timeout") + 1]) if "--timeout" in a else 60
        print(watch(to, MEDIUM))


if __name__ == "__main__":
    main()
