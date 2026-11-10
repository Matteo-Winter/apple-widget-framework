"""Extracts WidgetKit archive requests (extension side) from the Simulator unified log:
'Request began for RenderLab:<family>' → 'Request ended for RenderLab:<family> - success|…'.
This is the handover stage: getTimeline + SwiftUI view archiving, as seen by WidgetKit."""
import re, subprocess, json, sys
from datetime import datetime

def archive_requests(last="60m"):
    pred = 'process == "AgentWidgetExtension" AND (eventMessage CONTAINS "Request began for RenderLab" OR eventMessage CONTAINS "Request ended for RenderLab")'
    r = subprocess.run(["xcrun", "simctl", "spawn", "booted", "log", "show", "--style", "compact", "--last", last, "--predicate", pred], capture_output=True, text=True)
    open_ = {}; out = []
    for line in r.stdout.splitlines():
        m = re.match(r"(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+).*Request (began|ended) for (RenderLab\w*):(\w+):\(noIntent\)(?: - (\w+))?", line)
        if not m: continue
        ts = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S.%f").timestamp() * 1000
        key = (m.group(3), m.group(4))
        if m.group(2) == "began": open_[key] = ts
        elif key in open_:
            out.append({"kind": key[0], "family": key[1], "began": int(open_.pop(key)), "ms": int(ts - 0) - int(0) and int(ts - open_.get(key, ts)) , "end": int(ts), "result": m.group(5)})
    for o in out: o["ms"] = o["end"] - o["began"]
    return out

def assign(rows, reqs):
    for i, r in enumerate(rows):
        t0 = r["trigger_ms"]; t1 = rows[i + 1]["trigger_ms"] if i + 1 < len(rows) else t0 + 60000
        r["archive"] = [q for q in reqs if t0 <= q["began"] < t1 and q["kind"] == "RenderLab"]
    return rows

if __name__ == "__main__":
    reqs = archive_requests(sys.argv[2] if len(sys.argv) > 2 else "60m")
    name = sys.argv[1]
    import rlcore as rc
    p = rc.DATA + f"/{name}.json"; d = json.load(open(p))
    rows = d["rows"] if isinstance(d, dict) else d
    rows = [r.get("render", r) for r in rows if "trigger_ms" in r.get("render", r)]
    assign(rows, reqs)
    json.dump(d, open(p, "w"), indent=1)
    for r in rows:
        print(r["run"], [(a["family"][6:], a["ms"], a["result"]) for a in r["archive"]])
