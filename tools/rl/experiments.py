#!/usr/bin/env python3
"""RenderLab experiments (Simulator). Usage: python3 experiments.py T1|T2|T3|T4px|T4ops|T4fmt|NEG|MARGIN ...
Results: experiments/rendering/data/<name>.json, screenshots in experiments/rendering/img/."""
import json, os, subprocess, sys, time
import rlcore as rc
import surfaces as sf

FAM = ["systemLarge", "systemMedium"]
WORK = os.path.join(rc.RAW, "work"); os.makedirs(WORK, exist_ok=True)

def sh(*a):
    t = time.time(); r = subprocess.run(a, capture_output=True, text=True); return r, int((time.time() - t) * 1000)

def server_cg(scene_file, out, pw, ph, q=0.85):
    r, ms = sh(rc.RENDER, scene_file, out, str(pw), str(ph), WORK, str(q))
    info = json.loads(r.stdout) if r.stdout.startswith("{") else {"err": r.stdout + r.stderr}
    info["wallMs"] = ms; return info

def chrome_png(html_file, out, w, h, scale=3):
    r, ms = sh(rc.CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--force-device-scale-factor={scale}",
               f"--window-size={w},{h}", f"--screenshot={out}", "--default-background-color=00000000", "file://" + html_file)
    return {"wallMs": ms, "ok": os.path.exists(out), "bytes": os.path.getsize(out) if os.path.exists(out) else 0}

def chrome_pdf(html_file, out):
    r, ms = sh(rc.CHROME, "--headless=new", "--disable-gpu", "--no-pdf-header-footer", f"--print-to-pdf={out}", "file://" + html_file)
    return {"wallMs": ms, "ok": os.path.exists(out), "bytes": os.path.getsize(out) if os.path.exists(out) else 0}

def put_local(name, content):
    p = os.path.join(WORK, name)
    if isinstance(content, (dict, list)): json.dump(content, open(p, "w"))
    else: open(p, "w").write(content)
    return p

def assets():
    photo = os.path.join(WORK, "photo.png")
    if not os.path.exists(photo): sf.photo_png(photo)
    rc.put("photo.png", photo)

# ------------------------------------------------------------------ T1 free graphic

def T1():
    assets(); gen = {}
    for f in FAM:
        W, H = sf.SIZES[f]
        rc.put(f"t1-{f}.json", sf.t1(f)); put_local(f"t1-{f}.json", sf.t1(f))
        html = sf.t1_html(f); hp = put_local(f"t1-{f}.html", html); rc.put(f"t1-{f}.html", hp)
        gen[f"server-cg-{f}"] = server_cg(os.path.join(WORK, f"t1-{f}.json"), os.path.join(WORK, f"t1-srvcg-{f}.png"), W * 3, H * 3)
        rc.put(f"t1-srvcg-{f}.png", os.path.join(WORK, f"t1-srvcg-{f}.png"))
        gen[f"chrome-png-{f}"] = chrome_png(hp, os.path.join(WORK, f"t1-html-{f}.png"), W, H)
        rc.put(f"t1-html-{f}.png", os.path.join(WORK, f"t1-html-{f}.png"))
        pdfhtml = put_local(f"t1-pdf-{f}.html", html.replace("<style>", f"<style>@page{{size:{W}px {H}px;margin:0}}"))
        gen[f"chrome-pdf-{f}"] = chrome_pdf(pdfhtml, os.path.join(WORK, f"t1-{f}.pdf"))
        rc.put(f"t1-{f}.pdf", os.path.join(WORK, f"t1-{f}.pdf"))
    rc.put("t1.surface.json", sf.t1_json())
    print(json.dumps(gen, indent=1))
    jobs_cg = [{"op": "cg", "scene": f"t1-{f}.json", "out": f"t1-appcg-{f}.png", "pw": sf.SIZES[f][0] * 3, "ph": sf.SIZES[f][1] * 3} for f in FAM]
    jobs_html = [{"op": "html", "html": f"t1-{f}.html", "out": f"t1-apphtml-{f}.png", "pw": sf.SIZES[f][0] * 3, "ph": sf.SIZES[f][1] * 3} for f in FAM]
    cases = [
        ("t1-json", "json", None, dict(surfaceFile="t1.surface.json")),
        ("t1-views", "views", None, dict(scene="t1-{f}.json")),
        ("t1-canvas", "canvas", None, dict(scene="t1-{f}.json")),
        ("t1-cg-ext", "cg", None, dict(scene="t1-{f}.json")),
        ("t1-bitmap-app-cg", "bitmap", {"jobs": jobs_cg}, dict(bitmap="t1-appcg-{f}.png")),
        ("t1-bitmap-server-cg", "bitmap", None, dict(bitmap="t1-srvcg-{f}.png")),
        ("t1-bitmap-server-html", "bitmap", None, dict(bitmap="t1-html-{f}.png")),
        ("t1-bitmap-app-html", "bitmap", {"jobs": jobs_html}, dict(bitmap="t1-apphtml-{f}.png")),
        ("t1-pdf-server-html", "pdf", None, dict(pdf="t1-{f}.pdf")),
        ("t1-charts", "charts", None, dict(cgScale=60)),
    ]
    rows = []
    for run, tech, cmd, kw in cases:
        row = rc.run_case(run, tech, cmd=cmd, timeout=15, **kw); rows.append(row)
        print(run, {k: row[k] for k in ("visible_ms", "reload_requested_ms", "first_view_ms")}, [t.get("prepMs") for t in row["timeline"]], row["prerender"])
    rc.save_rows("T1", {"generation": gen, "rows": rows})

# ------------------------------------------------------------------ negative controls / special APIs

def NEG():
    assets(); rows = []
    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100"><rect width="200" height="100" fill="#FF7A18"/><circle cx="50" cy="50" r="40" fill="#111"/></svg>'
    rc.put("test.svg", svg.encode())
    font_src = "/System/Library/Fonts/Supplemental/Luminari.ttf"
    rc.put("runtime-font.ttf", font_src)
    font_scene = {"w": 349, "h": 164, "ops": [sf.R(0, 0, 349, 164, "#111111"),
        sf.T(16, 20, "Runtime font from App Group", 20, "#FFD166", font="Luminari-Regular"),
        sf.T(16, 60, "System font for comparison", 20, "#FFFFFF", "bold"),
        sf.T(16, 100, "Bundled iOS font: Didot", 20, "#9FE7FF", font="Didot")]}
    rc.put("font-scene.json", font_scene)
    for run, tech, kw in [("neg-uiview", "uiview", {}), ("neg-svg", "svg", dict(bitmap="test.svg")),
                          ("api-font-runtime", "font", dict(fontFile="runtime-font.ttf", scene="font-scene.json")),
                          ("api-coreimage-qr", "coreimage", {})]:
        row = rc.run_case(run, tech, timeout=12, **kw); rows.append(row)
        print(run, row["visible_ms"], [t.get("prepMs") for t in row["timeline"]], [{k: v for k, v in t.items() if k not in ("run",)} for t in row["timeline"]][:1])
    rc.save_rows("NEG", rows)


# ------------------------------------------------------------------ UI-test driver

PROJ = os.path.join(rc.ROOT, "prototype", "AgentWidgetLab.xcodeproj")
DD = os.path.expanduser("~/Library/Developer/Xcode/DerivedData/AWL")

def uitest(name, **env):
    e = dict(os.environ); e.update({f"TEST_RUNNER_{k}": str(v) for k, v in env.items()})
    r = subprocess.run(["xcodebuild", "test-without-building", "-project", PROJ, "-scheme", "AgentWidgetLab",
                        "-destination", "platform=iOS Simulator,name=iPhone 17 Pro", "-derivedDataPath", DD,
                        f"-only-testing:AgentWidgetLabUITests/RenderLabTests/{name}"], capture_output=True, text=True, env=e)
    out = []
    for line in r.stdout.splitlines():
        if line.startswith("AWL|"):
            _, t, k, j = line.split("|", 3)
            try: out.append((int(t), k, json.loads(j)))
            except Exception: pass
    ok = "** TEST EXECUTE SUCCEEDED **" in r.stdout
    return out, ok

def namespaced(scene, prefix):
    for r_ in scene.get("regions", []): r_["id"] = prefix + r_["id"]
    return scene

def match_hits(taps, since):
    """Assign each rl_hit event to the tap that precedes it (taps are ≥1 s apart)."""
    hits = [(e["t"], rc.kv(e["d"])) for e in rc.events(since, ["rl_hit"])]
    res = []
    for i, tp in enumerate(taps):
        t0 = tp["t"]; t1 = taps[i + 1]["t"] if i + 1 < len(taps) else t0 + 3000
        got = [h for h in hits if t0 - 300 <= h[0] < t1 - 300]
        res.append({**tp, "got": [g[1].get("region") for g in got], "intent_ms": (got[0][0] - t0) if got else None})
    return res

# Widget content frames in screen points (from the SpringBoard accessibility tree, see raw/a11y-home.txt)
FRAME = {"systemLarge": (26.3, 90.0, 349.7, 365.0), "systemMedium": (26.3, 491.3, 349.7, 164.3)}

def plan_points(scene, family, prefix="", edge=0, pane=None):
    fx, fy, fw, fh = FRAME[family]
    if pane:  # normalized pane frame inside the widget
        fx, fy, fw, fh = fx + pane["x"] * fw, fy + pane["y"] * fh, pane["w"] * fw, pane["h"] * fh
    s = min(fw / scene["w"], fh / scene["h"]); ox = fx + (fw - scene["w"] * s) / 2; oy = fy + (fh - scene["h"] * s) / 2
    pts = []
    for r_ in scene.get("regions", []):
        if not r_["id"].startswith(prefix): continue
        want = (pane["agent"] + ":" + r_["id"]) if pane else r_["id"]
        x0, y0, w, h = ox + r_["x"] * s, oy + r_["y"] * s, r_["w"] * s, r_["h"] * s
        pts.append([want, x0 + w / 2, y0 + h / 2, "c"])
        if edge:
            pts += [[want, x0 + edge, y0 + h / 2, "l"], [want, x0 + w - edge, y0 + h / 2, "r"],
                    [want, x0 + w / 2, y0 + edge, "t"], [want, x0 + w / 2, y0 + h - edge, "b"]]
    return pts

def tap_points(label, pts, gap=1300):
    import base64
    since = rc.lab.now_ms()
    out, ok = uitest("testTapPoints", RL_POINTS=base64.b64encode(json.dumps(pts).encode()).decode(), RL_GAP_MS=gap)
    taps = [o for _, k, o in out if k == "tap"]
    time.sleep(2)
    m = match_hits(taps, since)
    correct = sum(1 for x in m if x["got"] == [x["want"]])
    wrong = [x for x in m if x["got"] and x["got"] != [x["want"]]]
    missed = [x for x in m if not x["got"]]
    lat = sorted(x["intent_ms"] for x in m if x["intent_ms"] is not None)
    by_tag = {}
    for x in m:
        t = by_tag.setdefault(x["pt"], [0, 0]); t[1] += 1; t[0] += x["got"] == [x["want"]]
    return {"label": label, "taps": len(m), "correct": correct, "wrong": len(wrong), "missed": len(missed),
            "by_point": {k: f"{v[0]}/{v[1]}" for k, v in by_tag.items()},
            "tap_to_intent_ms_median": lat[len(lat) // 2] if lat else None, "tap_to_intent_ms_max": lat[-1] if lat else None,
            "wrong_examples": wrong[:8], "missed_examples": missed[:8], "uitest_ok": ok}, m

def T2():
    assets(); rows = []
    for f in FAM:
        p = "L." if f == "systemLarge" else "M."
        sc = namespaced(sf.t2(f), p); rc.put(f"t2-{f}.json", sc); put_local(f"t2-{f}.json", sc)
        W, H = sf.SIZES[f]
        hp = put_local(f"t2-{f}.html", sf.t2_html(f))
        chrome_png(hp, os.path.join(WORK, f"t2-html-{f}.png"), W, H); rc.put(f"t2-html-{f}.png", os.path.join(WORK, f"t2-html-{f}.png"))
    variants = [("t2-canvas-clear", "canvas", dict(scene="t2-{f}.json", regions=True, hitStyle="clear")),
                ("t2-canvas-faint", "canvas", dict(scene="t2-{f}.json", regions=True, hitStyle="faint")),
                ("t2-bitmap-html", "bitmap", dict(bitmap="t2-html-{f}.png", scene="t2-{f}.json", regions=True)),
                ("t2-cg-ext", "cg", dict(scene="t2-{f}.json", regions=True))]
    for run, tech, kw in variants:
        row = rc.run_case(run, tech, timeout=12, **kw)
        pts = plan_points(json.load(open(os.path.join(WORK, "t2-systemLarge.json"))), "systemLarge") + \
              plan_points(json.load(open(os.path.join(WORK, "t2-systemMedium.json"))), "systemMedium")
        summ, m = tap_points(run, pts); reg = None
        rc.lab.home(1); time.sleep(1.5)
        after = os.path.join(rc.RAW, f"{run}-after-taps.png"); rc.shot(after)
        rc.crop(after, rc.LARGE, os.path.join(rc.IMG, f"{run}-after-taps-large.png"))
        rows.append({"render": row, "tap": summ, "frames": reg, "taps": m})
        print(run, {k: summ[k] for k in ("taps", "correct", "wrong", "missed", "by_point", "tap_to_intent_ms_median")})
        rc.save_rows("T2", rows)
    # precision: near-edge taps on the smallest targets (22 pt) and the 60x34 slots
    rc.run_case("t2-edges", "canvas", timeout=12, scene="t2-{f}.json", regions=True)
    L = json.load(open(os.path.join(WORK, "t2-systemLarge.json")))
    for pre, edge in [("L.tiny", 3), ("L.tiny", 1), ("L.slot", 3), ("L.seat", 2)]:
        summ, m = tap_points(f"edges {pre} inset {edge}pt", plan_points(L, "systemLarge", pre, edge), gap=1200); reg = None
        rows.append({"tap": summ, "frames": reg, "taps": m})
        print(pre, edge, {k: summ[k] for k in ("taps", "correct", "wrong", "missed", "by_point")})
        rc.save_rows("T2", rows)


# ------------------------------------------------------------------ system log (WidgetKit errors)

def syslog(seconds, extra=""):
    pred = ('(process == "chronod" OR process == "AgentWidgetExtension" OR process == "SpringBoard") AND '
            '(eventMessage CONTAINS[c] "too large" OR eventMessage CONTAINS[c] "exceed" OR eventMessage CONTAINS[c] "archiv" '
            'OR eventMessage CONTAINS[c] "memory" OR eventMessage CONTAINS[c] "jetsam" OR eventMessage CONTAINS[c] "timed out" '
            'OR eventMessage CONTAINS[c] "RenderLab" OR eventMessage CONTAINS[c] "error")' + extra)
    r = subprocess.run(["xcrun", "simctl", "spawn", "booted", "log", "show", "--style", "compact", "--last", f"{int(seconds)}s", "--predicate", pred],
                       capture_output=True, text=True)
    lines = [l for l in r.stdout.splitlines()[1:] if "AgentWidget" in l or "RenderLab" in l or "chronod" in l]
    return lines[-40:]

# ------------------------------------------------------------------ T3 three independent agents

PANES = [{"agent": "portfolio", "technique": "bitmap", "x": 0.03, "y": 0.02, "w": 0.94, "h": 0.49, "bitmap": "agentA.png", "scene": "agentA-regions.json"},
         {"agent": "ops", "technique": "canvas", "x": 0.03, "y": 0.53, "w": 0.46, "h": 0.45, "scene": "agentB.json"},
         {"agent": "mail", "technique": "json", "x": 0.51, "y": 0.53, "w": 0.46, "h": 0.45, "surfaceFile": "agentC.surface.json"}]

def T3():
    assets(); gen = {}
    # Agent A: HTML/CSS on a "server" (headless Chrome) → PNG; its hit regions are agent-declared coordinates
    hp = put_local("agentA.html", sf.agent_a_table_html())
    gen["agentA_chrome"] = chrome_png(hp, os.path.join(WORK, "agentA.png"), 349, 180)
    rc.put("agentA.png", os.path.join(WORK, "agentA.png")); rc.put("agentA-regions.json", sf.agent_a_regions())
    # Agent B: display list drawn by Canvas inside the widget
    rc.put("agentB.json", sf.agent_b_chart())
    # Agent C: baseline JSON component tree (native button → AgentActionIntent)
    rc.put("agentC.surface.json", sf.agent_c_json())
    rows = []
    for run, dbg in [("t3-multi-debug", True), ("t3-multi", False)]:
        row = rc.run_case(run, "multi", timeout=12, panes=PANES, regions=True, debugRegions=dbg)
        rows.append({"render": row}); print(run, row["timeline"][:1])
    pts = plan_points(sf.agent_a_regions(), "systemLarge", pane=PANES[0]) + plan_points(sf.agent_b_chart(), "systemLarge", pane=PANES[1])
    summ, m = tap_points("t3 panes A+B (large)", pts)
    rows.append({"tap": summ, "taps": m}); print({k: summ[k] for k in ("taps", "correct", "wrong", "missed")})
    # Agent C's native JSON button: bottom of its pane (approximate; we log what intent fires)
    fx, fy, fw, fh = FRAME["systemLarge"]; p = PANES[2]
    since = rc.lab.now_ms()
    import base64
    cpt = [["mail:send", fx + (p["x"] + p["w"] / 2) * fw, fy + (p["y"] + p["h"]) * fh - 28, "c"]]
    uitest("testTapPoints", RL_POINTS=base64.b64encode(json.dumps(cpt).encode()).decode())
    time.sleep(2)
    ev = [(e["e"], e.get("d", "")) for e in rc.events(since) if e["e"] in ("action_received", "action_rejected", "rl_hit", "app_launch", "scene_active")]
    rows.append({"agentC_tap": cpt, "events": ev}); print("agent C:", ev)
    rc.lab.home(1); time.sleep(1.2); rc.shot(os.path.join(rc.RAW, "t3-after-taps.png"))
    rc.crop(os.path.join(rc.RAW, "t3-after-taps.png"), rc.LARGE, os.path.join(rc.IMG, "t3-after-taps-large.png"))
    rc.save_rows("T3", {"generation": gen, "panes": PANES, "rows": rows})

# ------------------------------------------------------------------ T4 stress

def T4ops():
    rows = []
    for n in [100, 1000, 5000, 20000, 50000]:
        for f in FAM:
            sc = sf.stress(n, f); rc.put(f"stress-{n}-{f}.json", sc)
        size = os.path.getsize(os.path.join(rc.gdir(), f"stress-{n}-systemLarge.json"))
        for tech in ["canvas", "views", "cg"]:
            run = f"t4-{tech}-{n}"
            t = time.time()
            row = rc.run_case(run, tech, timeout=25, scene=f"stress-{n}-{{f}}.json")
            row["scene_bytes"] = size; row["syslog"] = syslog(time.time() - t + 2)
            rows.append(row)
            print(run, row["visible_ms"], [(x.get("family"), x.get("prepMs"), x.get("memAfter"), x.get("renderMs")) for x in row["timeline"]],
                  [(d.get("ms"), d.get("mem")) for d in row["canvas_draws"]], len(row["syslog"]))
            rc.save_rows("T4ops", rows)
    for n in [80, 200, 1000, 3000]:
        rc.put(f"stress-json-{n}.json", sf.stress_json(n))
        for bypass in ([False, True] if n > 80 else [False]):
            run = f"t4-json-{n}{'-bypass' if bypass else ''}"
            t = time.time()
            row = rc.run_case(run, "json", timeout=20, surfaceFile=f"stress-json-{n}.json", bypassLimits=bypass)
            row["syslog"] = syslog(time.time() - t + 2); rows.append(row)
            print(run, row["visible_ms"], [(x.get("family"), x.get("prepMs"), x.get("memAfter")) for x in row["timeline"]], len(row["syslog"]))
            rc.save_rows("T4ops", rows)

def T4px():
    """Bitmap resolution ladder (server-rendered t1 scene), PNG."""
    assets(); rows = []
    put_local("t1-systemLarge.json", sf.t1("systemLarge")); put_local("t1-systemMedium.json", sf.t1("systemMedium"))
    for k in [1, 2, 3, 4, 6, 8, 12]:
        gen = {}
        for f in FAM:
            W, H = sf.SIZES[f]
            out = os.path.join(WORK, f"px{k}-{f}.png")
            gen[f] = server_cg(os.path.join(WORK, f"t1-{f}.json"), out, W * k, H * k)
            rc.put(f"px{k}-{f}.png", out)
        run = f"t4-px-{k}x"; t = time.time()
        row = rc.run_case(run, "bitmap", timeout=20, bitmap=f"px{k}-{{f}}.png")
        row["generation"] = gen; row["syslog"] = syslog(time.time() - t + 2); rows.append(row)
        print(run, row["visible_ms"], [(x.get("family"), x.get("px"), x.get("bytes"), x.get("decodeMs"), x.get("memAfter")) for x in row["timeline"]], row["syslog"][-3:])
        rc.save_rows("T4px", rows)

def T4fmt():
    assets(); rows = []
    for ext, q in [("png", 1), ("jpg", 0.9), ("jpg", 0.5), ("heic", 0.9), ("heic", 0.5)]:
        for f in FAM:
            W, H = sf.SIZES[f]
            out = os.path.join(WORK, f"fmt-{ext}{int(q*100)}-{f}.{ext}")
            g = server_cg(os.path.join(WORK, f"t1-{f}.json"), out, W * 3, H * 3, q)
            rc.put(os.path.basename(out), out)
        run = f"t4-fmt-{ext}{int(q*100)}"
        row = rc.run_case(run, "bitmap", timeout=15, bitmap=f"fmt-{ext}{int(q*100)}-{{f}}.{ext}"); rows.append(row)
        print(run, row["visible_ms"], [(x.get("family"), x.get("bytes"), x.get("decodeMs"), x.get("memAfter")) for x in row["timeline"]])
        rc.save_rows("T4fmt", rows)

def T4regions():
    rows = []
    import random
    for cols, rows_ in [(4, 4), (8, 8), (12, 12), (20, 20), (30, 30)]:
        for f in FAM:
            sc = namespaced(sf.t2(f, grid=(cols, rows_)), "L." if f == "systemLarge" else "M.")
            rc.put(f"grid-{cols}-{f}.json", sc); put_local(f"grid-{cols}-{f}.json", sc)
        run = f"t4-regions-{cols}x{rows_}"; t = time.time()
        row = rc.run_case(run, "canvas", timeout=15, scene=f"grid-{cols}-{{f}}.json", regions=True)
        row["syslog"] = syslog(time.time() - t + 2)
        L = json.load(open(os.path.join(WORK, f"grid-{cols}-systemLarge.json")))
        pts = plan_points(L, "systemLarge"); random.Random(cols).shuffle(pts)
        summ, m = tap_points(run, pts[:12], gap=1200)
        rows.append({"render": row, "regions": cols * rows_, "cell_pt": round(349 / cols, 1), "tap": summ, "taps": m})
        print(run, row["visible_ms"], [(x.get("family"), x.get("prepMs"), x.get("memAfter")) for x in row["timeline"]], {k: summ[k] for k in ("taps", "correct", "wrong", "missed")})
        rc.save_rows("T4regions", rows)

def MARGIN():
    """Full-bleed check: edge-marker scene, with contentMarginsDisabled vs. emulated default padding."""
    rows = []
    for f in FAM:
        W, H = sf.SIZES[f]
        ops = [sf.R(0, 0, W, H, "#FF00FF"), sf.R(0, 0, 6, H, "#00FF00"), sf.R(W - 6, 0, 6, H, "#00FF00"),
               sf.R(0, 0, W, 6, "#0000FF"), sf.R(0, H - 6, W, 6, "#0000FF"), sf.T(W / 2, H / 2 - 10, f"{W}x{H} pt full bleed", 14, "#FFFFFF", "bold", align="center")]
        rc.put(f"margin-{f}.json", {"w": W, "h": H, "ops": ops})
    for run, kw in [("margin-disabled", {}), ("margin-padding16", {"padding": 16})]:
        row = rc.run_case(run, "canvas", timeout=10, scene="margin-{f}.json", **kw); rows.append(row)
    from PIL import Image
    for run in ("margin-disabled", "margin-padding16"):
        im = Image.open(os.path.join(rc.RAW, f"{run}.png")).convert("RGB")
        # scan the middle row of the large widget from the left edge of its frame
        y = (rc.LARGE[1] + rc.LARGE[3]) // 2
        first = next((x for x in range(rc.LARGE[0] - 10, rc.LARGE[2]) if im.getpixel((x, y))[1] > 200 and im.getpixel((x, y))[0] < 80), None)
        rows.append({"run": run, "first_green_px_x": first, "widget_left_px": rc.LARGE[0]})
    rc.save_rows("MARGIN", rows); print(rows[-2:])


# ------------------------------------------------------------------ paging instead of scrolling

def PAGE():
    """A 30-row list shown as 3 pages of 10 rows; ‹ › regions page locally via RLPageIntent (no agent round trip)."""
    import base64
    rows_out = []
    for f in FAM:
        W, H = sf.SIZES[f]
        per = 10 if f == "systemLarge" else 4
        for p in range(3):
            ops = [sf.R(0, 0, W, H, "#FFFFFF"), sf.T(16, 12, f"Inbox · page {p + 1}/3", 15, "#111111", "heavy")]
            regions = []
            rh = (H - 80) / per
            for i in range(per):
                y = 40 + i * rh; n = p * per + i + 1
                ops += [sf.R(16, y, W - 32, rh - 4, "#F2F2F2", r=8), sf.T(26, y + rh / 2 - 9, f"Item {n:02d}  ·  agent message", 12, "#111111", "semibold")]
                regions.append({"id": f"{f[6]}.item-{n}", "x": 16, "y": y, "w": W - 32, "h": rh - 4})
            ops += [sf.R(16, H - 36, 80, 28, "#111111" if p > 0 else "#DDDDDD", r=14), sf.T(56, H - 30, "‹ Prev", 12, "#FFFFFF", "bold", align="center"),
                    sf.R(W - 96, H - 36, 80, 28, "#111111" if p < 2 else "#DDDDDD", r=14), sf.T(W - 56, H - 30, "Next ›", 12, "#FFFFFF", "bold", align="center")]
            if p > 0: regions.append({"id": f"{f[6]}.prev", "x": 16, "y": H - 36, "w": 80, "h": 28, "action": "page:-1"})
            if p < 2: regions.append({"id": f"{f[6]}.next", "x": W - 96, "y": H - 36, "w": 80, "h": 28, "action": "page:+1"})
            sc = {"w": W, "h": H, "ops": ops, "regions": regions}
            rc.put(f"page-{p}-{f}.json", sc); put_local(f"page-{p}-{f}.json", sc)
    rc.run_case("page-0", "canvas", timeout=10, scene="page-{p}-{f}.json", regions=True, page=0)
    fx, fy, fw, fh = FRAME["systemLarge"]; W, H = sf.SIZES["systemLarge"]
    nxt = ["L.next", fx + (W - 56) * fw / W, fy + (H - 22) * fh / H, "c"]
    prv = ["L.prev", fx + 56 * fw / W, fy + (H - 22) * fh / H, "c"]
    item = lambda n: [f"L.item-{n}", fx + 120, fy + (40 + ((n - 1) % 10) * (H - 80) / 10 + 10) * fh / H, "c"]
    plan = [item(3), nxt, item(14), nxt, item(27), prv, item(15)]
    since = rc.lab.now_ms()
    out, ok = uitest("testTapPoints", RL_POINTS=base64.b64encode(json.dumps(plan).encode()).decode(), RL_GAP_MS=1800)
    time.sleep(2)
    ev = [(e["t"] - since, e["e"], e.get("d", "")) for e in rc.events(since) if e["e"] in ("rl_hit", "rl_page")]
    rc.lab.home(1); time.sleep(1); rc.shot(os.path.join(rc.RAW, "page-final.png"))
    rc.crop(os.path.join(rc.RAW, "page-final.png"), rc.LARGE, os.path.join(rc.IMG, "page-final-large.png"))
    rows_out.append({"plan": plan, "events": ev, "uitest_ok": ok})
    for e in ev: print(e)
    rc.save_rows("PAGE", rows_out)

if __name__ == "__main__":
    for a in sys.argv[1:]: globals()[a]()
