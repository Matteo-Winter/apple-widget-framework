#!/usr/bin/env python3
"""Host-side Simulator experiments. Usage: run_experiments.py E02 E08 ...  (or 'all')
Requires: app installed, Agent Surface widgets on Home Screen page 1, bridge.py on :8787.
Writes experiments/raw/host-<ID>.json. Visible change = screenshot diff of the widget area."""
import json, os, subprocess, sys, time, urllib.request
sys.path.insert(0, os.path.dirname(__file__))
import lab

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "experiments", "raw"); os.makedirs(RAW, exist_ok=True)
WIDGETS = (70, 260, 1140, 1440)  # small + medium widget area on iPhone 17 Pro, page 1


def iso(t=None):
    t = time.time() if t is None else t
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%03dZ" % int((t % 1) * 1000)


def T(text, style="body", **kw): return {"type": "text", "text": text, "style": style, **kw}


def status_surface(rev, title, agent="Host Agent"):
    return {"schema": 1, "id": f"host-{rev}", "agent": agent, "revision": rev, "issuedAt": iso(),
            "root": {"type": "vstack", "spacing": 6, "children": [
                {"type": "hstack", "children": [T(agent.upper(), "caption", color="secondary", weight="semibold"),
                                                 {"type": "spacer"}, {"type": "badge", "text": f"REV {rev}"}]},
                T(title, "title", weight="bold"),
                T(iso(), "mono", color="secondary"),
                {"type": "progress", "value": (rev % 10) / 10}]}}


def decision_surface(rev, agent="Host Agent"):
    s = status_surface(rev, "Deploy to production?", agent)
    s["id"] = f"host-decision-{rev}"
    s["root"]["children"][3] = {"type": "hstack", "children": [
        {"type": "button", "text": "Ship", "action": "ship", "prominent": True},
        {"type": "button", "text": "Hold", "action": "hold"}]}
    return s


def cur_rev():
    try: return int(lab.current_surface().get("revision", 0))
    except Exception: return 0


def terminate_app():
    subprocess.run(["xcrun", "simctl", "terminate", lab.SIM, lab.BUNDLE], capture_output=True)
    time.sleep(0.8)
    lab.home(2)
    time.sleep(1.0)


def first_event(name, since, timeout=0.0):
    t_end = time.time() + timeout
    while True:
        for e in lab.events(since):
            if e["e"] == name:
                return e
        if time.time() >= t_end:
            return None
        time.sleep(0.1)


def measure_visible(trigger, timeout=30.0):
    lab.home(2); time.sleep(0.8)
    base = lab.baseline(WIDGETS)
    t0 = trigger()
    seen, frames, frame_ms = lab.watch(timeout, WIDGETS, base)
    return t0, seen, frames, frame_ms


def save(name, obj):
    with open(os.path.join(RAW, f"host-{name}.json"), "w") as f:
        json.dump(obj, f, indent=1)
    print(json.dumps(obj.get("summary", obj), indent=1))


def rel(a, b): return None if a is None or b is None else round((a - b) / 1000, 3)


# ---------------------------------------------------------------------------

def E02(observe=180):
    """Shared-data change WITHOUT any reload request; app terminated."""
    terminate_app()
    lab.write_config(pullOnReload=False)
    rev = cur_rev() + 1
    t0, seen, frames, fms = measure_visible(lambda: lab.write_surface(status_surface(rev, "Silent write")), observe)
    gt = first_event("get_timeline", t0)
    save("E02", {"summary": {"observeSeconds": observe, "visibleChange": seen is not None,
                             "write_to_visible_s": rel(seen, t0), "getTimelineAfterWrite": gt is not None,
                             "write_to_getTimeline_s": rel(gt and gt["t"], t0), "frames": frames, "frameMs": fms}})


def E10(n=6):
    """Background push (content-available). Simulator delivers it as a background fetch without payload,
    so the app pulls the surface from the bridge, saves it and calls reloadAllTimelines."""
    rows = []
    lab.write_config(pullOnReload=False, bridgeURL="http://127.0.0.1:8787")
    for i in range(n):
        state = "terminated" if i % 2 == 0 else "suspended"
        if state == "terminated": terminate_app()
        rev = cur_rev() + 1
        body = json.dumps(status_surface(rev, f"Bg push {i}")).encode()
        urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8787/surface", body, {"Content-Type": "application/json"}))
        t0, seen, frames, fms = measure_visible(lambda: lab.push("silent")[0], 30)
        ev = lab.events(t0)
        def first(n): return next((e["t"] for e in ev if e["e"] == n), None)
        rows.append({"i": i, "appState": state, "push_to_wake_s": rel(first("perform_fetch") or first("silent_push"), t0),
                     "push_to_fetchDone_s": rel(first("bridge_fetch_ok"), t0),
                     "push_to_getTimeline_s": rel(first("get_timeline"), t0), "push_to_visible_s": rel(seen, t0), "frameMs": fms})
        time.sleep(3)
    save("E10", {"rows": rows, "summary": rows})


def E08(n=5):
    """WidgetKit push (iOS 26 API) via simctl: does a content-changed push trigger getTimeline?"""
    rows = []
    terminate_app()
    lab.write_config(pullOnReload=False)
    for i in range(n):
        rev = cur_rev() + 1
        lab.write_surface(status_surface(rev, f"Widget push {i}"))
        time.sleep(0.5)
        res = {}
        def trig():
            t, rc, out = lab.push("widget"); res.update(rc=rc, out=out); return t
        t0, seen, frames, fms = measure_visible(trig, 30)
        gt = first_event("get_timeline", t0, 2)
        rows.append({"i": i, "simctl_rc": res["rc"], "simctl_out": res["out"][:200],
                     "push_to_getTimeline_s": rel(gt and gt["t"], t0), "push_to_visible_s": rel(seen, t0), "frameMs": fms})
        time.sleep(2)
    save("E08", {"rows": rows, "summary": rows})


def E11(n=5):
    """Content-free WidgetKit push + pull-on-reload: the widget extension fetches the agent's surface itself."""
    terminate_app()
    lab.write_config(pullOnReload=True, bridgeURL="http://127.0.0.1:8787")
    rows = []
    for i in range(n):
        rev = cur_rev() + 1
        body = json.dumps(status_surface(rev, f"Pulled {i}")).encode()
        urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:8787/surface", body, {"Content-Type": "application/json"}))
        t0, seen, frames, fms = measure_visible(lambda: lab.push("widget")[0], 30)
        gt = first_event("get_timeline", t0, 2); bf = first_event("bridge_fetch_ok", t0, 2)
        rows.append({"i": i, "push_to_getTimeline_s": rel(gt and gt["t"], t0), "push_to_fetchDone_s": rel(bf and bf["t"], t0),
                     "push_to_visible_s": rel(seen, t0), "frameMs": fms})
        time.sleep(2)
    lab.write_config(pullOnReload=False)
    save("E11", {"rows": rows, "summary": rows})


def E05():
    """Invalid / oversized / too deep schemas → reload → must show safe fallback, no crash."""
    rows = []
    deep = {"type": "text", "text": "x"}
    for _ in range(12): deep = {"type": "vstack", "children": [deep]}
    big = {"type": "vstack", "children": [{"type": "text", "text": str(i)} for i in range(200)]}
    cases = {
        "not_json": "{this is not json",
        "missing_root": json.dumps({"id": "x", "agent": "a", "revision": 1}),
        "too_deep": json.dumps({"id": "x", "agent": "a", "revision": 999, "root": deep}),
        "too_many_nodes": json.dumps({"id": "x", "agent": "a", "revision": 999, "root": big}),
        "unknown_type": json.dumps({"id": "unk", "agent": "a", "revision": 999, "root": {"type": "vstack", "children": [
            {"type": "webview", "url": "https://example.com"}, {"type": "text", "text": "Unknown node ignored", "style": "headline"}]}}),
    }
    for name, raw in cases.items():
        since = lab.now_ms()
        with open(os.path.join(lab.group_dir(), "surface.json"), "w") as f: f.write(raw)
        lab.push("silent", extra={"reloadOnly": 1})
        time.sleep(3); lab.home(2); time.sleep(1)
        shot = os.path.join(RAW, f"E05-{name}.png"); lab.shot(shot)
        inv = first_event("surface_invalid", since)
        gt = first_event("get_timeline", since)
        rows.append({"case": name, "getTimeline": gt is not None, "invalidLogged": inv and inv.get("d"), "screenshot": os.path.basename(shot)})
    save("E05", {"rows": rows, "summary": rows})


def E12(n=20, gap=1.0):
    """Burst: n silent pushes `gap` s apart. How many distinct reloads/renders does the system grant?"""
    terminate_app()
    since = lab.now_ms()
    for i in range(n):
        rev = cur_rev() + 1
        lab.push("silent", status_surface(rev, f"Burst {i}"))
        time.sleep(gap)
    time.sleep(5)
    ev = lab.events(since)
    sp = [e for e in ev if e["e"] in ("silent_push", "perform_fetch")]
    gt = [e for e in ev if e["e"] == "get_timeline"]
    save("E12", {"summary": {"pushes": n, "gapSeconds": gap, "silentPushHandled": len(sp),
                             "getTimelineCalls": len(gt), "families": sorted({e.get("d") for e in gt})}})


def E13(n=30):
    """Foreground app calling reloadAllTimelines repeatedly (budget exempt while foreground per Apple)."""
    # driven through the app: the URL scheme requires a confirmation dialog in simctl, so this
    # experiment is executed by the UI test testH_ForegroundReloadBurst instead.
    pass


def E04(step=30):
    """Pre-scheduled timeline entries: one write, 5 layout switches at known instants, no further updates."""
    terminate_app()
    now = time.time()
    names = ["Queued", "Compiling", "Testing", "Uploading", "Done"]
    rev = cur_rev() + 1
    s = status_surface(rev, "Plan start")
    s["schedule"] = [{"at": iso(now + step * (i + 1)), "root": status_surface(rev, n)["root"]} for i, n in enumerate(names)]
    for i, sch in enumerate(s["schedule"]):
        sch["root"]["children"][1]["text"] = names[i]
        sch["root"]["children"][2]["text"] = "planned " + sch["at"][11:19]
    lab.write_surface(s)
    lab.push("silent", extra={"reloadOnly": 1})
    time.sleep(3)
    lab.home(2)
    rows = []
    for i in range(len(names)):
        target = now + step * (i + 1)
        while time.time() < target - 3: time.sleep(0.2)
        seen, frames, fms = lab.watch(step, WIDGETS, lab.baseline(WIDGETS))
        rows.append({"step": names[i], "planned": iso(target), "drift_s": rel(seen, target * 1000), "frameMs": fms,
                     "getTimelineNear": any(abs(e["t"] - target * 1000) < 3000 for e in lab.events(int(target * 1000) - 3000) if e["e"] == "get_timeline")})
        lab.shot(os.path.join(RAW, f"E04-{i}.png"))
    save("E04", {"rows": rows, "summary": rows})


if __name__ == "__main__":
    ids = sys.argv[1:] or ["all"]
    order = ["E05", "E08", "E11", "E10", "E12", "E04", "E02"]
    for x in (order if ids == ["all"] else ids):
        print("=== ", x, flush=True)
        globals()[x]()
