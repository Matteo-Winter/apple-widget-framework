#!/bin/zsh
cd "$(dirname "$0")"
for x in T4ops T4px T4fmt T4regions NEG; do echo "== $x"; python3 -u experiments.py $x; done
python3 -u - <<'PY'
import json, rlcore as rc, surfaces as sf
F=["systemLarge","systemMedium"]
cmd={"jobs":[{"op":"html","html":f"t1-{f}.html","out":f"t1-apphtml-{f}.png","pw":sf.SIZES[f][0]*3,"ph":sf.SIZES[f][1]*3} for f in F]}
rows=[rc.run_case("t1-bitmap-app-html-fg2","bitmap",cmd=cmd,fg=True,timeout=20,bitmap="t1-apphtml-{f}.png")]
print(rows[0]["prerender_all"], rows[0]["archive"])
json.dump(rows,open(rc.DATA+"/T1-apphtml-fg.json","w"),indent=1)
PY
