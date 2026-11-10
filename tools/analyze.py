#!/usr/bin/env python3
"""Correlates UI-test AWL| lines with App Group events. Usage: analyze.py <uitest.log> <events.jsonl>"""
import json, sys, statistics as st

def load(log, ev):
    marks = []
    for l in open(log):
        if "AWL|" in l:
            _, t, k, j = l.strip().split("|", 3)[0:4] if l.count("|") >= 3 else (None,)*4
            try: marks.append((int(t), k, json.loads(j)))
            except Exception: pass
    events = []
    for l in open(ev):
        try: events.append(json.loads(l))
        except Exception: pass
    return marks, events

def after(events, t, name, limit=30000):
    for e in events:
        if e["e"] == name and t <= e["t"] <= t + limit:
            return e
    return None

def pct(xs):
    xs = sorted(xs)
    if not xs: return {}
    return {"n": len(xs), "min": round(xs[0], 3), "median": round(st.median(xs), 3),
            "p90": round(xs[int(0.9 * (len(xs) - 1))], 3), "max": round(xs[-1], 3)}

if __name__ == "__main__":
    marks, events = load(sys.argv[1], sys.argv[2])
    out = {"E01": [], "E03": []}
    for t, k, d in marks:
        if k == "E03_tap":
            t0 = int(d["tapStart"] * 1000)
            a = after(events, t0, "action_received"); g = after(events, t0, "get_timeline")
            done = after(events, t0, "action_done")
            out["E03"].append({"tap_to_intent_s": a and (a["t"] - t0) / 1000, "tap_to_getTimeline_s": g and (g["t"] - t0) / 1000,
                               "intent_runtime_s": a and done and (done["t"] - a["t"]) / 1000,
                               "tap_to_visible_s": d["visibleSecondsAfterTapStart"], "appState": d["appState"]})
        if k == "E01_visible":
            out["E01"].append(d)
    summary = {
        "E01_publish_to_visible_s": pct([d["secondsAfterPublish"] for d in out["E01"] if d["secondsAfterPublish"] > 0]),
        "E03_tap_to_intent_s": pct([x["tap_to_intent_s"] for x in out["E03"] if x["tap_to_intent_s"]]),
        "E03_tap_to_getTimeline_s": pct([x["tap_to_getTimeline_s"] for x in out["E03"] if x["tap_to_getTimeline_s"]]),
        "E03_intent_runtime_s": pct([x["intent_runtime_s"] for x in out["E03"] if x["intent_runtime_s"]]),
        "E03_tap_to_visible_s": pct([x["tap_to_visible_s"] for x in out["E03"] if x["tap_to_visible_s"] > 0]),
    }
    print(json.dumps({"rows": out, "summary": summary}, indent=1))
