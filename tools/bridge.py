#!/usr/bin/env python3
"""Minimal agent bridge (stdlib only). Stands in for "the agent" during experiments.

  GET  /surface              -> current surface JSON the agent wants on the phone
  POST /surface              -> agent publishes a new surface (revision auto-bumped)
  POST /response             -> phone returns a user decision; reply may carry {"next": surface}
  GET  /responses?since=ms   -> responses received (for agents / measurement scripts)
  GET  /wait?surface=id&timeout=s -> long-poll until a response for that surface arrives

Rules (in-memory, demo only): a surface may declare "agentReplies": {actionId: surface}
which the bridge returns synchronously as "next" when that action arrives. That models
an agent that answers within the App Intent's lifetime.

Every request is logged as JSON lines to tools/runtime/bridge-events.jsonl with ms timestamps.
"""
import json, os, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

HERE = os.path.dirname(os.path.abspath(__file__))
RUNTIME = os.path.join(HERE, "runtime")
os.makedirs(RUNTIME, exist_ok=True)
LOG = os.path.join(RUNTIME, "bridge-events.jsonl")

state = {"surface": None, "responses": [], "replies": {}}
cond = threading.Condition()


def now_ms():
    return int(time.time() * 1000)


def log(event, **kw):
    rec = {"t": now_ms(), "e": event, **kw}
    with open(LOG, "a") as f:
        f.write(json.dumps(rec) + "\n")
    print(json.dumps(rec), flush=True)


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if u.path == "/surface":
            with cond:
                s = state["surface"]
            log("get_surface", rev=s and s.get("revision"), peer=self.client_address[0])
            return self._send(200, s) if s else self._send(404, {"error": "no surface"})
        if u.path == "/responses":
            since = int(q.get("since", ["0"])[0])
            with cond:
                return self._send(200, [r for r in state["responses"] if r["_receivedAt"] >= since])
        if u.path == "/wait":
            sid = q.get("surface", [""])[0]
            deadline = time.time() + float(q.get("timeout", ["120"])[0])
            with cond:
                while time.time() < deadline:
                    hit = [r for r in state["responses"] if r.get("surfaceId") == sid]
                    if hit:
                        return self._send(200, hit[-1])
                    cond.wait(timeout=max(0.05, deadline - time.time()))
            return self._send(408, {"error": "timeout"})
        self._send(404, {"error": "unknown"})

    def do_POST(self):
        u = urlparse(self.path)
        if u.path == "/surface":
            s = self._body()
            with cond:
                cur = state["surface"]
                if cur and s.get("revision", 0) <= cur.get("revision", 0):
                    s["revision"] = cur["revision"] + 1
                state["replies"] = s.pop("agentReplies", {}) or {}
                state["surface"] = s
                cond.notify_all()
            log("publish_surface", rev=s["revision"], id=s.get("id"))
            return self._send(200, {"ok": True, "revision": s["revision"]})
        if u.path == "/response":
            r = self._body()
            r["_receivedAt"] = now_ms()
            with cond:
                dup = any(x.get("responseId") == r.get("responseId") for x in state["responses"])
                if not dup:
                    state["responses"].append(r)
                nxt = state["replies"].get(r.get("action"))
                if nxt:
                    cur = state["surface"] or {}
                    nxt = dict(nxt)
                    nxt["revision"] = max(nxt.get("revision", 0), cur.get("revision", 0), r.get("revision", 0)) + 2
                    state["surface"] = nxt
                    state["replies"] = {}
                cond.notify_all()
            log("response", action=r.get("action"), text=r.get("text"), channel=r.get("channel"),
                surface=r.get("surfaceId"), duplicate=dup, createdAt=r.get("createdAt"), next=bool(nxt),
                peer=self.client_address[0])
            return self._send(200, {"ok": True, "duplicate": dup, **({"next": nxt} if nxt else {})})
        self._send(404, {"error": "unknown"})


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
    log("bridge_start", port=port)
    ThreadingHTTPServer(("0.0.0.0", port), H).serve_forever()
