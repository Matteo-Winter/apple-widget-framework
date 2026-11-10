"""RenderLab host helpers (Simulator). Builds on tools/lab.py."""
import json, os, sys, time, subprocess, shutil
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import lab  # noqa

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "experiments", "rendering")
IMG = os.path.join(OUT, "img"); RAW = os.path.join(OUT, "raw"); DATA = os.path.join(OUT, "data")
for d in (IMG, RAW, DATA): os.makedirs(d, exist_ok=True)
RENDER = os.path.join(ROOT, "tools", "runtime", "rl_render")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# Home Screen layout of the lab Simulator (iPhone 17 Pro, 1206x2622 px, scale 3):
# page 1 = RenderLab large (top) + RenderLab medium (bottom).
LARGE = (80, 270, 1128, 1368)
MEDIUM = (80, 1476, 1128, 1970)
BOTH = (80, 270, 1128, 1970)

def gdir():
    d = os.path.join(lab.group_dir(), "renderlab"); os.makedirs(d, exist_ok=True); return d

def put(name, obj):
    p = os.path.join(gdir(), name)
    if isinstance(obj, (dict, list)):
        with open(p + ".tmp", "w") as f: json.dump(obj, f)
        os.replace(p + ".tmp", p)
    elif isinstance(obj, bytes):
        open(p, "wb").write(obj)
    else:
        shutil.copyfile(obj, p)
    return p

def spec(run, technique, **kw):
    s = {"run": run, "technique": technique}; s.update(kw); put("spec.json", s); return s

def trigger(cmd=None):
    """Background (silent) push → app (not foreground) → optional pre-render → reloadTimelines."""
    t, rc, out = lab.push("silent", extra={"renderlab": cmd or {"op": "reload"}})
    return t

def events(since, names=None):
    return [e for e in lab.events(since) if names is None or e["e"] in names]

def kv(d):
    out = {}
    for tok in (d or "").split(" "):
        if "=" in tok:
            k, v = tok.split("=", 1)
            try: v = float(v) if "." in v else int(v)
            except ValueError: pass
            out[k] = v
    return out

def shot(path):
    lab.shot(path); return path

def crop(src, box, dst):
    from PIL import Image
    Image.open(src).crop(box).save(dst); return dst

def launch_fg(cmd):
    """Foreground path: launch the app with a pre-render command (no push)."""
    t = lab.now_ms()
    subprocess.run(["xcrun", "simctl", "launch", "--terminate-running-process", lab.SIM, lab.BUNDLE, "-rlcmd", __import__("base64").b64encode(json.dumps(cmd).encode()).decode()],
                   capture_output=True, text=True)
    return t

def wait_event(name, since, timeout):
    end = time.time() + timeout
    while time.time() < end:
        for e in lab.events(since):
            if e["e"] == name: return e
        time.sleep(0.2)
    return None

def run_case(run, technique, cmd=None, timeout=20, region=BOTH, settle=1.5, save=True, home=True, fg=False, wait_archive=True, archive_timeout=60, **spec_kw):
    """Writes the spec, triggers, measures stages, saves screenshots. Returns a row dict."""
    if home: lab.home(1); time.sleep(0.6)
    base = lab.baseline(region)
    since = lab.now_ms()
    spec(run, technique, **spec_kw)
    if fg:
        t0 = launch_fg(cmd)
        wait_event("reload_requested", t0, 30); time.sleep(0.3); lab.home(2)
    else:
        t0 = trigger(cmd)
        if cmd and cmd.get("jobs"): wait_event("reload_requested", t0, 40)
    # Simulator artifact: every simctl push makes SpringBoard switch to home page 2
    # ("Current home screen page changed to: 2"); one Home press returns to page 1.
    if home and not fg: time.sleep(0.25); lab.home(1)
    seen, frames, frame_ms = lab.watch(timeout, region, base)
    arch = []
    if wait_archive:
        import archive_log as al
        end = time.time() + archive_timeout
        while time.time() < end:
            arch = [q for q in al.archive_requests("3m") if q["began"] >= t0 - 200 and q["kind"] == "RenderLab"]
            if len({q["family"] for q in arch}) >= 2: break
            time.sleep(1.0)
    time.sleep(settle)
    full = os.path.join(RAW, f"{run}.png"); shot(full)
    if save:
        crop(full, LARGE, os.path.join(IMG, f"{run}-large.png"))
        crop(full, MEDIUM, os.path.join(IMG, f"{run}-medium.png"))
    ev = events(since)
    def first(name, pred=lambda e: True):
        return next((e for e in ev if e["e"] == name and pred(e)), None)
    tl = [dict(kv(e.get("d")), t=e["t"]) for e in ev if e["e"] == "rl_timeline" and f"run={run}" in e.get("d", "")]
    views = [e for e in ev if e["e"] == "rl_view" and f"run={run}" in e.get("d", "")]
    draws = [dict(kv(e.get("d")), t=e["t"]) for e in ev if e["e"] == "rl_canvas_draw" and f"run={run}" in e.get("d", "")]
    pres = [kv(e.get("d")) | {"at_ms": e["t"] - t0} for e in ev if e["e"] == "rl_prerender"]
    pre = first("rl_prerender"); push = first("rl_push"); rr = first("reload_requested")
    rel = lambda e: None if e is None else e["t"] - t0
    row = {"run": run, "technique": technique, "trigger_ms": t0,
           "push_to_app_ms": rel(push), "prerender": kv(pre.get("d")) if pre else None, "prerender_all": pres, "prerender_done_ms": rel(pre),
           "reload_requested_ms": rel(rr),
           "timeline": [{k: v for k, v in x.items() if k != "t"} | {"at_ms": x["t"] - t0} for x in tl],
           "view_evals": len(views), "first_view_ms": (views[0]["t"] - t0) if views else None,
           "canvas_draws": [{k: v for k, v in x.items() if k != "t"} | {"at_ms": x["t"] - t0} for x in draws],
           "archive": arch, "archive_done_ms": (max(q["end"] for q in arch) - t0) if arch else None,
           "visible_ms": (seen - t0) if seen else None, "screenshot_frame_ms": frame_ms,
           "screenshot": os.path.relpath(full, ROOT)}
    return row

def save_rows(name, rows):
    p = os.path.join(DATA, f"{name}.json")
    json.dump(rows, open(p, "w"), indent=1); return p
