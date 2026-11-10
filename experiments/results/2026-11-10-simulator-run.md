# Test records — 2026-11-10, Simulator run

**Common environment:** macOS 15.7.3, Xcode 26.3 (17C529), iOS SDK 26.2, Simulator iPhone 17 Pro iOS 26.3.1 (German UI),
prototype on branch `research/widgetkit-limits`. Widgets: one small and one medium "Agent Surface" on Home Screen page 1,
added by `HomeScreenTests.testA_AddWidgets`. Bridge `tools/bridge.py` on 127.0.0.1:8787. Network: loopback.
Developer Mode: n/a (Simulator). Lock state: unlocked for all runs. **Status of every record: SIMULATOR ONLY unless stated.**

Measurement sources:
- App Group event log `events.jsonl`: ms timestamps from app (`p: app`) and widget extension (`p: ext`). Same clock as host.
- XCUITest accessibility polling of SpringBoard. Widget **buttons** are exposed with our `accessibilityIdentifier`;
  plain texts are not. "Visible" = button appeared or disappeared.
- Host screenshot diff (`tools/lab.py watch`), ≈370–530 ms per frame, so the resolution is ±0.5 s.

Data: [`data/`](data/). Images: [`img/`](img/).

---

### G0 — Build and install
- Original scaffold: builds, but `simctl install` fails: *"Failed to create app extension placeholder … Invalid placeholder
  attributes"* (hand-written extension Info.plist). **FAIL → fixed** by generated Info.plist with only `NSExtension`.
- Repo in iCloud-synced `~/Documents` → codesign error *"resource fork, Finder information, or similar detritus not allowed"*;
  fixed by building to `~/Library/Developer/Xcode/DerivedData/AWL`.
- Device: unsigned generic iOS build succeeds; signed build BLOCKED (PLA, see RESULTS.md).

### A1/A2 — Layout switching from JSON
Procedure: publish presets status, decision, decision4, grid8, list, timer, calendar, scheduled plus host-written trees.
Result: same installed widget shows all of them; per-family layouts work (small vs. medium). The `webview` node was ignored.
Image: `img/roundtrip-after-tap.png`, `img/E05-unknown_type.png`.

### E01 — App foreground publish + `reloadTimelines`
Procedure: `testB_PublishToVisible`, 8 alternating publishes via URL scheme (app foreground), then Home.
Result: `reload_requested` → `get_timeline` median 0.052 s (n=44 across the session, p90 0.214 s, max 1.052 s).
Publish → button visible after returning Home: 2.27–3.58 s. This number is dominated by test navigation (opening app, Home press), not by WidgetKit.

### E02 — Write without reload
Procedure: app terminated; host writes `surface.json` directly into the App Group; screenshots for 180 s.
Result: no visible change, no `get_timeline`. **The mechanism by itself does not update the widget.** Timeline policy was `.after(+15 min)`.

### E03 — Widget button → App Intent
Procedure: `testC_TapLatency`, 10 runs; app **terminated** before each tap.
Result (`data/analysis-BC.json`): tap→intent 0.304–0.532 s (median 0.312), intent runtime 6–92 ms (median 7),
tap→`get_timeline` median 0.349 s, tap→layout changed in a11y tree median 0.692 s (p90 1.335, max 1.473).
App state after tap: *not running* (1) in all runs. The app was not launched.
Limitation: XCUITest tap synthesis adds ≈0.3–0.5 s; bridge was offline in this run (POST failed fast in 3–53 ms).

### E04 — Pre-scheduled timeline entries
Procedure: one surface with 5 `schedule` entries 30 s apart; app terminated; screenshots around each instant.
Result: 5/5 switches, drift +1.71, +2.88, +1.82, +1.85, +1.93 s (includes ≈0.4 s frame time). No `get_timeline` near the
switches, so no process ran. Images `img/E04-step*.png`.

### E05 — Invalid schemas
Procedure: host writes not-JSON, missing root, depth 13, 201 nodes and an unknown type, then triggers a reload.
Result: safe "Schema rejected" card with reason; unknown type ignored; no crash.
**Bug found:** first run rejected *every* host surface with `keyNotFound("schema")`. Synthesized `Decodable` ignores
property defaults. Fixed (`schema` optional), rerun passed.

### E06 / E06b — Duplicate and stale taps
- E06: Investigate, Revert, Investigate tapped back-to-back by coordinate → 1 `action_received`, 1 outbox entry.
  The later taps never reached an intent (widget re-rendered).
- E06b: widget shows rev N, app silently stores rev N+1 (no reload), tap on old button → `action_rejected` in 2 ms
  ("want #81215 have #81216"), widget reloaded 47 ms later to the current revision.

### E07 — Live Activity / Dynamic Island
Procedure: `testG_LiveActivity`: start activity from foreground app, go Home, long-press island, tap action.
Result: `activity_auth enabled=true frequent=true`, activity started, push token issued. Island button ran
`AgentActivityActionIntent` in the **app process in background** (XCUI state 3), response at bridge in 78 ms, activity
updated, widget `get_timeline` 0.26 s after tap. Compact island showed the answered state (`img/dynamic-island-compact.png`).
E07p (push update): `simctl push` to `<bundle>.push-type.liveactivity` ×4 → no change; system log shows it treated as
a user notification for an unknown bundle. **BLOCKED** (needs APNs + device).

### E08 — WidgetKit push
Procedure: write surface without reload, `simctl push <bundle>.push-type.widgets {"aps":{"content-changed":true}}` ×5.
Result: no `get_timeline` (0/5); SpringBoard logs *"Not delivering user visible notification … because it has no alert"*.
**BLOCKED:** simctl does not emulate WidgetKit push; the device has iOS 18 (API is iOS 26+); no APNs key.

### E10 — Background push wake → pull → reload
Procedure: agent publishes to bridge; `simctl push {"aps":{"content-available":1}}`; 6 runs alternating terminated/suspended.
Observation: the Simulator delivers this as **background fetch** (`performFetchWithCompletionHandler`) with no payload,
not as `didReceiveRemoteNotification`. The app therefore pulls from the bridge (content-free wake-up pattern).
Result: push→wake 0.136–0.199 s (suspended) / 0.572–0.825 s (terminated); push→`get_timeline` 0.195–0.264 /
0.717–1.201 s; push→visible 0.69–0.79 s (screenshot-limited).
Lab stand-in: for tests that need a payload (E04/E05 reload-only), `lab.py` writes the payload to
`sim-push-payload.json` and the fetch handler reads it. This emulates APNs payload delivery; it is not APNs.

### E12 — Burst
20 background pushes 1 s apart → 20 handled, 40 `get_timeline` (2 widgets). No throttling observed **in the Simulator**.
Apple documents budgets and "two or three per hour" for background pushes on devices.

### C1/C2 — Round trip with agent (Phase 4 flow)
Procedure: `tools/agent_demo.py` + `testH_RoundTrip`.
Timeline (from App Group log): status published + push → app wake → `get_timeline` +0.25 s after wake; decision with
4 options published + push → `get_timeline` +0.08 s after wake; tap "Fix tests" → intent start; optimistic save +10 ms;
POST to bridge done +53 ms (39 ms network) with `next` (agent reply); `get_timeline` +115 ms after intent start; agent's long-poll returned the response (8.78 s after publish incl. waiting for the tap).
Image: `img/roundtrip-after-tap.png`.

### C3 — Notification text reply
Procedure: `testI_NotificationText`: notification permission granted, text notification fired with app in background,
long-press banner → "Reply" → typed text → Send.
Result: `notification_action reply text=ship it after lunch appState=2` (background), bridge POST 105 ms, widget reload requested.
Notification action titles are fixed per registered category. Dynamic options must be registered by the app beforehand (`Notifications.registerCategory`).

### C5 — Button capacity
`testE_Capacity`: decision4 → 4/4 hittable in small (61×30 pt) and medium (154×30 pt); grid8 → 8/8 hittable in small
(29×30 pt) and medium (75×30 pt); list → 4/4 (39–42 pt wide in small).
