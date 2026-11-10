# Research knowledge base — iPhone agent surfaces (as of 2026-11-10)

One entry point for everything learned so far. Details and raw data live in the phase reports.
**All experimental results are `PASS_SIMULATOR` (Xcode 26.3, iOS 26.3.1 Simulator). Nothing is confirmed on hardware**;
the test iPhone 13 (iOS 18.7.8) was never reachable (`devicectl`: unavailable) and the Apple PLA blocked signing.

## Phases and where to find them
| Phase | Branch / commit | Report | Question |
|---|---|---|---|
| 1 WidgetKit limits | `research/widgetkit-limits` @ `eb00d01` | [`docs/RESULTS.md`](../RESULTS.md) | How fast/how dynamic can one widget be updated and answered? |
| 2 Rendering freedom | `research/rendering-freedom` @ `a494631` | [`docs/RENDERING_FREEDOM.md`](../RENDERING_FREEDOM.md), [`docs/rendering/A_CONSTRAINT_INVENTORY.md`](../rendering/A_CONSTRAINT_INVENTORY.md) | How freely can the inside of a widget be drawn and made interactive? |
| 3 Screen surface | `research/max-screen-surface` @ `52f51a1` (contains 1 + 2) | [`docs/research/screen-surfaces/REPORT.md`](screen-surfaces/REPORT.md) | How much of the iPhone screen can a third-party app occupy outside its app? |

`main` is untouched; nothing has been merged.

## Core findings (one line each)
**Updates & interaction (phase 1)**
- A widget changes only when a reload is triggered: app in foreground, user tap (App Intent), scheduled timeline entry, background push → app → reload, or WidgetKit push (iOS 26+). Writing data alone does nothing.
- Tap → App Intent → new layout ≈0.35 s (Simulator, intent→`getTimeline` 0.04 s); the app is not launched.
- Up to 60 pre-scheduled layouts switch on time (≈2 s late) without any process running.
- No text input in widgets/Live Activities; free text works via notification text actions (and, phase 3, via notification content extensions).

**Rendering freedom (phase 2)**
- Our JSON component tree was the limit, not iOS: 11 of 20 constraints were self-imposed.
- Any 2-D design renders: SwiftUI `Canvas` display list (50 000 ops archived in 0.9 s), Core Graphics in extension/app/server, pre-rendered HTML/CSS (headless Chrome or WKWebView in the *foreground* app), PDF, Swift Charts.
- One SwiftUI view per element is slow: 5 000 views → 2.5 s, 50 000 → 28 s archive (same cost for the JSON tree).
- Transparent native buttons over a drawn picture: 428/428 taps correct, 1 pt edge accuracy; 900 regions still route correctly but feedback slows to ≈6 s.
- Hard limits: bitmaps > **4.4 × the widget's pixel area** fail silently (old snapshot stays); no UIKit/WebKit views (yellow "prohibited" placeholder); SVG not decodable; runtime-registered fonts fail in SwiftUI text but work when rasterized.

**Screen surface (phase 3)**
- Home Screen: max ≈**52 %** of the screen per page (large + medium); widget sizes 17 Pro small 164.33², medium 349.67×164.33, large 349.67×365 pt (16e: 162/342×162/342×358; Pro Max: 176.67/378×176.67/378×394).
- Several widgets can look like one surface and share state (all tiles re-render ≈0.1–0.3 s after a tap) but stay separate touch surfaces; gaps are dead; real transparency is impossible (clear background → white).
- Live Activities: max 5 per app; Lock Screen card 374×160 pt (taller content clipped), stacked; **buttons work while locked**; expanded Dynamic Island capped at ≈373×159 pt.
- Largest interactive surface: expanded **Notification Content Extension** ≈59 % of the screen with full UIKit (button, text input, scrolling) — temporary, needs a notification + long-press.
- Control widgets: addable via Control Center, tap runs the intent without opening the app.
- StandBy full screen = Lock Screen presentation scaled ×2 (documented), not reproducible in the Simulator.

## Lab handbook — pitfalls that cost time
**Build / Xcode**
- Repo lives in iCloud-synced `~/Documents` → build with `-derivedDataPath ~/Library/Developer/Xcode/DerivedData/AWL` (codesign "detritus" error otherwise).
- Team id and bundle id only in gitignored `prototype/Config/Local.xcconfig` (public repo).
- Run `xcodegen generate` after adding *any* new source file; otherwise new tests/targets silently do not exist (tests "pass" with 0 tests).
- Widget extension Info.plist: generated plist + `NSExtension` only (hand-written plist → "Invalid placeholder attributes" on install).
- `configurationDisplayName("Tile \(x)")` crashes the extension at runtime ("Formatted text … is not supported") and removes **all** widgets of the bundle from the gallery — pass a plain `String`.
- Notification Content Extension + `ENABLE_DEBUG_DYLIB` → crash "Unable to find NSExtensionContextClass" — set `ENABLE_DEBUG_DYLIB = NO` for that target.
- Synthesized `Decodable` ignores property defaults → make optional (`schema` bug in phase 1).

**Simulator behaviour (not iOS behaviour)**
- Every `simctl push` and every XCUITest-runner launch switches SpringBoard to Home page 2; one Home press (Cmd+Shift+H) returns to page 1. A second press may jump again.
- `simctl push` cannot emulate WidgetKit or Live Activity pushes; `content-available` arrives as payload-less background fetch.
- `simctl openurl` shows a confirmation dialog → use `simctl launch … -arg <base64>` (raw JSON args are parsed as plist dictionaries by `UserDefaults`).
- Cmd+L locks; a Home press on the Lock Screen **unlocks** (no passcode) — never press Home before locked-screen taps.
- The Simulator does not enforce the ≈30 MB widget memory cap (157 MB seen) and cannot enter StandBy.
- The Lock Screen editor and the Control Center contents are not in the XCUITest accessibility tree → coordinate taps + host screenshots.
- Widget content buttons were not exposed in SpringBoard's AX tree in phases 2/3 → tap by computed coordinates.
- `XCUIScreen.main.screenshot()` from the runner showed the app instead of SpringBoard → take host screenshots (`simctl io screenshot`) on `hold` markers (`tools/sl/slcore.uitest_hold`).
- Banners disappear after ≈5 s; the UI-test runner needs ≈10 s to start → schedule notifications ≥30 s ahead.
- WidgetKit archive time is the real "handover" metric: parse `Request began/ended for <kind>` from the extension log (`tools/rl/archive_log.py`); screenshots taken before archive end can be stale.

**Safety rules used in the lab**
- Widget-removal automation only touches widgets labelled with our app name ("Agent Lab"); Apple's widgets are never removed.
- No private APIs, no wallpaper changes, no fake media/PiP/CallKit, no downloaded code in extensions.

## Open items (all need hardware)
1. iPhone via USB, accept the PLA, rerun: tap latency, bitmap limit (4.4×?), memory cap, real finger accuracy.
2. Lock Screen accessory widgets and Lock Screen controls; StandBy full screen with buttons.
3. VoiceOver, tinted/clear Home Screen modes, iOS 18 vs 26 differences, WidgetKit push (iOS 26 device + APNs key).

## Reusable tooling
| Path | Use |
|---|---|
| `tools/lab.py`, `tools/run_experiments.py` | phase 1 host driver (pushes, events, screenshot diff) |
| `tools/rl/` | phase 2: specs, scene generators, server renderer (`main.swift`), archive-log parser |
| `tools/sl/` | phase 3: tiles, Live Activity/notification/control procedures, multi-device sizes |
| `prototype/UITests/*` | SpringBoard automation (German UI labels) |
