"""SurfaceLab host helpers (Simulator). Reuses tools/lab.py and tools/rl/rlcore.py."""
import base64, json, os, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..")); sys.path.insert(0, os.path.join(HERE, "..", "rl"))
import lab  # noqa
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "docs", "research", "screen-surfaces")
DATA = os.path.join(OUT, "data"); IMG = os.path.join(OUT, "img")
RAW = os.path.join(ROOT, "experiments", "screen-surfaces-raw"); os.makedirs(RAW, exist_ok=True)
PROJ = os.path.join(ROOT, "prototype", "AgentWidgetLab.xcodeproj")
DD = os.path.expanduser("~/Library/Developer/Xcode/DerivedData/AWL")
SIM_NAME = os.environ.get("SL_SIM_NAME", "iPhone 17 Pro")

def gdir():
    d = os.path.join(lab.group_dir(), "surfacelab"); os.makedirs(d, exist_ok=True); return d

def put(name, obj):
    p = os.path.join(gdir(), name)
    if isinstance(obj, (dict, list)): json.dump(obj, open(p, "w"))
    elif isinstance(obj, bytes): open(p, "wb").write(obj)
    else:
        import shutil; shutil.copyfile(obj, p)
    return p

def spec(run, **kw):
    s = {"run": run, "tiles": {}}; s.update(kw); put("spec.json", s); return s

def slcmd(cmd, wait=4.0):
    """Foreground app launch with a SurfaceLab command."""
    t = lab.now_ms()
    subprocess.run(["xcrun", "simctl", "launch", "--terminate-running-process", lab.SIM, lab.BUNDLE, "-slcmd",
                    base64.b64encode(json.dumps(cmd).encode()).decode()], capture_output=True)
    time.sleep(wait); return t

def reload_bg():
    """Background reload via silent push (Simulator jumps to page 2 → one Home press back)."""
    t, rc, out = lab.push("silent", extra={"surfacelab": {"op": "reload"}})
    time.sleep(0.3); lab.home(1); return t

def uitest(name, **env):
    e = dict(os.environ); e.update({f"TEST_RUNNER_{k}": str(v) for k, v in env.items()})
    r = subprocess.run(["xcodebuild", "test-without-building", "-project", PROJ, "-scheme", "AgentWidgetLab",
                        "-destination", f"platform=iOS Simulator,name={SIM_NAME}", "-derivedDataPath", DD,
                        f"-only-testing:AgentWidgetLabUITests/{name}"], capture_output=True, text=True, env=e)
    out = []
    for line in r.stdout.splitlines():
        if line.startswith("AWL|"):
            _, t, k, j = line.split("|", 3)
            try: out.append((int(t), k, json.loads(j)))
            except Exception: pass
    return out, "** TEST EXECUTE SUCCEEDED **" in r.stdout

def lock():
    """Simulator > Device > Lock (Cmd+L)."""
    subprocess.run(["osascript", "-e", 'tell application "Simulator" to activate', "-e", "delay 0.2", "-e",
                    'tell application "System Events" to keystroke "l" using {command down}'], capture_output=True)
    time.sleep(1.5)

def shot(name):
    p = os.path.join(RAW, f"{name}.png"); lab.shot(p); return p

def save(name, obj):
    p = os.path.join(DATA, f"{name}.json"); json.dump(obj, open(p, "w"), indent=1); return p

def events(since, prefix="sl_"):
    return [e for e in lab.events(since) if e["e"].startswith(prefix)]

def uitest_hold(name, shots_prefix, **env):
    """Runs a UI test and takes HOST screenshots whenever the test emits a `hold` marker
    (the test sleeps SL_HOLD seconds after each marker)."""
    e = dict(os.environ); e.update({f"TEST_RUNNER_{k}": str(v) for k, v in env.items()})
    p = subprocess.Popen(["xcodebuild", "test-without-building", "-project", PROJ, "-scheme", "AgentWidgetLab",
                          "-destination", f"platform=iOS Simulator,name={SIM_NAME}", "-derivedDataPath", DD,
                          f"-only-testing:AgentWidgetLabUITests/{name}"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=e)
    out, shots = [], {}
    for line in p.stdout:
        if line.startswith("AWL|"):
            _, t, k, j = line.rstrip("\n").split("|", 3)
            try: o = json.loads(j)
            except Exception: o = {}
            out.append((int(t), k, o))
            if k == "hold":
                time.sleep(0.8); shots[o["what"]] = shot(f"{shots_prefix}-{o['what']}")
    p.wait()
    return out, shots
