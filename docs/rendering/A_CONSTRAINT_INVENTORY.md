# Phase A — Constraint inventory of the baseline renderer

Baseline = branch `research/widgetkit-limits` @ `eb00d01`: `prototype/Shared/{Schema,Renderer}.swift`,
`prototype/Widget/AgentWidget.swift`, `docs/SCHEMA.md`, `docs/RESULTS.md`.
Every constraint is classified, then challenged. "Evidence" points at this branch's experiments
(`experiments/rendering/…`, IDs from [RENDERING_FREEDOM.md](../RENDERING_FREEDOM.md)) or at sources.

All experimental evidence cited here is `PASS_SIMULATOR` / `FAIL` in the iOS 26.3.1 Simulator; nothing is confirmed on hardware.

Classes: **(1) hard iOS limit** · **(2) consequence of the current SwiftUI rendering approach** ·
**(3) self-imposed framework rule** · **(4) unverified assumption**.

| # | Constraint in the baseline | Where | Class | Challenge / evidence |
|---|---|---|---|---|
| 1 | Only 14 node types (stacks, text, symbol, image, badge, progress, gauge, timer, relative, spacer, divider, button, row*) | `Renderer.swift` switch | **3** | Vocabulary is ours. A *display list* (rect/oval/path/arc/gradient/text/img/sym) renders any 2-D composition with the same "data only, no code" property (R1–R4). *`row` is listed in the schema comment but not implemented. |
| 2 | Layout only through VStack/HStack/ZStack, no absolute positions | `Renderer.swift` | **3** | SwiftUI supports `.offset`, `.position`, `Canvas`, custom `Shape`s inside widgets. Free positioning demonstrated (R2, R3). |
| 3 | Colors: 9 semantic names | `Palette` | **3** | Any sRGB/alpha color, linear/radial gradients render (R1–R6). (Tinted/clear Home Screen modes desaturate content: class 1, see #17.) |
| 4 | Text styles: 8 Dynamic-Type styles, 4 weights | `NodeView.font` | **3** | Arbitrary sizes (6–34 pt tested), weights, iOS system fonts by PostScript name (Didot, Menlo) and **fonts registered at runtime from App Group data** work (R11). |
| 5 | `maxNodes = 80` | `SchemaLimits` | **3** | Pure validation rule. With bypass the same renderer draws 200/1 000/3 000 nodes (T4 element count). Canvas draws 50 000 ops (T4 element count). |
| 6 | `maxButtons = 12` | `SchemaLimits` | **3** | 900 hit regions rendered; sampled taps never mis-routed even at 11.6 pt cells, but feedback slows to ≈6 s (T4 hit-region density). Usability (44 pt HIG) is the real constraint, not iOS. |
| 7 | `maxDepth = 8`, `maxText = 600`, `maxSchedule = 60` | `SchemaLimits` | **3** | Validation rules; no iOS counterpart found. Timeline entry count is not documented as limited; the archived timeline size is (see #13). |
| 8 | `maxImageBase64 = 60 000` (≈ 45 KB image) inline in JSON | `SchemaLimits` | **3** | Images can be files in the App Group. 1.2 MB PNGs at 3× and larger work up to the archival limit (T4 bitmap resolution). |
| 9 | Images: `scaledToFit` + 6 pt corner clip, no positioning | `NodeView` | **3** | Full-bleed bitmaps and freely placed images work (R5–R8). |
| 10 | Buttons: fixed look (13 pt label, 30 pt min height, filled/outlined) | `ActionButton` | **3** | Button label can be *any* view, including `Color.clear` → invisible, freely placed hit regions (T2: 51/51 correct, 4 renderers). |
| 11 | Default content margins + `.containerBackground(.background)` | `AgentWidgetView` | **3** (configurable) | `.contentMarginsDisabled()` gives the whole widget rect to the content; the system still applies the corner mask (surface control). |
| 12 | No scrolling, no text fields, only `Button`/`Toggle` interactive | WidgetKit | **1** | Documented by Apple ("Adding interactivity…"). Workarounds tested: paging via App Intent (RLPageIntent), multiple hit regions. |
| 13 | Widget images must be small (`imageTooLarge`) | — | **1** (+4) | Real: WidgetKit refuses to archive bitmaps above a pixel-area limit ("Widget archival failed due to image being too large"). Exact threshold measured on the Simulator (T4 bitmap resolution); not documented by Apple. |
| 14 | ≈ 30 MB extension memory | RESULTS.md | **4 → partly 1** | Not in Apple docs; reported by Apple engineers in forums. **The Simulator does not enforce it** (footprints up to 157 MB without termination, T4); device test BLOCKED. |
| 15 | UIKit views cannot be used | RESULTS.md | **1** | `UIViewRepresentable` renders as a placeholder (N1). Offscreen UIKit/CG rendering to an image *does* work (R4, R5). |
| 16 | No animations except system transitions | RESULTS.md | **1** | Not re-tested here (out of scope; `Text(timerInterval:)` etc. already proven). |
| 17 | Colors survive on Home Screen | implicit | **4** | Tinted/clear Home Screen (iOS 18+/26) desaturate or accent content; full-color images need `widgetAccentedRenderingMode(.fullColor)` and the background may be removed. Not tested in this run (Simulator appearance switching not automated) → HYPOTHESIS. |
| 18 | Unknown node types ignored → forward-compatible | `Renderer` | design choice | Display lists make new *visuals* forward-compatible without new node types; only new *op kinds* need an app update. |
| 19 | Render tree recomputed per family via `layouts` | `Schema` | **3** | Same principle works for scenes (`{f}` substitution) and bitmaps (one per family). |
| 20 | Agent supplies UI only as JSON | architecture | **3** | Agents can also supply HTML/CSS, PDF or pixels — rendered *outside* the extension (server/app) and delivered as files (R6–R9). No code is executed in the extension in any of these paths. |

## What this means
Of 20 listed constraints, **11 are self-imposed (class 3)**, 4 are hard iOS limits (class 1), and 3 are
partly or wholly unverified assumptions (class 4). The baseline therefore measured the expressiveness of our
own vocabulary, not of WidgetKit. The hard limits that remain are: SwiftUI-only view tree (no UIKit views, no web
views), tap-only interaction through `Button`/`Toggle` with App Intents, no scrolling or text input, an archival size
limit for images (and timelines), the extension memory cap (device only), and system-owned corner mask,
appearance modes and refresh budget.
