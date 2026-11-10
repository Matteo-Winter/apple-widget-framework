"""RenderLab test surfaces. Every surface exists as an RLScene (display list) and,
where relevant, as equivalent HTML/CSS and as the closest JSON node tree of the
current baseline renderer, so all techniques get the same visual brief.

Widget sizes on the lab Simulator (iPhone 17 Pro, from rl_timeline logs):
  systemLarge 349x365 pt, systemMedium 349x164 pt  (@3x → 1047x1095 / 1047x492 px)
"""
import math, random

SIZES = {"systemLarge": (349, 365), "systemMedium": (349, 164)}

def R(x, y, w, h, fill=None, r=0, **kw): return {"k": "rect", "x": x, "y": y, "w": w, "h": h, "fill": fill, "r": r, **kw}
def O(x, y, w, h, fill=None, **kw): return {"k": "oval", "x": x, "y": y, "w": w, "h": h, "fill": fill, **kw}
def T(x, y, t, size, fill="#ffffff", weight="regular", **kw): return {"k": "text", "x": x, "y": y, "t": t, "size": size, "fill": fill, "weight": weight, **kw}
def LG(x, y, w, h, c, x2=None, y2=None, r=0): return {"k": "lgrad", "x": x, "y": y, "w": w, "h": h, "c": c, "x2": x2 if x2 is not None else x + w, "y2": y2 if y2 is not None else y + h, "r": r}
def RG(x, y, w, h, c, r=0): return {"k": "rgrad", "x": x, "y": y, "w": w, "h": h, "c": c, "r": r}
def P(pts, stroke=None, fill=None, lw=1, close=False, **kw): return {"k": "poly", "pts": [v for p in pts for v in p], "stroke": stroke, "fill": fill, "lw": lw, "close": close, **kw}
def A(cx, cy, r, a0, a1, stroke, lw): return {"k": "arc", "x": cx, "y": cy, "r": r, "a0": a0, "a1": a1, "stroke": stroke, "lw": lw}
def S(x, y, w, h, name, fill="#ffffff"): return {"k": "sym", "x": x, "y": y, "w": w, "h": h, "name": name, "fill": fill}
def I(x, y, w, h, name, r=0): return {"k": "img", "x": x, "y": y, "w": w, "h": h, "name": name, "r": r}

def spark(n=40, seed=3):
    rnd = random.Random(seed); v = 50; out = []
    for i in range(n):
        v = max(8, min(92, v + rnd.uniform(-9, 10))); out.append(v)
    return out

# ---------------------------------------------------------------- Test surface 1

def t1(family):
    W, H = SIZES[family]
    ops = [LG(0, 0, W, H, ["#0B1026", "#123A5A", "#0E6B6B"], x2=W, y2=H),
           RG(W - 170, -90, 260, 260, ["#FF7A1880", "#FF7A1800"]),
           RG(-60, H - 120, 220, 220, ["#7C4DFF66", "#7C4DFF00"]),
           O(W - 120, 18, 64, 64, "#FFFFFF14"), O(W - 92, 40, 40, 40, "#FFFFFF22")]
    # headline + microtype
    ops += [T(16, 14, "Q4 PIPELINE · LIVE", 9, "#9FE7FF", "bold"),
            T(16, 28, "€ 4.82 M", 34 if family == "systemLarge" else 28, "#FFFFFF", "heavy"),
            T(16, 70 if family == "systemLarge" else 62, "+18.4 % vs. Q3", 12, "#7CFFB2", "semibold"),
            T(W - 16, 16, "Didot headline", 13, "#FFE6B0", font="Didot-Bold", align="right")]
    if family == "systemLarge":
        # donut
        cx, cy, rr = 270, 128, 42
        start = 0
        for frac, col in [(0.42, "#FF7A18"), (0.27, "#7CFFB2"), (0.18, "#4DA3FF"), (0.13, "#C77DFF")]:
            ops.append(A(cx, cy, rr, start + 2, start + frac * 360 - 2, col, 13)); start += frac * 360
        ops += [T(cx, cy - 12, "42%", 18, "#FFFFFF", "bold", align="center"), T(cx, cy + 8, "EMEA", 8, "#FFFFFFAA", "semibold", align="center")]
        # sparkline with filled area
        v = spark(); x0, y0, w, h = 16, 100, 200, 70
        pts = [(x0 + i * w / (len(v) - 1), y0 + h - v[i] / 100 * h) for i in range(len(v))]
        ops += [P(pts + [(x0 + w, y0 + h), (x0, y0 + h)], fill="#4DA3FF40", close=True),
                P(pts, stroke="#9FE7FF", lw=2),
                O(pts[-1][0] - 4, pts[-1][1] - 4, 8, 8, "#FFFFFF")]
        # bars
        bx, by, bh = 16, 196, 70
        for i in range(12):
            hh = 14 + (math.sin(i * 0.9) + 1.2) * 24
            ops.append(LG(bx + i * 17, by + bh - hh, 11, hh, ["#FF7A18", "#FFD166"], x2=bx + i * 17, y2=by + bh, r=3))
        ops += [T(bx, by + bh + 4, "Jan", 7, "#FFFFFF99"), T(bx + 11 * 17, by + bh + 4, "Dez", 7, "#FFFFFF99")]
        # overlapping card with photo + symbols
        ops += [R(214, 186, 120, 104, "#FFFFFFE6", r=16),
                I(222, 194, 104, 52, "photo.png", r=10),
                S(226, 252, 18, 18, "bolt.fill", "#FF7A18"), T(248, 254, "Deal Zeta", 11, "#111111", "bold"),
                T(226, 274, "Close prob. 0.82", 9, "#444444"),
                R(300, 176, 40, 18, "#FF3B30", r=9), T(320, 178, "HOT", 9, "#FFFFFF", "heavy", align="center")]
        # chips row
        x = 16
        for label, col in [("Pipeline 128", "#FFFFFF22"), ("Won 31", "#7CFFB233"), ("Lost 9", "#FF3B3033"), ("SLA 97%", "#4DA3FF33")]:
            w = 9 + len(label) * 5.3
            ops += [R(x, 302, w, 20, col, r=10), T(x + w / 2, 306, label, 9, "#FFFFFF", "semibold", align="center")]
            x += w + 6
        # micro text grid
        for row in range(3):
            ops.append(T(16, 330 + row * 9, "  ".join(f"{(row*7+i)%10}.{i}k" for i in range(14)), 6, "#FFFFFF77", font="Menlo-Regular"))
    else:
        v = spark(30); x0, y0, w, h = 16, 84, 170, 60
        pts = [(x0 + i * w / (len(v) - 1), y0 + h - v[i] / 100 * h) for i in range(len(v))]
        ops += [P(pts + [(x0 + w, y0 + h), (x0, y0 + h)], fill="#4DA3FF40", close=True), P(pts, stroke="#9FE7FF", lw=2)]
        cx, cy, rr = 262, 92, 34; start = 0
        for frac, col in [(0.42, "#FF7A18"), (0.27, "#7CFFB2"), (0.18, "#4DA3FF"), (0.13, "#C77DFF")]:
            ops.append(A(cx, cy, rr, start + 2, start + frac * 360 - 2, col, 11)); start += frac * 360
        ops += [T(cx, cy - 9, "42%", 15, "#FFFFFF", "bold", align="center"),
                I(300, 120, 36, 32, "photo.png", r=8), S(196, 132, 14, 14, "bolt.fill", "#FF7A18"),
                T(214, 133, "Deal Zeta", 10, "#FFFFFF", "bold")]
    return {"w": W, "h": H, "ops": ops}

def t1_html(family):
    W, H = SIZES[family]
    large = family == "systemLarge"
    v = spark(40 if large else 30)
    sw, sh = (200, 70) if large else (170, 60)
    pts = " ".join(f"{i * sw / (len(v) - 1):.1f},{sh - x / 100 * sh:.1f}" for i, x in enumerate(v))
    bars = "".join(f'<i style="height:{14 + (math.sin(i * 0.9) + 1.2) * 24:.0f}px"></i>' for i in range(12)) if large else ""
    donut = f"""<div class="donut"><b>42%</b><small>EMEA</small></div>"""
    return f"""<!doctype html><html><head><meta name=viewport content="width={W}">
<style>
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:{W}px;height:{H}px;overflow:hidden;font-family:-apple-system,'Helvetica Neue',sans-serif;color:#fff}}
body{{background:radial-gradient(circle at 92% -5%,#FF7A1880,transparent 40%),radial-gradient(circle at 0% 100%,#7C4DFF66,transparent 35%),linear-gradient(135deg,#0B1026,#123A5A 55%,#0E6B6B);position:relative}}
.k{{position:absolute;left:16px;top:14px;font:700 9px -apple-system;letter-spacing:.08em;color:#9FE7FF}}
.v{{position:absolute;left:16px;top:26px;font:900 {34 if large else 28}px -apple-system;letter-spacing:-.02em}}
.d{{position:absolute;left:16px;top:{70 if large else 62}px;font:600 12px -apple-system;color:#7CFFB2}}
.didot{{position:absolute;right:16px;top:14px;font:700 13px Didot,serif;color:#FFE6B0;font-style:italic}}
.donut{{position:absolute;left:{228 if large else 228}px;top:{86 if large else 58}px;width:{84 if large else 68}px;height:{84 if large else 68}px;border-radius:50%;
 background:conic-gradient(#FF7A18 0 42%,#7CFFB2 0 69%,#4DA3FF 0 87%,#C77DFF 0);-webkit-mask:radial-gradient(circle,transparent 52%,#000 53%);}}
.dl{{position:absolute;left:{228 if large else 228}px;top:{86 if large else 58}px;width:{84 if large else 68}px;height:{84 if large else 68}px;display:flex;flex-direction:column;align-items:center;justify-content:center;font-weight:700}}
.dl small{{font-size:8px;opacity:.7}}
svg{{position:absolute;left:16px;top:{100 if large else 84}px;overflow:visible}}
.bars{{position:absolute;left:16px;top:196px;height:70px;display:flex;align-items:flex-end;gap:6px}}
.bars i{{display:block;width:11px;border-radius:3px;background:linear-gradient(#FFD166,#FF7A18)}}
.card{{position:absolute;left:214px;top:186px;width:120px;height:104px;border-radius:16px;background:rgba(255,255,255,.9);color:#111;padding:8px;box-shadow:0 8px 24px rgba(0,0,0,.35)}}
.card .ph{{height:52px;border-radius:10px;background:url(photo.png) center/cover}}
.card b{{display:block;font-size:11px;margin-top:6px}} .card span{{font-size:9px;color:#444}}
.hot{{position:absolute;left:300px;top:176px;background:#FF3B30;border-radius:9px;font:900 9px -apple-system;padding:3px 9px;transform:rotate(-8deg)}}
.chips{{position:absolute;left:16px;top:302px;display:flex;gap:6px}}
.chips span{{font:600 9px -apple-system;padding:4px 8px;border-radius:10px;background:rgba(255,255,255,.14);backdrop-filter:blur(6px)}}
.micro{{position:absolute;left:16px;top:330px;font:6px Menlo,monospace;opacity:.5;line-height:9px;white-space:pre}}
.vert{{position:absolute;right:4px;bottom:40px;writing-mode:vertical-rl;font:600 8px -apple-system;opacity:.6;letter-spacing:.2em}}
</style></head><body>
<div class=k>Q4 PIPELINE · LIVE</div><div class=v>€ 4.82 M</div><div class=d>+18.4 % vs. Q3</div><div class=didot>Didot headline</div>
{donut.replace('class="donut"><b>42%</b><small>EMEA</small>', 'class="donut">')}<div class=dl><b>42%</b><small>EMEA</small></div>
<svg width="{sw}" height="{sh}"><defs><linearGradient id=g x1=0 y1=0 x2=0 y2=1><stop offset=0 stop-color="#4DA3FF" stop-opacity=.5 /><stop offset=1 stop-color="#4DA3FF" stop-opacity=0 /></linearGradient></defs>
<polygon points="{pts} {sw},{sh} 0,{sh}" fill="url(#g)"/><polyline points="{pts}" fill=none stroke="#9FE7FF" stroke-width=2 stroke-linejoin=round /></svg>
{f'<div class=bars>{bars}</div><div class=card><div class=ph></div><b>⚡ Deal Zeta</b><span>Close prob. 0.82</span></div><div class=hot>HOT</div>' if large else ''}
{'<div class=chips><span>Pipeline 128</span><span>Won 31</span><span>Lost 9</span><span>SLA 97%</span></div><div class=micro>' + chr(10).join("  ".join(f"{(r*7+i)%10}.{i}k" for i in range(14)) for r in range(3)) + '</div><div class=vert>CSS WRITING-MODE</div>' if large else ''}
</body></html>"""

def t1_json():
    """Closest equivalent in the baseline component vocabulary (schema v1)."""
    def t(x, **k): return {"type": "text", "text": x, **k}
    return {"schema": 1, "id": "t1", "agent": "Sales Agent", "revision": 1, "root": {"type": "vstack", "spacing": 6, "children": [
        {"type": "hstack", "children": [{"type": "badge", "text": "Q4 PIPELINE · LIVE"}, {"type": "spacer"}, {"type": "symbol", "symbol": "bolt.fill", "color": "orange"}]},
        t("€ 4.82 M", style="largeTitle", weight="bold"),
        t("+18.4 % vs. Q3", style="callout", color="green"),
        {"type": "hstack", "spacing": 8, "children": [{"type": "gauge", "value": 0.42, "text": "EMEA"}, {"type": "progress", "value": 0.69, "color": "orange"}]},
        {"type": "divider"},
        {"type": "hstack", "spacing": 6, "children": [{"type": "badge", "text": "Pipeline 128"}, {"type": "badge", "text": "Won 31", "background": "green"}, {"type": "badge", "text": "Lost 9", "background": "red"}]},
        t("Deal Zeta · close prob. 0.82", style="caption", color="secondary"),
    ]}}

# ---------------------------------------------------------------- Test surface 2 (interactive)

def t2(family, grid=None):
    """Free-form selection UI: seat map + color swatches + segmented range + 2 actions.
    Every interactive element is a region; visuals never use native controls."""
    W, H = SIZES[family]
    ops = [R(0, 0, W, H, "#F4F1EA")]
    regions = []
    if family == "systemLarge":
        ops += [T(16, 12, "Pick a seat", 18, "#111111", "heavy"), T(16, 36, "Flight AG 812 · agent: Travel", 9, "#666666", "semibold")]
        # seat map 6 x 4, irregular shapes
        for row in range(4):
            for col in range(6):
                x = 16 + col * 34 + (12 if col >= 3 else 0); y = 58 + row * 34
                taken = (row * 6 + col) % 5 == 0
                ops.append(R(x, y, 28, 28, "#C9C2B4" if taken else "#1E6B52", r=7))
                ops.append(T(x + 14, y + 8, f"{row+1}{'ABCDEF'[col]}", 9, "#FFFFFF", "bold", align="center"))
                regions.append({"id": f"seat-{row+1}{'ABCDEF'[col]}", "x": x, "y": y, "w": 28, "h": 28, "label": f"Seat {row+1}{'ABCDEF'[col]}"})
        # circular color swatches
        for i, c in enumerate(["#FF7A18", "#4DA3FF", "#7CFFB2", "#C77DFF"]):
            x = 250 + (i % 2) * 44; y = 62 + (i // 2) * 44
            ops.append(O(x, y, 36, 36, c, stroke="#111111", lw=2))
            regions.append({"id": f"swatch-{i}", "x": x, "y": y, "w": 36, "h": 36, "label": f"Color {i}"})
        # diagonal / triangular hit target (bounding box region, visual is a triangle)
        ops.append(P([(250, 200), (330, 200), (290, 160)], fill="#111111", close=True))
        ops.append(T(290, 186, "UP", 9, "#FFFFFF", "heavy", align="center"))
        regions.append({"id": "tri-up", "x": 250, "y": 160, "w": 80, "h": 40, "label": "Upgrade"})
        # segmented range 5 segments
        for i in range(5):
            x = 16 + i * 64
            ops.append(R(x, 208, 60, 34, "#111111" if i == 2 else "#E4DED2", r=8))
            ops.append(T(x + 30, 218, ["06", "09", "12", "15", "18"][i] + ":00", 10, "#FFFFFF" if i == 2 else "#111111", "bold", align="center"))
            regions.append({"id": f"slot-{i}", "x": x, "y": 208, "w": 60, "h": 34, "label": f"Slot {i}"})
        # tiny targets row (stress precision): 8 x 22pt
        for i in range(8):
            x = 16 + i * 26
            ops.append(R(x, 256, 22, 22, "#FF7A18" if i % 2 else "#111111", r=4))
            regions.append({"id": f"tiny-{i}", "x": x, "y": 256, "w": 22, "h": 22, "label": f"Tiny {i}"})
        # primary + secondary actions
        ops += [R(16, 300, 214, 50, "#111111", r=14), T(123, 315, "Confirm 3C", 15, "#FFFFFF", "bold", align="center"),
                R(238, 300, 95, 50, "#E4DED2", r=14), T(285, 315, "Skip", 15, "#111111", "bold", align="center")]
        regions += [{"id": "confirm", "x": 16, "y": 300, "w": 214, "h": 50, "label": "Confirm"},
                    {"id": "skip", "x": 238, "y": 300, "w": 95, "h": 50, "label": "Skip"}]
    else:
        ops += [T(16, 12, "Pick a slot", 15, "#111111", "heavy")]
        for i in range(5):
            x = 16 + i * 64
            ops.append(R(x, 40, 60, 46, "#111111" if i == 2 else "#E4DED2", r=10))
            ops.append(T(x + 30, 55, ["06", "09", "12", "15", "18"][i], 14, "#FFFFFF" if i == 2 else "#111111", "bold", align="center"))
            regions.append({"id": f"slot-{i}", "x": x, "y": 40, "w": 60, "h": 46, "label": f"Slot {i}"})
        ops += [R(16, 100, 214, 48, "#111111", r=14), T(123, 114, "Confirm", 15, "#FFFFFF", "bold", align="center"),
                R(238, 100, 95, 48, "#E4DED2", r=14), T(285, 114, "Skip", 15, "#111111", "bold", align="center")]
        regions += [{"id": "confirm", "x": 16, "y": 100, "w": 214, "h": 48}, {"id": "skip", "x": 238, "y": 100, "w": 95, "h": 48}]
    if grid:
        cols, rows = grid; regions = []
        for r_ in range(rows):
            for c in range(cols):
                regions.append({"id": f"g{c}_{r_}", "x": c * W / cols, "y": r_ * H / rows, "w": W / cols, "h": H / rows})
                ops.append(R(c * W / cols + 1, r_ * H / rows + 1, W / cols - 2, H / rows - 2, "#1E6B52" if (c + r_) % 2 else "#2E8B6A"))
    return {"w": W, "h": H, "ops": ops, "regions": regions}

def t2_html(family):
    """HTML version of surface 2 (visual only — the hit regions come from the scene)."""
    sc = t2(family)
    # Render the same scene geometry in HTML/CSS to prove "HTML picture + native hit layer" works.
    els = []
    for op in sc["ops"]:
        if op["k"] == "rect":
            els.append(f'<div style="position:absolute;left:{op["x"]}px;top:{op["y"]}px;width:{op["w"]}px;height:{op["h"]}px;border-radius:{op.get("r",0)}px;background:{op["fill"]}"></div>')
        elif op["k"] == "oval":
            els.append(f'<div style="position:absolute;left:{op["x"]}px;top:{op["y"]}px;width:{op["w"]}px;height:{op["h"]}px;border-radius:50%;background:{op["fill"]};border:2px solid #111;box-sizing:border-box"></div>')
        elif op["k"] == "poly":
            p = op["pts"]; pts = " ".join(f"{p[i]},{p[i+1]}" for i in range(0, len(p), 2))
            els.append(f'<svg style="position:absolute;left:0;top:0" width="{sc["w"]}" height="{sc["h"]}"><polygon points="{pts}" fill="{op["fill"]}"/></svg>')
        elif op["k"] == "text":
            tx = {"center": "translateX(-50%)", "right": "translateX(-100%)"}.get(op.get("align"), "none")
            w = {"heavy": 900, "bold": 700, "semibold": 600}.get(op.get("weight"), 400)
            els.append(f'<div style="position:absolute;left:{op["x"]}px;top:{op["y"]}px;transform:{tx};font:{w} {op["size"]}px -apple-system;color:{op["fill"]};white-space:nowrap">{op["t"]}</div>')
    return f'<!doctype html><html><head><style>*{{margin:0}}body{{width:{sc["w"]}px;height:{sc["h"]}px;position:relative;overflow:hidden}}</style></head><body>{"".join(els)}</body></html>'

# ---------------------------------------------------------------- Test surface 3 (three agents)

def agent_b_chart(w=166, h=170):
    """Agent B (Canvas display list): live latency chart + 2 actions."""
    v = spark(28, seed=11)
    pts = [(10 + i * (w - 20) / (len(v) - 1), 40 + 70 - x / 100 * 70) for i, x in enumerate(v)]
    ops = [R(0, 0, w, h, "#10141C"), T(10, 8, "OPS AGENT", 8, "#7CFFB2", "bold"), T(10, 20, "p95 212 ms", 13, "#FFFFFF", "heavy"),
           P(pts, stroke="#7CFFB2", lw=1.5)]
    for i in range(0, len(v), 3):
        ops.append(O(pts[i][0] - 2, pts[i][1] - 2, 4, 4, "#FFFFFF"))
    ops += [R(10, 122, 70, 36, "#7CFFB2", r=10), T(45, 133, "Scale up", 10, "#10141C", "bold", align="center"),
            R(86, 122, 70, 36, "#FFFFFF22", r=10), T(121, 133, "Mute", 10, "#FFFFFF", "bold", align="center")]
    return {"w": w, "h": h, "ops": ops, "regions": [{"id": "scale", "x": 10, "y": 122, "w": 70, "h": 36, "label": "Ops: scale up"},
                                                    {"id": "mute", "x": 86, "y": 122, "w": 70, "h": 36, "label": "Ops: mute"}]}

def agent_a_table_html(w=349, h=180):
    """Agent A (HTML/CSS table → server bitmap)."""
    rows = [("AAPL", "231.40", "+1.2%", "#1E9E5A"), ("MSFT", "498.10", "−0.4%", "#D63B3B"), ("NVDA", "176.02", "+3.8%", "#1E9E5A"),
            ("TSLA", "402.77", "−2.1%", "#D63B3B"), ("AMZN", "221.35", "+0.6%", "#1E9E5A")]
    trs = "".join(f"<tr><td><b>{a}</b></td><td>{b}</td><td style='color:{c}'>{d}</td><td><button>{'Sell' if '−' in d else 'Buy'}</button></td></tr>" for a, b, d, c in rows)
    return f"""<!doctype html><html><head><style>*{{margin:0;box-sizing:border-box}}
body{{width:{w}px;height:{h}px;overflow:hidden;font-family:Georgia,serif;background:#FFFDF6;color:#1b1b1b;padding:8px 12px}}
h1{{font:italic 700 13px Georgia;letter-spacing:.02em;border-bottom:2px solid #1b1b1b;padding-bottom:2px}}
table{{width:100%;border-collapse:collapse;font-size:11px;margin-top:3px}} td{{padding:3px 2px;border-bottom:1px dotted #bbb;height:27px}}
td:nth-child(2),td:nth-child(3){{text-align:right;font-family:Menlo,monospace}}
button{{font:700 9px -apple-system;border:1.5px solid #1b1b1b;background:none;border-radius:4px;padding:2px 8px;float:right}}
</style></head><body><h1>Portfolio Agent — watchlist</h1><table>{trs}</table></body></html>"""

def agent_a_regions(w=349, h=180):
    # buttons sit right-aligned in each row (row pitch ≈ 28pt starting at y≈27) — agent-defined coordinates
    return {"w": w, "h": h, "ops": [], "regions": [{"id": f"trade-{i}", "x": w - 62, "y": 27 + i * 28.6, "w": 50, "h": 28, "label": f"Portfolio: trade row {i}"} for i in range(5)]}

def agent_c_json():
    return {"schema": 1, "id": "c", "agent": "Mail Agent", "revision": 1, "root": {"type": "vstack", "spacing": 4, "children": [
        {"type": "badge", "text": "MAIL AGENT"}, {"type": "text", "text": "3 drafts ready", "style": "headline"},
        {"type": "text", "text": "Reply to Anna about the offsite?", "style": "caption", "color": "secondary", "lineLimit": 2},
        {"type": "button", "text": "Send", "action": "send", "prominent": True}]}}

# ---------------------------------------------------------------- Test surface 4 (stress)

def stress(n, family="systemLarge", seed=1):
    W, H = SIZES[family]; rnd = random.Random(seed)
    ops = [R(0, 0, W, H, "#0B0B0F")]
    kinds = ["rect", "oval", "text", "poly", "lgrad"]
    for i in range(n):
        k = kinds[i % len(kinds)]
        x, y = rnd.uniform(0, W - 20), rnd.uniform(0, H - 12)
        col = "#%02X%02X%02X%02X" % (rnd.randrange(60, 255), rnd.randrange(60, 255), rnd.randrange(60, 255), rnd.randrange(80, 255))
        if k == "rect": ops.append(R(x, y, rnd.uniform(2, 18), rnd.uniform(2, 18), col, r=2))
        elif k == "oval": ops.append(O(x, y, rnd.uniform(2, 14), rnd.uniform(2, 14), col))
        elif k == "text": ops.append(T(x, y, f"{i}", rnd.choice([5, 6, 7, 9]), col))
        elif k == "poly": ops.append(P([(x, y), (x + rnd.uniform(-15, 15), y + rnd.uniform(-15, 15)), (x + rnd.uniform(-15, 15), y + rnd.uniform(-15, 15))], stroke=col, lw=0.8))
        else: ops.append(LG(x, y, rnd.uniform(4, 20), rnd.uniform(4, 12), [col, "#00000000"]))
    ops.append(R(W - 92, H - 26, 86, 20, "#FFFFFF", r=6)); ops.append(T(W - 49, H - 23, f"n={n}", 11, "#000000", "bold", align="center"))
    return {"w": W, "h": H, "ops": ops}

def stress_json(n):
    kids = [{"type": "text", "text": f"node {i}", "style": "caption"} for i in range(max(0, n - 2))]
    return {"schema": 1, "id": f"sj{n}", "agent": "Stress", "revision": 1, "root": {"type": "vstack", "spacing": 0, "children": [
        {"type": "text", "text": f"n={n}", "style": "headline"}, {"type": "hstack", "children": kids}]}}

def photo_png(path, w=600, h=300):
    from PIL import Image, ImageDraw, ImageFilter
    im = Image.new("RGB", (w, h)); d = ImageDraw.Draw(im)
    for y in range(h):
        d.line([(0, y), (w, y)], fill=(int(30 + 200 * y / h), int(90 + 80 * (1 - y / h)), int(160 + 60 * y / h)))
    rnd = random.Random(5)
    for _ in range(40):
        x, y, r = rnd.randrange(w), rnd.randrange(h), rnd.randrange(10, 60)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(rnd.randrange(150, 255), rnd.randrange(80, 200), rnd.randrange(40, 120)))
    im = im.filter(ImageFilter.GaussianBlur(4))
    d = ImageDraw.Draw(im); d.polygon([(0, h), (w * .3, h * .45), (w * .55, h), ], fill=(20, 40, 30)); d.polygon([(w * .35, h), (w * .7, h * .35), (w, h)], fill=(30, 55, 40))
    im.save(path)
