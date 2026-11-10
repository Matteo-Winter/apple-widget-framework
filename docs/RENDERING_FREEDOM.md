# Maximum rendering freedom inside a WidgetKit widget — research report (run 2026-11-10)

Branch `research/rendering-freedom` (from `research/widgetkit-limits` @ `eb00d01`).
Phase A inventory: [rendering/A_CONSTRAINT_INVENTORY.md](rendering/A_CONSTRAINT_INVENTORY.md).
Raw data: [`experiments/rendering/data/`](../experiments/rendering/data/) · screenshots: [`experiments/rendering/img/`](../experiments/rendering/img/) (widget crops, downscaled 50 % and 256-color quantized for the repo; full-resolution Simulator screenshots stay local in the gitignored `experiments/rendering/raw/`). Bundle id and home path are redacted in the data files.

> **Scope of evidence:** every positive result in this document is `PASS_SIMULATOR` (iOS 26.3.1 Simulator).
> Nothing here is confirmed on hardware; there is no `PASS_DEVICE` result. "?" / "unknown" = not tested.

## Status legend
| Label | Meaning |
|---|---|
| `PASS_DEVICE` | Shown on real hardware — **none in this report** |
| `PASS_SIMULATOR` | Shown only in the iOS Simulator |
| `DOCUMENTED` | Official Apple documentation or Apple engineer statement, not tested here |
| `HYPOTHESIS` | Technically plausible, unproven |
| `FAIL` | Disproved by experiment |
| `BLOCKED` | Prerequisite missing |

## Environment and blockers
| Item | Value |
|---|---|
| Mac / Xcode | macOS 15.7.3 (24G419), Xcode 26.3 (17C529), iOS SDK 26.2 |
| Simulator | iPhone 17 Pro, iOS 26.3.1 (23D8133), German UI, scale 3 |
| Widget sizes (pt) | systemLarge 349.67 × 365, systemMedium 349.67 × 164.33 (from `context.displaySize` and chronod logs) |
| Server renderer | `tools/runtime/rl_render` (same Swift CG code, compiled for macOS); Google Chrome headless for HTML/CSS |
| Physical device | iPhone 13, iOS 18.7.8 — `devicectl` state **unavailable** (re-checked at start). Signing not retried (PLA blocker from the last run unchanged as far as known). **All device tests BLOCKED.** |
| iOS 18 | No iOS 18 Simulator runtime installed (only 26.3) → iOS 18 behavior **unknown** |

Simulator artifacts we had to work around (documented so nobody mistakes them for iOS behavior):
1. Every `simctl push` and every XCUITest-runner launch switches SpringBoard to Home Screen page 2 (`Current home screen page changed to: 2` in the SpringBoard log). One Home press returns. All screenshot-based "visible" timings therefore include ≈1.5 s of navigation and are **not** rendering latencies.
2. A raw JSON launch argument (`-rlcmd {…}`) is parsed as an old-style plist dictionary by `UserDefaults`; we pass base64.
3. The Simulator does not enforce the widget-extension memory cap; footprints of 75–157 MB were reached without termination (see T4). On device the commonly cited cap is ≈30 MB.

## What was built (all public API, no downloaded code)
`prototype/RenderLab/` (compiled into app **and** widget extension) + `prototype/Widget/RenderLabWidget.swift`:
* **Display list (`RLScene`)** — an agent-supplied flat list of drawing ops in its own coordinate space: `rect, oval, line, poly, arc, lgrad, rgrad, text, img, sym`, any sRGB/alpha color, any font size/weight/PostScript name, plus **interaction regions** (`regions: [{id, x, y, w, h, label, action}]`). Pure data, like the JSON tree, but without components.
* **One scene, many renderers** — SwiftUI view-per-op, SwiftUI `Canvas`, Core Graphics in the extension, CG in the app, CG on a server (`tools/rl/main.swift` compiles the *same* `RLScene.swift` + `RLCoreGraphics.swift` on macOS).
* **Native hit layer (`RLHitOverlay`)** — one `Button(intent: RLHitIntent)` per region, label `Color.clear` (or 1 % white), positioned with the same scale/offset math as the graphic. Works above any renderer.
* **Multi-agent compositor (`RLPanesView`)** — panes in normalized frames, each produced independently with its own technique; region ids namespaced `agent:region`.
* **Paging (`RLPageIntent`)** — regions with `action: "page:+1"` switch scene pages locally.
* Two widget kinds: `RenderLab` (`.contentMarginsDisabled()`) and `RenderLabMargins` (defaults).
* Instrumentation: `rl_timeline` (provider preparation time + `phys_footprint`), `rl_view` (body evaluation), `rl_canvas_draw` (Canvas closure time), plus WidgetKit's own extension log lines `Request began/ended for RenderLab:<family> … - success|error` (parsed by `tools/rl/archive_log.py`).

### Measurement stages (kept separate everywhere)
| Stage | What it is | Source |
|---|---|---|
| **G – generation** | Producing the pixels/data outside WidgetKit: server CG, Chrome, app CG/WebKit | tool wall time / `rl_prerender` |
| **P – provider preparation** | Inside `getTimeline`: decode file, offscreen render, font registration | `rl_timeline prepMs` |
| **A – handover / archive** | WidgetKit request in the extension: provider + SwiftUI body + view archiving, until WidgetKit reports success/error | chronod/extension log "Request began → ended" |
| **V – visible** | Pixels on the Home Screen | `simctl io screenshot` diff + saved screenshot (±0.5 s, plus page-switch artifact) |

## Techniques and results

API references: WidgetKit [overview](https://developer.apple.com/documentation/widgetkit), [Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension), [Adding interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities), [`contentMarginsDisabled()`](https://developer.apple.com/documentation/swiftui/widgetconfiguration/contentmarginsdisabled()), [`containerBackground(for:)`](https://developer.apple.com/documentation/swiftui/view/containerbackground(for:alignment:content:)), [Canvas](https://developer.apple.com/documentation/swiftui/canvas), [GraphicsContext](https://developer.apple.com/documentation/swiftui/graphicscontext), [Core Graphics](https://developer.apple.com/documentation/coregraphics), [Image I/O](https://developer.apple.com/documentation/imageio), [CGPDFDocument](https://developer.apple.com/documentation/coregraphics/cgpdfdocument), [Swift Charts](https://developer.apple.com/documentation/charts), [Core Image](https://developer.apple.com/documentation/coreimage), [`CTFontManagerRegisterGraphicsFont`](https://developer.apple.com/documentation/coretext/1499499-ctfontmanagerregistergraphicsfon), [WKWebView `takeSnapshot`](https://developer.apple.com/documentation/webkit/wkwebview/takesnapshot(with:completionhandler:)), [Optimizing for accented rendering mode](https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass).

### Test surface 1 — free graphic design (T1)
Same brief for every technique: full-bleed 3-stop gradient, two translucent radial glows, overlapping translucent circles, 34 pt heavy + 6–13 pt text, Didot and Menlo by PostScript name, donut chart from 4 arcs, filled sparkline (40 pts), 12 gradient bars, an overlapping card with a photo and SF Symbol, a rotated "HOT" tag (HTML only), chips, 6 pt micro-type grid, CSS `writing-mode` (HTML only).
Sheets: [`img/sheet-T1-large.png`](../experiments/rendering/img/sheet-T1-large.png), [`img/sheet-T1-medium.png`](../experiments/rendering/img/sheet-T1-medium.png).

| ID | Technique | Where pixels are made | G (L / M) | P ms (L / M) | A ms (L / M) | Visual result | Status |
|---|---|---|---|---|---|---|---|
| R0 | Baseline JSON tree (`NodeView`) | widget, SwiftUI | – | 0.6 / 1.1 | 17 / 66 | Only text, badges, gauge, progress. No gradient, chart, free placement, photo, font. | PASS_SIMULATOR (brief **not** achievable) |
| R1 | SwiftUI view per op (`ZStack` + `.offset`) | widget, SwiftUI | – | 5.5 / 4.0 | 97 / 23 | Identical to R2 after fixing a layout bug of ours (centered text grew the ZStack) | PASS_SIMULATOR |
| R2 | SwiftUI `Canvas` (`GraphicsContext`) | widget, SwiftUI | – | 0.8 / 0.6 | 22 / 23 | Full brief except rotation (no rotate op yet) | PASS_SIMULATOR |
| R3 | Core Graphics + CoreText in `getTimeline` → `UIImage` | extension | – | 25 / 11.6 (render 24 / 10) | 92 / 46 | Pixel-identical to R4/R5, SF Symbols drawn | PASS_SIMULATOR |
| R4 | Same CG code in the **app** (background push) → PNG in App Group | app | 102 / 44 ms (render + encode), 1.17 MB / 0.59 MB | 26.8 / 10.4 (decode) | 32 / 14 | as R3 | PASS_SIMULATOR |
| R5 | Same CG code on the **Mac/server** → PNG | server | 50 + 57 ms / 26 + 28 ms, 1.17 / 0.58 MB | 28.1 / 13.5 | 33 / 21 | as R3, **no SF Symbols** (not available to CG on a server) | PASS_SIMULATOR |
| R6 | **HTML/CSS** → headless Chrome screenshot (server) → PNG | server | 1 980 / 1 120 ms wall (incl. Chrome launch), 0.74 / 0.37 MB | 18.1 / 12.3 | 24 / 16 | Full CSS: conic gradients, masks, SVG, `backdrop-filter`, transforms, `writing-mode`, web layout | PASS_SIMULATOR |
| R7a | HTML/CSS → **WKWebView in the app, foreground** → PNG | app | 1 527–2 515 / 628–777 ms, 1.31 / 0.64 MB | 18.4 / 10.1 | 24 / 16 | as R6 (WebKit instead of Blink) | PASS_SIMULATOR |
| R7b | same, app launched **in background** by a silent push | app | never finished (no `rl_prerender` within 40 s) | – | – | widget kept the previous image | **FAIL** (as implemented) |
| R8 | HTML → Chrome **PDF** (vector) → `CGPDFPage` rasterized in `getTimeline` | server + extension | 1 900 / 888 ms, 246 / 86 KB | **283 / 255** | 345 / 290 | Vector text sharp, but Chrome's PDF dropped the conic donut and rasterized `backdrop-filter` as a dark box | PASS_SIMULATOR (with fidelity loss) |
| R9 | Swift Charts | widget, SwiftUI | – | 0.2 / 0.4 | 106 / 40 | Native area/line/rule chart | PASS_SIMULATOR |
| R10 | Core Image (`CIQRCodeGenerator`) in `getTimeline` | extension | – | 137 (first) / 2 | 16 / 6 | QR code rendered | PASS_SIMULATOR |
| R11a | Font file shipped as **data**, registered in the extension (`CTFontManagerRegisterGraphicsFont`), used by SwiftUI text | extension | – | 5 | success | Registration `true`, `UIFont(name:)` usable, archive **success**, but the Home Screen shows the **redacted placeholder** | **FAIL** |
| R11b | same font, rasterized with CoreText into the CG bitmap (R3) | extension | – | – | 18 / 12 | Font renders correctly | PASS_SIMULATOR |
| N1 | `UIViewRepresentable` (UILabel) | – | – | 0.3 | 16 / 6 (success) | Yellow "prohibited" placeholder | **FAIL** (= DOCUMENTED) |
| N2 | SVG bytes → `UIImage(data:)` | – | – | 14.6 | – | `nil` | **FAIL** (rasterize SVG outside, R6) |

### Test surface 2 — complex interaction without opening the app (T2)
A seat map (24 rounded squares), 4 circular swatches, a triangular target (rectangular hit box), 5 segmented slots, 8 tiny 22 pt targets with 4 pt gaps, two CTA buttons — **all drawn graphics**, none of them native controls. Every element is a region → transparent native `Button`.
Proof method: XCUITest taps **by screen coordinate** computed on the host from the agent's scene coordinates (`plan_points` in `tools/rl/experiments.py`), then each tap is matched to the `rl_hit` event the App Intent wrote in the widget extension. The app was not opened.

| Run | Graphic made by | Taps | Correct | Wrong | Missed | Median tap→intent* |
|---|---|---|---|---|---|---|
| t2-canvas-clear (label `Color.clear`) | Canvas | 51 | **51** | 0 | 0 | 367 ms |
| t2-canvas-faint (label 1 % white) | Canvas | 51 | 51 | 0 | 0 | 368 ms |
| t2-bitmap-html | Chrome PNG (server) | 51 | 51 | 0 | 0 | 368 ms |
| t2-cg-ext | CG in extension | 51 | 51 | 0 | 0 | 368 ms |
| near-edge, 22 pt targets, 3 pt inset | Canvas | 40 | 40 | 0 | 0 | – |
| near-edge, 22 pt targets, **1 pt inset** (4 pt gaps) | Canvas | 40 | 40 | 0 | 0 | – |
| near-edge, 60×34 slots, 3 pt inset | Canvas | 25 | 25 | 0 | 0 | – |
| near-edge, 28 pt seats, 2 pt inset | Canvas | 120 | 120 | 0 | 0 | – |
| **Total** | | **428** | **428** | 0 | 0 | |

\* includes XCUITest tap synthesis (≈0.3 s per the previous run). Every tap re-archived both widgets (large ≈92–107 ms, medium ≈20–27 ms) and the selected region got a native outline (`img/t2-*-after-taps-large.png`). Debug outlines showing the region alignment: `img/t2-debug-large.png`.
**Status: PASS_SIMULATOR.** Device touch accuracy (finger size, Home Screen jiggle, lock state) is BLOCKED.

### Test surface 3 — three independent agents in one widget (T3)
| Pane | Agent | Produced by | Interaction |
|---|---|---|---|
| top, 94 %×49 % | Portfolio | HTML table → headless Chrome PNG (1 529 ms, 57 KB) | 5 agent-declared hit regions over the drawn "Buy/Sell" buttons |
| bottom-left | Ops | display list drawn by Canvas in the widget | 2 regions |
| bottom-right | Mail | **baseline JSON tree** with a native button | `AgentActionIntent` (existing path) |

Provider preparation 6–17 ms, archive 33–55 ms (large). Taps: **7/7** pane regions reported as `portfolio:trade-N` / `ops:scale|mute`; the Mail button reached `AgentActionIntent` (`action_received widget c/send`). It was then rejected by the baseline's single-surface revision guard (`want c#1 have decision-1#81217`) — a **framework limitation** (one global surface/revision in `Store`), not an iOS one. Screenshot `img/t3-multi-debug-large.png` (region outlines), `img/t3-after-taps-large.png` (selection on "Mute").
**Status: PASS_SIMULATOR.** A tap outside every region (first, mis-aimed attempt) opened the app (`scene_active`) — the default widget tap behavior.

### Test surface 4 — stress (T4)
Large + medium widget rendered the same spec each time. A = WidgetKit archive request in the extension.

**Element count (random rect/oval/text/poly/gradient ops)** — data `T4ops.json`, sheet `img/sheet-T4ops-large.png`

| Ops | Canvas P / draw / **A** (L) | Views-per-op P / **A** (L) | CG-in-ext P (render) / **A** (L) | Scene JSON |
|---|---|---|---|---|
| 100 | 1.3 / 1.4 / **9 ms** | 1.3 / **53 ms** | 8 (6) / **38 ms** | 11 KB |
| 1 000 | 9.5 / 17 / **36 ms** | 8 / **481 ms** | 57 (45) / **121 ms** | 0.1 MB |
| 5 000 | 41 / 56 / **109 ms** | 41 / **2.5 s** | 177 (132) / **263 ms** | 0.6 MB |
| 20 000 | 148 / 191 / **359 ms** | 203 / **9.6 s** | 635 (450) / **731 ms** | 2.3 MB |
| 50 000 | 360 / 481 / **0.88 s** | 349 / **28.3 s** | 1 445 (1 107) / **1.55 s** | 5.8 MB |

All requests ended `success`. Views-per-op scales ≈ linearly in *archive* cost (≈0.5 ms per view) — at 20 000+ the next reload waits for it, and screenshots taken before archive completion showed stale content. Baseline JSON tree with the 80-node rule bypassed: 200 nodes 287 ms, 1 000 nodes 1.07 s, 3 000 nodes 3.17 s archive — the **same per-view cost**; with validation on it fails closed ("Schema rejected", 201 > 80).
Memory: extension `phys_footprint` reached 105 MB (CG 50 000) and 157 MB (bitmap 12×) in the **Simulator without termination**. Device cap ≈30 MB is not enforced here → everything above ≈25 MB in this table is **unknown on device** (BLOCKED).

**Bitmap resolution (server CG of T1, PNG)** — data `T4px.json`

| Scale vs. pt | Large px | Bytes | Decode ms | A (L / M) |
|---|---|---|---|---|
| 1× | 349×365 | 162 KB | 6.8 | 17 / 14 ✓ |
| 3× (native) | 1047×1095 | 1.17 MB | 21 | 32 / 20 ✓ |
| 4× | 1396×1460 | 1.97 MB | 35 | 44 / 21 ✓ |
| 6× | 2094×2190 | 4.21 MB | 74 | 85 / 37 ✓ |
| 8× | 2792×2920 | 7.23 MB | 106 | **error / error** |
| 12× | 4188×4380 | 15.3 MB | 278 | **error** |

Exact WidgetKit messages (extension log):
`Widget archival failed due to image being too large [274] - (4188, 4380), totalArea: 18343440 > max[5054082.000000]` and
`ArchivingError.imageTooLarge(size: (2792.0, 1312.0) …) totalArea: 3663104 > max[2275490.8]`.
→ **Limit = 4.4 × the widget's own pixel area** (large: 5 054 082 px ≈ 4.4 × 349.67×365×9; medium: 2 275 491 px ≈ 4.4 × 349.67×164.33×9), i.e. ≈2.1× native linear resolution. On failure the widget **silently keeps its previous snapshot** (`img/t4-px-8x-*.png` shows the 6× image). Status PASS_SIMULATOR; that the formula is identical on device is a HYPOTHESIS (forum reports show other maxima, e.g. 2 121 055 px, on other devices).

**Formats at 3×** — data `T4fmt.json`: PNG 1.17 MB / decode 17 ms; JPEG q0.9 202 KB; JPEG q0.5 96 KB; HEIC q0.9 114 KB; HEIC q0.5 48 KB. All rendered; decode 3–68 ms with first-use outliers. Format choice is a transport-size question, not a rendering one.

**Hit-region density** — data `T4regions.json` (12 random taps each, routed in order)

| Regions (large) | Cell | Routed correctly | Tap→intent median | Re-archive after tap (L) |
|---|---|---|---|---|
| 16 | 87 pt | 12/12 | 0.35 s | 84 ms |
| 64 | 44 pt | 12/12 | 0.42 s | 321 ms |
| 144 | 29 pt | 12/12 | 0.55 s | 502 ms |
| 400 | 17 pt | 12/12 | 1.8 s | 1.19 s |
| 900 | 12 pt | 11/12 within 8 s, all in order | **6.2 s** | 2.76 s |

Taps are never mis-routed and not lost, but each tap triggers a re-archive whose cost grows with button count; taps queue behind it. Practical limit: a few dozen regions per widget for sub-second feedback. (The 44 pt HIG minimum is the usability limit long before that.)

### Surface control (Phase C)
| Question | Finding | Status |
|---|---|---|
| Can content fill the whole widget? | With `.contentMarginsDisabled()` the first content pixel is at the widget's frame edge (x = 80 px = frame), with 16 pt padding at 127 px (`MARGIN.json`, `img/margin-*`). | PASS_SIMULATOR |
| What stays under Apple's control? | Corner mask (continuous radius, ≈27.9 pt per chronod log `349.67/365.00/27.94`), widget size/position, label below, background in tinted/clear modes, StandBy/Lock Screen backgrounds, refresh budget. | PASS_SIMULATOR (mask) / DOCUMENTED (modes) |
| Pixel-exact positioning | Region outlines and drawn shapes coincide; scene → screen mapping (`plan_points`) hit 1 pt-inset targets 40/40. | PASS_SIMULATOR |
| Arbitrary colors, gradients, shapes, layers | Yes in R1–R8 (see T1). | PASS_SIMULATOR |
| Custom fonts | System-installed iOS fonts by PostScript name: yes. Runtime-registered fonts in SwiftUI text: **no** (R11a). Rasterized: yes (R11b). Bundled fonts in the app/extension (Info.plist `UIAppFonts`): DOCUMENTED, not tested. | `PASS_SIMULATOR` (installed/rasterized) · `FAIL` (runtime font in SwiftUI text) · `DOCUMENTED` (bundled) |
| Tinted / clear Home Screen (iOS 18 / 26) | Images are desaturated/accented unless `.widgetAccentedRenderingMode(.fullColor)`; background can be removed. This hits bitmap approaches hardest. Not tested (no automated appearance switch). | DOCUMENTED / HYPOTHESIS |
| Lock Screen accessory families, StandBy, Live Activities, Dynamic Island | Families are declared; rendering not tested in this run. Accessory families render in vibrant/monochrome mode, so free color is not available there. | DOCUMENTED, test BLOCKED/not run |
| Accessibility | Observation in the Simulator: in the RenderLab widget **no button** — neither transparent regions nor the native JSON button in T3 — appeared in SpringBoard's XCUITest tree, although all of them worked by coordinate. The previous run did see `action-*` buttons in the AgentSurface widget. Cause unknown. Bitmap UIs have no text for VoiceOver unless regions carry labels. | `HYPOTHESIS` (cause open) — needs a VoiceOver test on device |

### Navigation without scrolling (PAGE)
A 30-item list as 3 scene pages; "‹ Prev / Next ›" are regions with `action: page:±1` → `RLPageIntent` changes `spec.page`, the provider loads `page-{p}-{f}.json`. Sequence item 3 → next → item 14 → next → item 27 → prev → item 15: **7/7** events in order (`PAGE.json`, `img/page-final-large.png` shows page 2/3). PASS_SIMULATOR. Each page turn costs one widget reload (budget-exempt because user-initiated, per Apple).

## Comparison matrix
All cells are `PASS_SIMULATOR` measurements unless marked `FAIL`, `DOCUMENTED` or `HYPOTHESIS`. "?" = not tested.

| Dimension | R0 JSON tree (baseline) | R1 SwiftUI view-per-op | R2 Canvas display list | R3 CG in extension | R4/R5 CG bitmap (app/server) | R6/R7 HTML → bitmap | R8 PDF vector | Hybrid: any of R2–R8 + hit layer |
|---|---|---|---|---|---|---|---|---|
| **Graphic freedom** | 14 components, 9 colors, 8 text styles | any 2-D shape/gradient/text/image | same | same + SF Symbols | same (server: no SF Symbols) | everything CSS/SVG can do | CSS minus Chrome-PDF losses | as underlying |
| **Positioning** | stacks only | absolute | absolute | absolute | absolute | absolute / CSS layout | absolute | regions absolute, 1 pt accurate |
| **Area usable** | inside default margins | full rect minus system corner mask (with `contentMarginsDisabled`) | same | same | same | same | same | same |
| **Interactions** | native buttons, fixed look, ≤12 by rule | via hit layer | via hit layer | via hit layer | via hit layer | via hit layer | via hit layer | 428/428 taps correct; any look; tap only |
| **Complexity (ops)** | 80 by rule; 3 000 nodes → 3.2 s archive | 5 000 → 2.5 s, 50 000 → 28 s archive | **50 000 → 0.9 s** | 50 000 → 1.6 s | independent of op count (pixels) | independent | 1 page: 0.3 s | regions: ≤ dozens for < 0.5 s feedback |
| **Performance (T1, large)** | P 0.6 ms, A 17 ms | P 5.5, A 97 | P 0.8, A 22 | P 25, A 92 | G 0.1 s app / 0.1 s server; P 27, A 32 | G 1.5–2.5 s (WebKit fg) / 2 s (Chrome cold); P 18, A 24 | G 1.9 s; P 283, A 345 | render cost of the region layer not isolated; each tap re-archives (T2 large 92–107 ms) |
| **Memory** | ? (device) | ? | ? | adds a full bitmap in the extension | bitmap ≤ 4.4× widget px or archive fails | same | same | ? |
| **Dynamics (agent changes everything)** | only within vocabulary | fully, by data | fully, by data | fully, by data | fully, any renderer the agent likes | fully, agent writes HTML | fully | fully |
| **Multi-agent** | one tree | panes possible | panes (T3) | panes | panes (T3 agent A) | panes (T3) | panes | namespaced regions, 7/7 routed |
| **iOS 18 vs 26** | builds for iOS 17+; 26 tested | 26 tested, 18 ? | 26 tested, 18 ? | 26 tested, 18 ? | 26 tested, 18 ? | 26 tested, 18 ? | 26 tested, 18 ? | 26 tested, 18 ? |
| **Proven not possible** | – | > ~5 000 views (archive seconds) | rotation not implemented (API exists) | – | > 4.4× widget pixel area; server: SF Symbols | WebKit snapshot in background (R7b); live web view in widget (N1) | CSS fidelity via Chrome PDF | text input, scrolling, gestures other than tap, a11y exposure unclear |

## Phase D — creative probes, including dead ends
| Hypothesis | Result |
|---|---|
| Render the entire UI outside WidgetKit and show one image | Works (R4–R7a); limited by 4.4× pixel area, tinted modes (hypothesis) and loss of accessibility text. |
| Invisible native buttons over a picture | Works with `Color.clear` labels (no `contentShape` trick needed beyond what we used), 1 pt edge accuracy. |
| Many tiny views are slow → one composited graphic | Confirmed: 5 000 ops: views 2.5 s vs Canvas 0.11 s vs CG 0.26 s archive. |
| Chart not native → draw it | Canvas/CG arcs + polylines (R2/R3) and Swift Charts (R9) all work. |
| No scroll → page | Works via intents (PAGE). |
| Independent agent renders + composite | Works (T3), including mixing server bitmap, Canvas and JSON tree. |
| Ship a font as data | SwiftUI text: FAIL (placeholder); rasterize it: works (R11). |
| SVG directly | FAIL with `UIImage(data:)`; rasterize elsewhere (R6) or convert to display-list paths (HYPOTHESIS). |
| Vector via PDF | Works but 10× slower in P than PNG decode and lossy via Chrome. |
| WebKit inside the widget | Not possible (N1, DOCUMENTED). WebKit **in the app** in foreground works (R7a); background launch hung (R7b). |
| MapKit snapshot in the provider | DOCUMENTED by an Apple engineer (`MKMapSnapshotter` in the timeline provider); not tested. |
| Metal / SpriteKit / SceneKit views in a widget | Same class as N1 (UIKit-backed) → expected FAIL; offscreen GPU rendering to a `CGImage` in the provider: HYPOTHESIS, risky under the memory cap. |
| Frame-by-frame animation via timeline entries | Previous run E04: entries fire ≈2 s late → no smooth animation. Not repeated. |
| Bigger-than-widget image + fill/crop for "zoom" | Possible up to 4.4× area; beyond that silent failure. |

## Answers (all `PASS_SIMULATOR`; no hardware confirmation)
1. **How far can a widget become a freely designable, interactive surface?** In the Simulator: every pixel inside the system corner mask can be agent-defined (any 2-D graphics, any web-renderable design via pre-rendering), and any number of arbitrarily shaped tap targets can be laid over it with point accuracy. What stays impossible: live views other than SwiftUI (no WebKit/UIKit/Metal views), anything except taps (no scroll, drag, text input), animation, and control outside the widget rect.
2. **The JSON component tree is not the limit — it is one renderer among several.** It is the slowest per element (same cost as views-per-op), the least expressive, and its limits (80 nodes, 12 buttons, 9 colors, 60 KB images) are ours.
3. **Most promising direction for "many agents, maximum freedom" (not a decision):** a *data-only display list* rendered by `Canvas` (fast, vector, sharp at any scale, no pixel-size limit, 50 000 ops < 1 s) **plus** an agent-declared region layer, with *pre-rendered bitmaps* (server HTML/CSS or CG) as an escape hatch for anything the op set cannot express — always capped below 4.4× widget pixels. The JSON tree remains useful for accessibility-heavy, text-first cards.
4. **Hard open risks:** device memory cap (≈30 MB) vs. bitmaps and big scenes, tinted/clear Home Screen modes for bitmaps, accessibility of drawn UIs, iOS 18 behavior, real finger accuracy.

## Next steps (device needed)
1. USB-connect the iPhone 13 (iOS 18.7.8), accept the PLA, install, add RenderLab large + medium. Re-run T1, T2 (coordinate taps → manual taps), T4px (does 4.4× hold on iOS 18?), T4ops with memory (`rl_timeline mem…`) to find the real cap.
2. Test tinted/clear Home Screen with bitmap vs Canvas (+ `widgetAccentedRenderingMode`).
3. VoiceOver pass over T2/T3.
4. If an iOS 26 device exists: repeat T2 and PAGE there.

## Reproduction
```bash
# build + install (see prototype/README.md for Local.xcconfig and DerivedData outside iCloud)
cd prototype && xcodegen generate && xcodebuild ... -derivedDataPath ~/Library/Developer/Xcode/DerivedData/AWL build-for-testing
xcrun simctl install booted ~/Library/Developer/Xcode/DerivedData/AWL/Build/Products/Debug-iphonesimulator/AgentWidgetLab.app
# add RenderLab medium + large (German SpringBoard; gallery swipes 4 = medium, 5 = large)
TEST_RUNNER_RL_SWIPES=4 xcodebuild test-without-building ... -only-testing:AgentWidgetLabUITests/RenderLabTests/testAddWidget
TEST_RUNNER_RL_SWIPES=5 xcodebuild test-without-building ... -only-testing:AgentWidgetLabUITests/RenderLabTests/testAddWidget
# server renderer
swiftc -O -o tools/runtime/rl_render prototype/RenderLab/RLScene.swift prototype/RenderLab/RLCoreGraphics.swift tools/rl/main.swift
# experiments (needs macOS Accessibility permission for the Simulator Home shortcut, Google Chrome for HTML)
cd tools/rl && python3 experiments.py T1 T2 T3 MARGIN T4ops T4px T4fmt T4regions NEG PAGE
python3 archive_log.py T1 3h      # back-fill WidgetKit archive durations from the unified log
```
Files: `tools/rl/rlcore.py` (spec/trigger/measure), `surfaces.py` (the four test surfaces as scene, HTML and JSON), `experiments.py`, `archive_log.py`, `sheet.py`.
