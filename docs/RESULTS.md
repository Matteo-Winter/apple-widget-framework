# WidgetKit limits — research results (run 2026-11-10)

Branch `research/widgetkit-limits`. Raw evidence: [`experiments/results/`](../experiments/results/).
Per-test records: [`experiments/results/2026-11-10-simulator-run.md`](../experiments/results/2026-11-10-simulator-run.md).

## Status legend

| Label | Meaning |
| --- | --- |
| **PASS** | Successfully tested on real hardware |
| **SIMULATOR ONLY** | Confirmed only in the iOS Simulator |
| **DOCUMENTED** | Backed by official Apple documentation, not tested here |
| **BLOCKED** | A prerequisite is missing |
| **FAIL** | Tested in practice and did not work |

**No result in this document is PASS.** The physical iPhone could not be reached (see Blockers). Every measured
number below comes from the Simulator. Device refresh budgets, push delivery and power management behave
differently on hardware. Treat the latencies as *lower bounds of the mechanism*, not as production expectations.

## Environment

| Item | Value |
| --- | --- |
| Mac | macOS 15.7.3 (24G419), Apple silicon |
| Xcode / SDK | Xcode 26.3 (17C529), iOS SDK 26.2 |
| Simulator | iPhone 17 Pro, iOS 26.3.1, German locale |
| Physical device | iPhone 13, iOS 18.7.8, **unavailable** (see Blockers) |
| Signing | Paid individual team (automatic signing); team id kept in gitignored `Config/Local.xcconfig` |
| Prototype | `prototype/` @ this branch, deployment target iOS 17.0 |

## Blockers (manual action required)

1. **Program License Agreement.** The signed device build fails with *"PLA Update available … agree to the latest Program
   License Agreement in your developer account."* Until it is accepted, Xcode cannot provision the App Group or Push
   capability for the new bundle IDs. → All device tests BLOCKED.
2. **No device connection.** No cable was available. Over the university Wi-Fi the iPhone is not discoverable at all
   (`_apple-mobdev2._tcp` / `_remotepairing._tcp` Bonjour browse returns nothing), which is consistent with client
   isolation on the network. Workaround: connect once via USB, or put the Mac on the iPhone's Personal Hotspot.
3. **WidgetKit push needs iOS 26.** `WidgetPushHandler` / `WidgetPushInfo` are `@available(iOS 26.0, *)` in the SDK.
   The test iPhone runs iOS 18.7.8, so WidgetKit push is BLOCKED on this device even after 1 and 2 are solved.
4. **APNs credentials.** No APNs auth key (.p8) exists. Real WidgetKit, Live Activity and background pushes need one
   plus a sender. `simctl push` does not substitute for it (see E08, E07p).

## Summary table

| ID | Question | Status | Key measurement (Simulator) |
| --- | --- | --- | --- |
| G0 | Builds and installs | SIMULATOR ONLY | Original scaffold **did not install** (`Invalid placeholder attributes`); fixed. Device build compiles unsigned; signed build BLOCKED (PLA) |
| A1 | One installed widget renders materially different layouts from JSON | SIMULATOR ONLY | 9 presets plus host-generated trees, same binary. Small and medium tested; large and Lock Screen accessory families declared and supported by the renderer, but not tested visually |
| A2 | Unknown components degrade safely | SIMULATOR ONLY | Unknown `webview` node ignored, rest rendered |
| E01 | App publishes + `reloadTimelines` → `getTimeline` | SIMULATOR ONLY | median **0.052 s** (n=44, p90 0.21 s, max 1.05 s) |
| E02 | Shared-data write **without** reload, app terminated | SIMULATOR ONLY | **No change in 180 s**, no `getTimeline` |
| E03 | Widget button → App Intent → new layout, app not launched | SIMULATOR ONLY | tap→intent 0.31 s*, intent runtime 7 ms, tap→`getTimeline` **0.35 s**, tap→new layout in a11y tree median **0.69 s** (n=10); app state *not running* |
| E04 | Pre-scheduled timeline entries switch layouts with no process running | SIMULATOR ONLY | 5/5 switches, **1.7–2.9 s after** planned instant (incl. ≈0.4 s screenshot resolution), no extension/app wake |
| E05 | Invalid / oversized / too deep JSON | SIMULATOR ONLY | Safe "Schema rejected" card, no crash. **Found a real bug** (required `schema` key) and fixed it |
| E06 | Rapid taps on two different options | SIMULATOR ONLY | 3 taps → exactly 1 intent, 1 response |
| E06b | Tap on a stale card (store has newer revision) | SIMULATOR ONLY | Rejected in 2 ms, widget reloaded to current revision |
| E07 | Live Activity: start, Dynamic Island, button via `LiveActivityIntent` | SIMULATOR ONLY | Started from foreground; island tap ran intent in **background app process** (not opened); response at bridge in 78 ms; widget reloaded 0.26 s later |
| E07p | Live Activity update via push | BLOCKED | `simctl push` to `<bundle>.push-type.liveactivity` is delivered as a plain notification to an unknown bundle, not to ActivityKit |
| E08 | WidgetKit push (`content-changed`) | BLOCKED | Same `simctl` behavior for `.push-type.widgets`: no `getTimeline` (0/5). Device needs iOS 26 + APNs key |
| E10 | Background push → app wakes → pull → reload → visible | SIMULATOR ONLY | push→wake 0.14–0.20 s (suspended) / 0.57–0.82 s (terminated); push→`getTimeline` 0.20–0.26 / 0.72–1.20 s; push→visible ≤ 0.8 s. *Simulator delivers it as background fetch without payload* |
| E12 | 20 background pushes, 1 s apart | SIMULATOR ONLY | 20/20 handled, 40 `getTimeline` (2 families): **no throttling in the Simulator**. Apple documents budgets on devices, so not transferable |
| C1 | Agent response back-channel | SIMULATOR ONLY | Intent → HTTP POST to bridge (from the widget extension or, for Live Activity/notification, the background app): 2–105 ms; agent long-poll receives it |
| C2 | Agent's next UI returned synchronously in the intent | SIMULATOR ONLY | Bridge reply carried the agent's follow-up surface; `getTimeline` 0.115 s after intent start, no second push |
| C3 | Text input without opening the app | SIMULATOR ONLY | `UNTextInputNotificationAction`: reply typed in the notification, handler ran in **background** (appState 2), text at bridge in 105 ms |
| C4 | Text input inside widget / Live Activity | DOCUMENTED (not possible) | Only `Button`, `Toggle` (and `Link`) are interactive in widgets/Live Activities; no `TextField` |
| C5 | Button capacity | SIMULATOR ONLY | Medium: 8 hittable buttons (4×2, 75×30 pt). Small: 8 hittable but only 29×30 pt (< 44 pt guideline). Usable limit: **≈4 per medium widget, 2 per small** |
| B1 | Budget 40–70 reloads/day, roughly every 15–60 min | DOCUMENTED | Exempt: app in foreground, App Intent interaction, and others (Apple "Keeping a widget up to date") |
| B2 | Background push guidance "two or three per hour" | DOCUMENTED | Apple "Pushing background updates to your app" |
| B3 | BGAppRefreshTask | DOCUMENTED | Implemented (`BackgroundRefresh`), but the system decides timing (earliest 15 min requested). Not measurable in a deterministic way |
| B4 | Live Activity limits | DOCUMENTED | Up to 8 h active, 4 h more on Lock Screen; ≤ 4 KB content; background start only via push-to-start (iOS 17.2+) or `LiveActivityIntent` |
| L1 | Lock Screen behavior of widgets / Live Activity while locked | BLOCKED | The Simulator lock could not be automated reliably; needs device |

\* XCUITest's synthesized tap adds ≈0.3–0.5 s before the intent starts; real finger taps will be faster. Use *intent→getTimeline* (median 0.042 s) as the mechanism latency.

## Answers to the research questions

### 1. What can we demonstrably do with iPhone widgets? (Simulator evidence)
- One installed widget (one binary) renders **arbitrary agent-defined component trees** (stacks, text, symbols, badges,
  progress, timers, relative time, buttons, links, small images) from JSON, including different trees per widget size
  and Lock Screen accessory families.
- Widget buttons run App Intents **in the widget extension** without launching the app. The intent writes the answer,
  shows an optimistic follow-up layout, and POSTs the decision to an agent bridge over HTTP.
- The agent can answer **inside the same request**, so its real next UI is on screen ≈0.1 s after the tap.
- Background pushes wake the app (even from terminated) to pull a new surface and reload the widget in < 1 s.
- Notification actions accept **free text** and process it in the background.
- Live Activities / Dynamic Island render the same schema and accept button taps via `LiveActivityIntent`.

### 2. How dynamic can structure and content be?
- **Structure:** fully data-driven within a fixed vocabulary (currently 14 node types, `button` with `url` acts as a link). New node *types* need an app
  update; new *combinations* do not. Unknown types are ignored, so old app versions degrade safely.
- **Limits enforced by us:** depth ≤ 8, ≤ 80 nodes, ≤ 12 buttons, ≤ 600 chars per text, ≤ 60 KB base64 image, ≤ 60
  scheduled entries. Apple's limits: no scroll views, no text fields, no UIKit views, no animations beyond the system
  transitions, a widget-extension memory cap (≈30 MB is commonly cited; not stated on the pages we checked).
- **Time-dependent content without updates:** `Text(timerInterval:)`, `ProgressView(timerInterval:)` and
  `Text(_, style: .relative)` keep moving with zero refreshes (seen in screenshots: "2 Min., 0 Sek." ticking).
- **Pre-scheduled layouts (E04):** one write can carry up to 60 future trees. iOS switches between them at the planned
  instants with no process running. This is the strongest budget-free tool for *predictable* agent states.

### 3. How fast can widgets actually update?
| Trigger | Mechanism latency (Simulator) | Device expectation |
| --- | --- | --- |
| User taps widget button | intent→`getTimeline` 0.04 s; visible ≈0.3–0.7 s | Budget-exempt per Apple; should hold on device (to verify) |
| App in foreground calls reload | 0.05 s median | Budget-exempt while app is foreground |
| Background push → app → reload | 0.2–1.2 s | Push delivery is opportunistic; Apple advises ≤ 2–3 background pushes/hour |
| WidgetKit push (iOS 26) | not measurable here | Budgeted by the system; BLOCKED |
| Data write without reload | never (180 s observed) | Widget stays stale until the next budgeted reload (15–60 min typical) |
| Pre-scheduled entry | planned time + ≈2 s | Free, exact enough for timers / plans |

### 4. Which interactions work completely without opening the app?
Widget buttons and toggles (E03), Live Activity / Dynamic Island buttons (E07), notification action buttons and
**notification text replies** (C3). All of them deliver the decision to the agent from a background process.
Not possible: text entry inside a widget or Live Activity, scrolling lists, gestures other than tap.

### 5. What works and what doesn't?
**Works (Simulator):** universal JSON renderer, optimistic `onAction` transitions, synchronous agent reply inside the
intent, revision/expiry/replay guards, background-push-triggered pull, pre-scheduled timelines, timer views, Live
Activity with the same renderer, text replies via notifications.
**Doesn't work / not testable:** making a widget change visibly without a reload trigger (E02 FAIL as a technique),
`simctl` for WidgetKit or Live Activity pushes (tooling gap), payload delivery of `simctl` background pushes (arrive
as payload-less background fetch). We added a lab stand-in that drops the payload into the App Group and labelled
it as such.

### 6. Which limits are most critical for the product vision?
1. **Agent-initiated updates while the user is not interacting are budgeted.** For unpredictable events we depend
   on WidgetKit push (iOS 26+, budgeted) or background push (throttled, may not be delivered under low power).
   Sub-minute "live" widgets driven by remote agents are not something iOS guarantees. *This is the core risk.*
2. **WidgetKit push needs iOS 26 on the user's device.** Older devices fall back to background push or the budget.
3. **No text input in widgets.** Free-form answers must go through notifications (or the app).
4. **Choice density:** ≈4 comfortable options per medium widget. Larger menus need paging (intent-driven state) or
   a hand-off to a notification or the app.
5. **Live Activities are time-boxed (8 h + 4 h)** and meant for bounded tasks. They are good for "agent is running /
   waiting for me", not for a permanent surface.
6. **Our own schema vocabulary is compiled.** New component types need an App Store update. Design the vocabulary broadly now.

### 7. Most sensible next step
1. Accept the PLA, connect the iPhone once via USB (or via the iPhone's Personal Hotspot) and rerun the identical
   suite on hardware. `prototype/README.md` lists the commands. Priority: E03 (tap latency), E01, E04, E06b, E07, C3
   with the phone locked and unlocked.
2. Create an APNs auth key and add a minimal sender to `tools/` for background pushes (works on iOS 18) and Live
   Activity pushes. Measure delivery distributions over hours, not seconds, including Low Power Mode.
3. If an iOS 26 device is available: WidgetKit push measured against the background-push path.
4. Architecture decision based on 1–3: *content-free push + pull-on-reload* (implemented as `pullOnReload`) vs.
   payload pushes.

## Architecture implemented (generic, no per-agent UI code)

```
agent ──POST /surface──▶ bridge (Mac, tools/bridge.py) ◀──GET /surface── app / widget extension (pull)
   ▲                              │                                              │
   └──── GET /wait (long-poll) ◀──┴──── POST /response ◀── App Intent in widget / Live Activity / notification
                                       (reply may carry the agent's next surface → rendered immediately)
wake-ups: app foreground reload │ background push → app pulls │ WidgetKit push (iOS 26) │ user tap │ scheduled entries
```

See [`docs/SCHEMA.md`](SCHEMA.md) for the schema.
