#!/usr/bin/env python3
"""End-to-end demo of the generic flow with a fake agent. Requires bridge.py running.

  1. Agent publishes a STATUS surface               -> widget shows progress
  2. Agent publishes a DECISION surface (same widget) -> buttons appear
     It also declares `agentReplies`: the bridge returns the agent's real next surface
     synchronously in the POST /response reply, so the App Intent can render it at once.
  3. User taps a button in the widget (or Live Activity / notification)
  4. Response arrives at the bridge -> agent long-polls /wait and logs the decision
  5. Widget already shows the agent's follow-up surface (no extra push needed)

Wake-up after steps 1 and 2: --wake sim sends a simulator background push (simctl);
on a device this would be an APNs push (BLOCKED here, see docs/RESULTS.md).
"""
import argparse, json, os, sys, time, urllib.request
sys.path.insert(0, os.path.dirname(__file__))

BRIDGE = os.environ.get("AWL_BRIDGE", "http://127.0.0.1:8787")


def post(path, obj):
    r = urllib.request.urlopen(urllib.request.Request(BRIDGE + path, json.dumps(obj).encode(), {"Content-Type": "application/json"}))
    return json.loads(r.read())


def get(path, timeout=130):
    try:
        return json.loads(urllib.request.urlopen(BRIDGE + path, timeout=timeout).read())
    except urllib.error.HTTPError as e:
        return {"error": e.code}


def iso(t=None):
    t = time.time() if t is None else t
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t)) + ".%03dZ" % int((t % 1) * 1000)


def T(text, style="body", **kw): return {"type": "text", "text": text, "style": style, **kw}
def header(agent, badge): return {"type": "hstack", "children": [T(agent.upper(), "caption", color="secondary", weight="semibold", lineLimit=1), {"type": "spacer"}, {"type": "badge", "text": badge}]}


def status(agent, rev, title, sub, p):
    return {"id": f"demo-status-{rev}", "agent": agent, "revision": rev, "issuedAt": iso(),
            "root": {"type": "vstack", "spacing": 6, "children": [header(agent, "RUNNING"), T(title, "headline"), T(sub, "caption", color="secondary"), {"type": "spacer"}, {"type": "progress", "value": p}]}}


def decision(agent, rev, question, options):
    sid = f"demo-decision-{rev}"
    buttons = [{"type": "button", "text": label, "action": aid, "prominent": i == 0} for i, (aid, label) in enumerate(options)]
    rows = [{"type": "hstack", "children": buttons[i:i + 2]} for i in range(0, len(buttons), 2)]
    s = {"id": sid, "agent": agent, "revision": rev, "issuedAt": iso(), "expiresAt": iso(time.time() + 3600),
         "root": {"type": "vstack", "spacing": 6, "children": [header(agent, "NEEDS INPUT"), T(question, "headline", lineLimit=2)] + rows},
         # Optimistic local state shown immediately by the App Intent (no network):
         "onAction": {aid: {"type": "vstack", "children": [header(agent, "SENDING"), T(f"{label} …", "headline")]} for aid, label in options},
         # The agent's real answer, returned synchronously by the bridge in the POST /response reply:
         "agentReplies": {aid: {"id": f"demo-after-{aid}", "agent": agent, "revision": rev + 2, "issuedAt": iso(),
                                "root": {"type": "vstack", "spacing": 6, "children": [
                                    header(agent, "ACK"), T(f"Got it: {label}", "headline"),
                                    T("Agent continues…", "caption", color="secondary"),
                                    {"type": "relative", "date": iso(), "style": "caption", "color": "secondary"}]}}
                          for aid, label in options}}
    return s


def wake(mode):
    if mode == "sim":
        import lab
        return lab.push("silent")[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wake", default="sim", choices=["sim", "none"])
    ap.add_argument("--agent", default="Coding Agent")
    ap.add_argument("--wait", type=float, default=120)
    a = ap.parse_args()
    rev = int(time.time()) % 100000 * 10

    print("1) status"); post("/surface", status(a.agent, rev, "Refactoring auth module", "Step 2 of 4", 0.5)); wake(a.wake)
    time.sleep(6)
    d = decision(a.agent, rev + 10, "Tests fail on CI. What next?", [("fix", "Fix tests"), ("revert", "Revert"), ("skip", "Skip CI"), ("ask", "Ask me later")])
    print("2) decision", d["id"]); post("/surface", d); t_pub = time.time(); wake(a.wake)
    print("3) waiting for the user to tap in the widget …")
    r = get(f"/wait?surface={d['id']}&timeout={a.wait}", timeout=a.wait + 5)
    if "error" in r:
        print("no response:", r); return 1
    print(f"4) response: action={r['action']} channel={r['channel']} created={r['createdAt']} "
          f"publish->response={r['_receivedAt'] / 1000 - t_pub:.2f}s")
    print("5) the widget already received the agent reply synchronously (see bridge log 'next': true)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
