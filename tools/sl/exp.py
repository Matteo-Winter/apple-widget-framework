#!/usr/bin/env python3
"""SurfaceLab experiments (Simulator). python3 exp.py E1 E2 E5 ..."""
import json, os, sys, time, base64
import slcore as s
from PIL import Image

TILES = ["A", "B", "C", "D"]
FAMS = {"A": "systemSmall", "B": "systemSmall", "C": "systemMedium", "D": "systemMedium"}

def page1_shot(name):
    """Page 1 screenshot via XCUITest (runner writes PNG to the host)."""
    out, ok = s.uitest("SurfaceTests/testPages", SL_PAGES=2, SL_SHOT_DIR=s.RAW)
    src = os.path.join(s.RAW, "page-1.png"); dst = os.path.join(s.RAW, f"{name}.png")
    os.replace(src, dst)
    widgets = [o for _, k, o in out if k == "page" and o["index"] == 1]
    return dst, (widgets[0]["widgets"] if widgets else [])

def reload_and_wait(wait=3.0):
    s.reload_bg(); time.sleep(wait)

def mask_boxes(path, rgb, tol=40):
    im = Image.open(path).convert("RGB"); W, H = im.size; px = im.load()
    def hit(p): return all(abs(p[i] - rgb[i]) <= tol for i in range(3))
    count = 0; rows = {}
    for y in range(0, H):
        xs = [x for x in range(0, W, 1) if hit(px[x, y])] if y % 1 == 0 else []
        count += len(xs)
        if xs: rows[y] = (min(xs), max(xs))
    return count, W * H, rows

def E1():
    """Coverage: every tile full-bleed magenta, page 1 = 2 small + 2 medium."""
    s.spec("E1", tiles={t: {"bg": "#FF00FF"} for t in TILES})
    reload_and_wait()
    path, widgets = page1_shot("E1-coverage")
    n, total, rows = mask_boxes(path, (255, 0, 255))
    # bounding boxes of magenta bands (contiguous y ranges)
    ys = sorted(rows); bands = []
    for y in ys:
        if bands and y == bands[-1][1] + 1: bands[-1][1] = y
        else: bands.append([y, y])
    res = {"screen_px": [Image.open(path).size[0], Image.open(path).size[1]], "magenta_px": n, "total_px": total,
           "coverage_pct": round(100 * n / total, 2), "bands_px_y": bands, "widgets_ax": widgets}
    s.save("E1-coverage", res); print(json.dumps({k: v for k, v in res.items() if k != "widgets_ax"}))
    Image.open(path).resize((402, 874)).save(os.path.join(s.IMG, "E1-coverage.png"))


def tile_boxes(path):
    """Pixel boxes of the magenta tiles in an E1 screenshot, ordered A, B, C, D."""
    im = Image.open(path).convert("RGB"); W, H = im.size; px = im.load()
    mag = lambda p: p[0] > 215 and p[1] < 40 and p[2] > 215
    n, t, rows = mask_boxes(path, (255, 0, 255))
    ys = sorted(rows); bands = []
    for y in ys:
        if bands and y == bands[-1][1] + 1: bands[-1][1] = y
        else: bands.append([y, y])
    boxes = []
    for y0, y1 in bands:
        ym = (y0 + y1) // 2; segs = []; x = 0
        while x < W:
            if mag(px[x, ym]):
                x0 = x
                while x < W and mag(px[x, ym]): x += 1
                segs.append([x0, ym, x - 1])
            x += 1
        for x0, _, x1 in segs: boxes.append((x0, y0, x1 + 1, y1 + 1))
    return boxes  # px, exclusive max

def E2():
    import math
    from PIL import ImageDraw, ImageFont, ImageFilter
    boxes = tile_boxes(os.path.join(s.RAW, "E1-coverage.png"))
    assert len(boxes) == 4, boxes
    W, H = 1206, 2622
    g = Image.new("RGB", (W, H)); d = ImageDraw.Draw(g)
    for y in range(H):   # one global gradient
        f = y / H; d.line([(0, y), (W, y)], fill=(int(12 + 30 * f), int(18 + 90 * f), int(60 + 120 * (1 - f))))
    for cx, cy, r, col in [(600, 760, 330, (255, 122, 24)), (180, 1500, 260, (124, 77, 255)), (1000, 1900, 300, (77, 163, 255))]:
        blob = Image.new("RGBA", (W, H), (0, 0, 0, 0)); bd = ImageDraw.Draw(blob)
        bd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col + (150,)); blob = blob.filter(ImageFilter.GaussianBlur(60))
        g.paste(blob, (0, 0), blob)
    try: font = ImageFont.truetype("/System/Library/Fonts/SFNSRounded.ttf", 150)
    except Exception: font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 150)
    d = ImageDraw.Draw(g)
    d.text((W // 2, 420), "AGENT·HUB", font=font, fill=(255, 255, 255), anchor="mm")   # spans tile A + B and the gap
    # one continuous line chart across tiles C and D (and the gap between them)
    pts = [(80 + i * 1046 / 59, 1150 + 650 * (0.5 + 0.45 * math.sin(i / 6.0) * math.cos(i / 17.0))) for i in range(60)]
    d.line(pts, fill=(124, 255, 178), width=10, joint="curve")
    for p in pts[::6]: d.ellipse([p[0] - 14, p[1] - 14, p[0] + 14, p[1] + 14], fill=(255, 255, 255))
    # bridge button across A|B gap and 6 buttons inside C/D
    bx0, by0, bx1, by1 = 230, 600, 976, 720
    d.rounded_rectangle([bx0, by0, bx1, by1], 60, fill=(255, 255, 255)); d.text(((bx0 + bx1) // 2, (by0 + by1) // 2), "Bridge button", font=ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 48), fill=(20, 20, 20), anchor="mm")
    btns = {"C": [], "D": []}
    for tile in ("C", "D"):
        x0, y0, x1, y1 = boxes[TILES.index(tile)]
        for i in range(3):
            bx = x0 + 40 + i * (x1 - x0 - 80) / 3; by = y1 - 150
            rect = [bx + 10, by, bx + (x1 - x0 - 80) / 3 - 10, by + 110]
            d.rounded_rectangle(rect, 30, fill=(0, 0, 0)); d.text(((rect[0] + rect[2]) / 2, by + 55), f"{tile}{i + 1}", font=ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 46), fill=(255, 255, 255), anchor="mm")
            btns[tile].append(rect)
    g.save(os.path.join(s.RAW, "E2-global.png"))
    tiles = {}; plan = []
    for t, (x0, y0, x1, y1) in zip(TILES, boxes):
        crop = g.crop((x0, y0, x1, y1)); fn = f"e2-{t}.png"; crop.save(os.path.join(s.RAW, fn)); s.put(fn, os.path.join(s.RAW, fn))
        wpt, hpt = (x1 - x0) / 3, (y1 - y0) / 3
        regs = []
        def add(rid, r):   # global px rect → tile-local pt, clipped to the tile
            ix0, iy0, ix1, iy1 = max(r[0], x0), max(r[1], y0), min(r[2], x1), min(r[3], y1)
            if ix1 <= ix0 or iy1 <= iy0: return
            regs.append({"id": rid, "x": (ix0 - x0) / 3, "y": (iy0 - y0) / 3, "w": (ix1 - ix0) / 3, "h": (iy1 - iy0) / 3, "label": rid})
            plan.append([f"{t}:{rid}", (ix0 + ix1) / 6, (iy0 + iy1) / 6])
        add("bridge", (bx0, by0, bx1, by1))
        for i, r in enumerate(btns.get(t, [])): add(f"btn{i + 1}", r)
        s.put(f"e2-{t}.json", {"w": wpt, "h": hpt, "ops": [], "regions": regs})
        tiles[t] = {"image": fn, "scene": f"e2-{t}.json"}
    s.spec("E2", tiles=tiles, regions=True)
    reload_and_wait(4)
    path, widgets = page1_shot("E2-composite")
    Image.open(path).resize((402, 874)).save(os.path.join(s.IMG, "E2-composite.png"))
    # taps: every region + one tap exactly in the A|B gap (bridge button drawn, but no widget there)
    gap_x = (boxes[0][2] + boxes[1][0]) / 6
    plan.append(["(gap)", gap_x, (by0 + by1) / 6])
    since = s.lab.now_ms()
    out, ok = s.uitest("SurfaceTests/testTapPoints", SL_POINTS=base64.b64encode(json.dumps(plan).encode()).decode(), SL_GAP_MS=2500, SL_PAGE=1)
    time.sleep(3)
    taps = [o for _, k, o in out if k == "tap"]
    ev = s.lab.events(since)
    hits = [e for e in ev if e["e"] == "sl_hit"]
    rows = []
    for i, tp in enumerate(taps):
        t0 = tp["t"]; t1 = taps[i + 1]["t"] if i + 1 < len(taps) else t0 + 4000
        got = [e["d"].split("region=")[1] for e in hits if t0 - 200 <= e["t"] < t1]
        sel = got[0] if got else None
        tl = [e for e in ev if e["e"] == "sl_timeline" and t0 <= e["t"] < t1 and sel and f"selected={sel}" in e["d"] and "preview=false" in e["d"]]
        tiles_seen = sorted({e["d"].split("tile=")[1].split()[0] + "/" + e["d"].split("family=")[1].split()[0] for e in tl})
        rows.append({"want": tp["want"], "got": got, "hit_ms": (next(e["t"] for e in hits if t0 - 200 <= e["t"] < t1) - t0) if got else None,
                     "tiles_rerendered": tiles_seen, "first_rerender_ms": (min(e["t"] for e in tl) - t0) if tl else None,
                     "last_rerender_ms": (max(e["t"] for e in tl) - t0) if tl else None})
    other = [(e["e"], e.get("d", "")[:80]) for e in ev if e["e"] in ("app_launch", "scene_active")]
    res = {"boxes_px": boxes, "plan": plan, "taps": rows, "app_events": other, "uitest_ok": ok}
    s.save("E2-multi-widget", res)
    for r in rows: print(r)
    print("app events:", other)


def E5():
    """Visual-expansion tricks: (1) clear background [separate run], (2) wallpaper crop + fake icons (D),
    (3) wallpaper-colour interpolation from the surrounding pixels (C), (4) cross-tile composition (A/B from E2)."""
    from PIL import ImageDraw, ImageFont
    boxes = tile_boxes(os.path.join(s.RAW, "E1-coverage.png"))
    e1 = Image.open(os.path.join(s.RAW, "E1-coverage.png")).convert("RGB")
    page2 = Image.open(os.path.join(s.RAW, "page-2.png")).convert("RGB")   # icons page, rows 5–6 empty → clean wallpaper
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 34)
    tiles = {}
    # (2) D: wallpaper crop from the same screen position on another page + 8 fake "icons" on the real icon grid
    x0, y0, x1, y1 = boxes[3]
    d_img = page2.crop((x0, y0, x1, y1)); dd = ImageDraw.Draw(d_img)
    cols_pt = [28.33, 120.67, 213.67, 306.0]; rows_pt = [489.33, 589.67]; size = 68
    regs = []; plan = []
    colors = [(255, 122, 24), (77, 163, 255), (124, 255, 178), (199, 125, 255), (255, 59, 48), (255, 209, 102), (52, 199, 89), (90, 200, 250)]
    k = 0
    for ry in rows_pt:
        for cx in cols_pt:
            px0, py0 = cx * 3 - x0, ry * 3 - y0
            dd.rounded_rectangle([px0, py0, px0 + size * 3, py0 + size * 3], 46, fill=colors[k])
            dd.text((px0 + size * 1.5, py0 + size * 1.5), f"A{k + 1}", font=ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 70), fill=(255, 255, 255), anchor="mm")
            dd.text((px0 + size * 1.5, py0 + size * 3 + 30), f"Agent {k + 1}", font=font, fill=(255, 255, 255), anchor="mm")
            regs.append({"id": f"icon{k + 1}", "x": px0 / 3, "y": py0 / 3, "w": size, "h": size})
            plan.append([f"D:icon{k + 1}", cx + size / 2, ry + size / 2])
            k += 1
    d_img.save(os.path.join(s.RAW, "e5-D.png")); s.put("e5-D.png", os.path.join(s.RAW, "e5-D.png"))
    s.put("e5-D.json", {"w": (x1 - x0) / 3, "h": (y1 - y0) / 3, "ops": [], "regions": regs})
    tiles["D"] = {"image": "e5-D.png", "scene": "e5-D.json"}
    # (3) C: interpolate wallpaper colours between the pixels just left and right of the tile, per row
    x0, y0, x1, y1 = boxes[2]
    c_img = Image.new("RGB", (x1 - x0, y1 - y0)); cp = c_img.load(); ep = e1.load()
    for y in range(y1 - y0):
        l = ep[max(0, x0 - 12), y0 + y]; r = ep[min(e1.size[0] - 1, x1 + 12), y0 + y]
        for x in range(x1 - x0):
            f = x / (x1 - x0 - 1); cp[x, y] = tuple(int(l[i] * (1 - f) + r[i] * f) for i in range(3))
    ImageDraw.Draw(c_img).text(((x1 - x0) / 2, (y1 - y0) / 2), "interpolated wallpaper", font=font, fill=(255, 255, 255), anchor="mm")
    c_img.save(os.path.join(s.RAW, "e5-C.png")); s.put("e5-C.png", os.path.join(s.RAW, "e5-C.png"))
    tiles["C"] = {"image": "e5-C.png"}
    # (4) A/B keep the E2 cross-tile composition
    for t in ("A", "B"): tiles[t] = {"image": f"e2-{t}.png", "scene": f"e2-{t}.json"}
    s.spec("E5", tiles=tiles, regions=True)
    reload_and_wait(4)
    path, _ = page1_shot("E5-tricks")
    Image.open(path).resize((402, 874)).save(os.path.join(s.IMG, "E5-tricks.png"))
    since = s.lab.now_ms()
    out, ok = s.uitest("SurfaceTests/testTapPoints", SL_POINTS=base64.b64encode(json.dumps(plan).encode()).decode(), SL_GAP_MS=1500, SL_PAGE=1)
    time.sleep(2)
    hits = [e["d"].split("region=")[1] for e in s.lab.events(since) if e["e"] == "sl_hit"]
    res = {"plan": plan, "hits": hits, "correct": sum(1 for p, h in zip(plan, hits) if p[0] == h), "uitest_ok": ok}
    s.save("E5-tricks", res); print(res["correct"], "/", len(plan), hits)

if __name__ == "__main__":
    for a in sys.argv[1:]: globals()[a]()
