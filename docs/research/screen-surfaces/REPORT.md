# Maximum iPhone screen surface & system presence — research report (run 2026-11-10)

Branch `research/max-screen-surface` (from `research/rendering-freedom` @ `a494631`).
Data: [`data/`](data/) · screenshots: [`img/`](img/) (402×874 pt downscale, 256 colours) · code: `prototype/Surfaces/`,
`prototype/Widget/SurfaceLabWidgets.swift`, `prototype/NotificationLab/`, `prototype/App/SLApp.swift`,
`prototype/UITests/SurfaceTests.swift`, `tools/sl/`. Full-resolution screenshots stay local (`experiments/screen-surfaces-raw/`, gitignored).

> **Scope of evidence.** Every measured result is `PASS_SIMULATOR` (Xcode 26.3, iOS 26.3.1 Simulator, German UI;
> main device iPhone 17 Pro, sizes also on iPhone 16e and iPhone 17 Pro Max). **Nothing is confirmed on hardware.**
> The iPhone 13 (iOS 18.7.8) was again `unavailable` in `devicectl` → every device test is `BLOCKED`; no iOS 18 runtime is installed.
> No architecture or product decision is made here.

## Status legend
`PASS_DEVICE` (none) · `PASS_SIMULATOR` · `DOCUMENTED` · `HYPOTHESIS` · `FAIL` · `BLOCKED`. "unknown" = not measured.

## What was built (isolated from the agent renderer)
| Piece | Purpose |
|---|---|
| `SLTileA…D` widget kinds (small/medium/large + accessory families, `contentMarginsDisabled`) | Home Screen tiles; one *kind* per tile because WidgetKit gives a widget no information about its position |
| `SLHitIntent`, shared `surfacelab/spec.json` | Tap regions per tile, shared state → `reloadAllTimelines()` |
| `SLLiveActivity` | Measurement Live Activity: Lock Screen view with ruler + 2 `LiveActivityIntent` buttons; every Dynamic Island region fills itself and logs its size |
| `NotificationLab` (Notification Content Extension, category `SL_RICH`) | Full UIKit UI inside an expanded notification: button, `UITextField`, scroll list, `WKWebView` |
| `SLControl` (`ControlWidgetButton`, iOS 18+) | Control Center / Lock Screen / Action button control |
| `SurfaceTests` + `tools/sl/` | Gallery/placement automation, coordinate taps, host screenshots during the test (`hold` markers), pixel measurement |

## Phase A — inventory of third-party surfaces
Screen of the reference device: iPhone 17 Pro **402 × 874 pt** (1206 × 2622 px, @3x) = 351 348 pt².

| # | Surface | Size (pt) | Share of screen | What we draw / what Apple owns | Interaction | User must add/enable? | Locked? | Lifetime / appears automatically? | Update path | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Home widget small | 164.33² (16e 162², Pro Max 176.67²) | 7.7 % | all pixels inside the corner mask; Apple: mask, label, position, background in tinted/clear modes | `Button`/`Toggle` (App Intents), `Link` | yes, per instance | no | permanent; no | timeline, reload budget, intents, push (iOS 26) | PASS_SIMULATOR |
| 1 | Home widget medium | 349.67×164.33 (16e 342×162, Pro Max 378×176.67) | 16.4 % | same | same | yes | no | permanent | same | PASS_SIMULATOR |
| 1 | Home widget large | 349.67×365 (16e 342×358, Pro Max 378×394) | 36.3 % | same | same | yes | no | permanent | same | PASS_SIMULATOR |
| 1 | Extra-large | – | – | iPad only | – | – | – | – | – | DOCUMENTED (not offered on iPhone gallery) |
| 2 | Lock Screen accessory widgets (circular, rectangular, inline) | unknown | unknown (rectangular ≈ half the row under the clock per HIG) | monochrome/vibrant rendering by the system | `Button`/`Toggle` (iOS 17+) | yes (Lock Screen editor) | yes | permanent | same as widgets | **BLOCKED** (Lock Screen editor not reachable in the Simulator via XCUITest: only 3 AX elements, long-press does nothing) / DOCUMENTED |
| 3 | Live Activity, Lock Screen | **374 × 160** (content asking 400 pt is clipped at 160) | 17.0 % | own view incl. background; Apple: card position, corner, stacking, permission prompt | `Button`/`Toggle` via `LiveActivityIntent` — **works while locked** | app starts it (foreground, push-to-start, or intent); user can disable | yes | ≤ 8 h + 4 h (DOCUMENTED); appears automatically when started | ActivityKit local update / push | PASS_SIMULATOR |
| 4 | Dynamic Island compact | island ≈159×36; our leading/trailing ≈10×22 each | 1.6 % (island) | two tiny regions | tap opens app; long-press expands | automatic with a running activity | n/a | while activity runs | same | PASS_SIMULATOR |
| 4 | Dynamic Island expanded | **≈373 × 159** (identical for 160 or 400 pt requests) | 16.9 % | leading/trailing/center/bottom regions; Apple: shape, position, black background | buttons (`LiveActivityIntent`) | long-press by user (or system on update alert) | n/a | until dismissed | same | PASS_SIMULATOR |
| 4 | Dynamic Island minimal | ≈10×22 region | <1 % | one region | – | automatic when 2+ apps have activities | n/a | – | – | PASS_SIMULATOR (size); multi-app case not tested |
| 5/6 | StandBy widgets / StandBy Live Activity full screen | full display, Lock Screen presentation **scaled ×2** after the user taps the minimal view (DOCUMENTED) | ≈100 % (landscape) | our Lock Screen presentation, scaled | unknown | phone charging, landscape, locked | yes | while in StandBy | same | **BLOCKED** in Simulator (rotating + locking did not enter StandBy; Home/Lock Screen stay portrait) / DOCUMENTED |
| 7 | Control Center control | one control tile (≈ 1 grid cell; user can resize) | unknown | SF Symbol + label only, system tile | tap → App Intent (**ran without opening the app**) | yes (CC edit → "Steuerelement hinzufügen") | Lock Screen controls: DOCUMENTED, not tested | permanent | intent / `ControlCenter.reloadControls` (DOCUMENTED) | PASS_SIMULATOR |
| 8 | Lock Screen controls / Action button | system button slot | small | symbol only | tap → intent | yes | yes | permanent | – | DOCUMENTED (not testable: Lock Screen editor BLOCKED) |
| 9 | Notification banner | ≈386 × 79 | 8.7 % | title/body/attachment; system layout | system actions, text input action (previous run C3) | permission | yes | ~5 s banner, then Notification Center | push / local | PASS_SIMULATOR |
| 9 | **Notification Content Extension (expanded)** | visible card **≈369 × 559** (view reports 402×900, rest scrolls) | **58.7 %** | **arbitrary UIKit view controller**; Apple: card frame, system action button below | **native UIKit**: button ✓, `UITextField` focus + typing ✓, scrolling ✓; `WKWebView` stayed blank | notification permission; user long-presses each notification | yes (DOCUMENTED; tested unlocked) | only while expanded | per notification | PASS_SIMULATOR |
| 10 | Today View | same widget families as Home Screen | – | – | – | yes | yes (left of Lock Screen) | – | – | DOCUMENTED (not measured) |
| 11 | Smart Stack / suggestions | widget size | – | content yes, rotation no | – | user builds the stack | – | system rotates; app can only hint via `TimelineEntryRelevance` | – | DOCUMENTED |
| 12 | Others found | Siri/Spotlight App Shortcut snippets, Focus filters (`SetFocusFilterIntent` – content adaptation, not new area), AlarmKit alerts (iOS 26, system UI + Live Activity), CallKit (calls only), Picture in Picture (video only) | – | – | – | – | – | – | – | DOCUMENTED, not tested |

Sources: [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) (StandBy: tap on minimal → Lock Screen presentation fills the display; oversized images can stop an activity from starting), [WWDC23 "Meet ActivityKit"](https://developer.apple.com/videos/play/wwdc2023/10184) (StandBy scaling), [HIG Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities), [HIG Widgets](https://developer.apple.com/design/human-interface-guidelines/widgets), [UNNotificationContentExtension](https://developer.apple.com/documentation/usernotificationsui/unnotificationcontentextension), [ControlWidget](https://developer.apple.com/documentation/swiftui/controlwidget).

## Phase B — Home Screen
**B1 sizes** (gallery previews, `context.displaySize`): see table above (`data/B1-sizes-*.json`, 17 Pro from `sl_timeline`).
iOS 26 also offers resizing from the widget's long-press menu (size icons) — user-controlled.

**E1 coverage** (`data/E1-coverage.json`, `img/E1-coverage.png`): all tiles full-bleed magenta, pixel count.
| Page layout (17 Pro) | Measured | Theoretical (rects) |
|---|---|---|
| 2 small + 2 medium | **46.9 %** | 48.1 % |
| large + medium | **≈52 %** (51.9–52.2 %, earlier RenderLab page) | 52.7 % |
| 3 medium / 6 small | – | 49.1 % / 46.1 % |
Free-renderable = coverage (whole widget rect inside the system corner mask). Interactive = the same area via tap regions (Rendering-freedom run: 1 pt accurate). Apple-only: status bar, Dynamic Island, labels under widgets, inter-widget gaps, search pill, dock (≈48 %).
iPhone 16e (theoretical L+M): 54.0 %; Pro Max: 51.3 %.

**E2 multi-widget surface** (`data/E2-multi-widget.json`, `img/E2-composite.png`): one 1206×2622 px picture cropped to the measured pixel boxes of 4 widget instances. Visually continuous; gaps and labels cut it. **8/8 taps** routed to the right tile (including the two halves of a "bridge" button drawn across the A|B gap). **A tap in the gap does nothing** (no widget there; app not opened) — the drawn surface is not one touch surface. Shared state: one tap → App Group spec → all 4 tiles re-rendered **85–290 ms after the intent** (`tiles_rerendered` lists A, B, C, D every time). Each tile had to be added separately from the gallery; placement order is decided by SpringBoard (new widgets go to the top and push others to later pages).

**E5 visual expansion** (`data/E5-tricks.json`, `img/E5-*.png`)
| Trick | Result | Extra function? |
|---|---|---|
| `containerBackground(Color.clear)` / `#00000000` | system fills it **opaque white** | `FAIL` (no real transparency in default mode) |
| Wallpaper crop from the same screen position (taken on another page, like apps that ask for a Home Screen screenshot) + 8 drawn "icons" on the real icon grid | looks like a row of app icons; system border, corner mask and "Agent Lab" label remain; **8/8 taps** work | visual only — still one widget's area |
| Wallpaper colours interpolated from pixels around the widget | blends roughly; edge visible | visual only |
| Composition across widgets (E2) | continuous illusion across gaps | interactions only inside widgets |
Changing the wallpaper itself is not available to third-party apps (no public API).

**B4 stacks / suggestions:** user builds stacks; apps can only provide relevance hints (`TimelineEntryRelevance`) — DOCUMENTED, not measurable deterministically in the Simulator.

## Phase C — Lock Screen and always-on surfaces
* **Live Activities** (`data/E3-*.json`): max **5 concurrent per app** (6th: *"Maximum number of activities for target already exists"*). Lock Screen card 374×160 pt at y≈477–637 pt, several activities **stack** (one visible card). First appearance adds a system prompt *"Live-Aktivitäten von Agent Lab erlauben?"* below the card. **Buttons A/B worked on the locked Lock Screen** (`sl_la_tap` ×2, label updated to "tapped B", app not opened). Requesting 400 pt height: content clipped at 160 pt (`img/E3-lockscreen.png`).
* **Dynamic Island** (`img/E3-h160-*`): compact island ≈159×36 pt with our two 10×22 pt regions; expanded ≈373×159 pt, capped. Only one of our 3 running activities is shown. One-activity-per-island behaviour with several *apps*: not tested.
* **Multiple agents in one Live Activity:** possible as layout (it is one SwiftUI view), but limited to 160 pt height and 5 activities; HYPOTHESIS that one activity with agent rows is more practical than one activity per agent (not measured).
* **StandBy:** BLOCKED in the Simulator. DOCUMENTED: in StandBy the minimal presentation sits at the top; a tap makes the Lock Screen presentation fill the display, scaled ×2. That means the "full-screen" view is our 374×160 pt layout scaled — not a new free full-screen canvas. Whether buttons work there: unknown.

## Phase D — unconventional surfaces
* **Notification Content Extension = the largest interactive surface found** (≈59 % of the screen, real UIKit incl. text input and scrolling). Limits: appears only after a notification and a user long-press; not persistent; `WKWebView` content did not render in our test; needs notification permission. Xcode issue found: with `ENABLE_DEBUG_DYLIB` the extension crashes (*"Unable to find NSExtensionContextClass (_UNNotificationContentExtensionVendorContext)"*) → disabled for that target.
* **Control widgets:** small but permanent and reachable from anywhere (Control Center, DOCUMENTED also Lock Screen / Action button).
* **Not usable for this purpose (App Review / API rules):** Picture in Picture without real video, fake media playback, CallKit without calls, private APIs, wallpaper changes, overlays over other apps (no public API on iOS).
* Developer pitfall: interpolated strings in `configurationDisplayName` crash the widget extension at runtime (*"Formatted text for `configurationDisplayName` is not supported"*) and remove **all** widgets of the bundle from the gallery.

## E6 — usability and accessibility
| Check | Result |
|---|---|
| Touch reliability | Home tiles 8/8 + 8/8, Live Activity locked 2/2, notification 3/3 actions, control 1/1 (coordinate taps, Simulator) |
| Small displays | 16e widget sizes ≈1.5 % smaller than 17 Pro; no Dynamic Island on 16e (Live Activity only on Lock Screen / banner) — layout not tested there |
| VoiceOver | not tested (BLOCKED; rendering-freedom run already showed missing AX elements for drawn UIs) |
| Tinted / clear modes | not tested; DOCUMENTED risk for bitmap-based tiles |
| Readability of tricks | fake icons and seams look plausible in screenshots; misleading-UI risk for App Review (HYPOTHESIS) |

## Phase F — comparison matrix
| Dimension | Home widgets (max page) | Multi-widget surface | Live Activity Lock Screen | Dynamic Island expanded | StandBy LA | Notification content ext. | Control |
|---|---|---|---|---|---|---|---|
| Visible area | ≈52 % (L+M) | ≤ 52 % per page, split | 17 % | 17 % | ≈100 % (DOCUMENTED) | 59 % | ≈1 cell (unknown) |
| Freely drawn | 100 % of widget rects | 100 % of rects, gaps not | own view, 160 pt cap | regions, cap | scaled Lock Screen view | full UIKit | no (symbol + label) |
| Interactive | taps (Button/Toggle) | taps per tile | taps, also locked | taps | unknown | **any UIKit touch, text input, scroll** | tap |
| User steps to see | add once; visible on every unlock/home visit | add N widgets once | none once started | long-press | dock + charge + landscape + tap | wait for notification + long-press | open CC |
| Presence | permanent | permanent | ≤ 12 h per activity | while expanded | while docked | seconds–minutes | permanent |
| Update | budgeted reloads, intents, push iOS 26 | same, shared state ≈0.1–0.3 s after tap | ActivityKit update/push | same | same | per notification | intent |
| Multiple agents | yes (regions/panes) | yes (tile per agent) | 5 activities or rows in one | 1 visible | 1 | one per notification | one control per action |
| System decides | size grid, position, labels, budget, modes | placement, gaps | height, stacking, dismissal, permission prompt | shape, cap, which activity | when StandBy shows, scaling | card frame, when it appears | tile look |
| iOS versions | 17+ (interactive), 26 tested | same | 16.1+ (buttons 17+) | 16.1+, DI devices only | 17+ | 10+ (interaction 12+) | 18+ |
| App Store fit | standard | ok; fake-icon trick risky | standard if tied to a real ongoing task | standard | standard | standard if tied to real notifications | standard |

## Answers to the ten questions (all Simulator-based, no decision)
1. **Available surfaces:** Home/Today widgets (3 iPhone sizes), Lock Screen accessory widgets, Live Activities (Lock Screen, Dynamic Island, StandBy), notifications incl. custom content extensions, Control Center/Lock Screen/Action-button controls, plus system-UI integrations (Siri/Spotlight snippets, Focus filters, AlarmKit).
2. **Most immediate:** Home Screen widgets (permanent, every unlock), Lock Screen Live Activity (visible before unlocking, interactive), Control Center controls; the Dynamic Island compact view is always visible but tiny.
3. **Home Screen share:** ≈52 % of the screen pixels on one page (large + medium, iPhone 17 Pro), ≈47 % with 2 small + 2 medium; the rest is reserved by iOS.
4. **One larger surface from several widgets:** visually yes, functionally no — each widget is a separate touch surface, gaps are dead; shared state syncs all tiles within ≈0.1–0.3 s after a tap; each tile must be added by the user.
5. **Visual extension beyond bounds:** only by illusion (matching wallpaper crop, fake icons, cross-widget composition). Real transparency is not available (clear background → white).
6. **Largest truly interactive surface:** expanded Notification Content Extension (≈59 %, full UIKit incl. text input) — temporary; among permanent surfaces: a full Home Screen page of widgets (≈52 %, tap-only).
7. **Lock Screen as agent surface:** up to 5 Live Activities (one visible card, 374×160 pt, buttons work while locked), notifications with custom UI, accessory widgets and controls (not testable here).
8. **StandBy full screen:** documented as the Lock Screen presentation scaled ×2 — a full-screen *view*, not a new free full-screen canvas; not reproducible in the Simulator (BLOCKED).
9. **Unexpected findings:** notification content extensions accept text input and scrolling; Live Activity buttons work on the locked screen; max 5 activities; expanded island hard cap; iOS 26 widget resize menu; display-name crash; debug-dylib crash of notification extensions; the Simulator cannot enter StandBy or edit the Lock Screen via XCUITest.
10. **Hard iOS limits:** widget grid sizes and placement, system labels/gaps/dock/status bar, no transparency, tap-only widgets, 160 pt Live Activity height, island cap, 5 activities, no wallpaper or overlay control, user consent for every surface. **Changeable by implementation:** how much of each surface we fill (full bleed), how many agents share one surface (regions/panes/tiles), synchronised multi-widget state, choosing notification extensions for rich temporary interaction.

## Reproduction (Simulator)
```bash
cd prototype && xcodegen generate && xcodebuild ... build-for-testing && xcrun simctl install booted <AgentWidgetLab.app>
cd ../tools/sl
python3 exp.py E1 E2 E5          # needs tiles A,B (small) + C,D (medium) on Home page 1 (gallery swipes 9/12 small, 16/19 medium)
./sizes_other.sh                 # widget sizes on iPhone 16e / 17 Pro Max (sets the Simulator language to German)
python3 exp_system.py ISLAND LOCK NOTIF CONTROL   # Live Activities, Dynamic Island, locked taps, rich notification, control
```
Helpers: `slcore.py` (spec, launch commands, lock, host screenshots during UI tests), `exp.py` (E1/E2/E5), `SurfaceTests.swift` (gallery add, pages, island, notification, coordinate steps).
