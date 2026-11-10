#!/usr/bin/env python3
"""System surfaces (Simulator): python3 exp_system.py ISLAND LOCK NOTIF CONTROL
Mirrors the procedures used for docs/research/screen-surfaces/REPORT.md (E3, N1/N2, CC)."""
import base64, json, os, sys, time
import slcore as s
from PIL import Image

def _small(p, name): Image.open(p).resize((402, 874)).save(os.path.join(s.IMG, name + ".png"))

def ISLAND():
    """Start 3 activities with a 160/400 pt height request; host screenshots of compact + expanded island."""
    for h in (160, 400):
        s.slcmd({"op": "la-end"}, wait=2)
        s.slcmd({"op": "la-start", "names": ["Agent 1", "Agent 2", "Agent 3"], "h": h}, wait=4)
        s.to_home()
        out, shots = s.uitest_hold("SurfaceTests/testIsland", f"E3-h{h}", SL_HOLD=4)
        for k, p in shots.items(): _small(p, f"E3-h{h}-{k}")

def LOCK():
    """Lock Screen card with one activity, then tap its buttons while LOCKED (no Home press)."""
    s.slcmd({"op": "la-end"}, wait=2)
    s.slcmd({"op": "la-start", "names": ["Agent 1"], "h": 160}, wait=4)
    p = s.lock_screen("E3-lock-one"); _small(p, "E3-lock-one")
    pts = [["Agent 1:A", 14 + 0.27 * 374, 477 + 0.47 * 160], ["Agent 1:B", 14 + 0.73 * 374, 477 + 0.47 * 160]]
    since = s.lab.now_ms()
    s.uitest("SurfaceTests/testTapPoints", SL_POINTS=base64.b64encode(json.dumps(pts).encode()).decode(), SL_NOHOME=1, SL_GAP_MS=2500)
    time.sleep(2)
    print([(e["e"], e.get("d", "")) for e in s.lab.events(since) if e["e"] == "sl_la_tap"])

def NOTIF():
    """Rich notification: schedule 30 s ahead, expand by long-press, tap button, type text, scroll."""
    since = s.lab.now_ms()
    s.slcmd({"op": "notify", "delay": 30}, wait=2); s.to_home()
    out, shots = s.uitest_hold("SurfaceTests/testNotificationExpand", "N2", SL_HOLD=3, SL_WAIT=45,
                               SL_BUTTON_X=104, SL_BUTTON_Y=145, SL_FIELD_X=200, SL_FIELD_Y=185, SL_SCROLL_X=200, SL_SCROLL_Y=520)
    for k, p in shots.items(): _small(p, f"N2-{k}")
    print([(e["e"], e.get("d", "")) for e in s.lab.events(since) if e["e"].startswith("sl_notif") and e["e"] != "sl_notif_layout"])

def CONTROL():
    """Add 'Agent Surface Control' via Control Center edit mode (coordinates for iPhone 17 Pro), then tap it."""
    s.to_home()
    s.uitest_hold("SurfaceTests/testCoordSteps", "CCadd", SL_OPEN_CC=1, SL_STEPS_XY="33,28;202,800;57,392", SL_HOLD=1)
    s.to_home(); since = s.lab.now_ms()
    s.uitest_hold("SurfaceTests/testCoordSteps", "CCtap", SL_OPEN_CC=1, SL_STEPS_XY="72,189", SL_HOLD=1)
    time.sleep(2)
    print([(e["e"], e.get("d", "")) for e in s.lab.events(since) if e["e"] == "sl_control"])

if __name__ == "__main__":
    for a in sys.argv[1:]: globals()[a]()
