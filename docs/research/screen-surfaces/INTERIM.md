# Max screen surface — INTERIM results (incomplete, 2026-11-10)

Branch `research/max-screen-surface`. **Work stopped early (usage limit). Everything below is `PASS_SIMULATOR`**
(iPhone 17 Pro Simulator, iOS 26.3.1, German UI) unless marked. iPhone 13 (iOS 18.7.8): still unavailable → all device tests `BLOCKED`.
Data: `data/`, screenshots: `img/` (402×874 downscaled). Code: `prototype/Surfaces/`, `prototype/Widget/SurfaceLabWidgets.swift`,
`prototype/NotificationLab/`, `prototype/App/SLApp.swift`, `prototype/UITests/SurfaceTests.swift`, `tools/sl/`.

| ID | Finding | Status |
|---|---|---|
| B1 | Widget sizes (gallery previews, `context.displaySize`): small 164.33×164.33, medium 349.67×164.33, large 349.67×365 pt. No extra-large on iPhone. | PASS_SIMULATOR |
| E1 | Home Screen coverage (screen 402×874 pt): 2 small + 2 medium = **46.9 %** of pixels; large + medium = **≈52 %** (largest measured). Theoretical incl. corners: L+M 52.7 %, 3M 49.1 %, 6S 46.1 %. Status bar, dock, search pill, labels and gaps stay Apple's. | PASS_SIMULATOR |
| E2 | One picture split across 4 widget instances (one widget *kind* per tile, because WidgetKit tells a widget nothing about its position): visually continuous except gaps/labels; **8/8 taps** routed to the right tile; tap in the gap between widgets: nothing happens. One tap → shared App Group state → **all 4 tiles re-rendered 85–290 ms after the intent**. | PASS_SIMULATOR |
| E5a | `containerBackground(Color.clear)` / `#00000000`: system draws an opaque white background → real transparency **FAIL** (default full-colour mode). | FAIL |
| E5b | Wallpaper crop (same screen position, taken from another page) + 8 drawn "icons" aligned to the real icon grid inside a medium widget: looks like icons, **8/8 taps** work; system border, corner mask and the "Agent Lab" label remain. Visual only – no extra area. | PASS_SIMULATOR |
| E5c | Wallpaper colour interpolated from pixels around the widget: approximate blend, visible edge. | PASS_SIMULATOR |
| E3a | Live Activities: **max 5 concurrent per app** (6th: "Maximum number of activities for target already exists"). | PASS_SIMULATOR |
| E3b | Dynamic Island: compact ≈159×36 pt (leading/trailing ≈10×22 pt each); expanded ≈**373×159 pt**, identical when 160 or 400 pt is requested → capped. One of our activities is shown at a time. | PASS_SIMULATOR |
| E3c | Lock Screen Live Activity view: 374 pt wide; content asking for 400 pt is clipped to ≈160 pt; several activities are stacked (one visible card). Exact pixel diff not finished. | PASS_SIMULATOR (partial) |
| B4 | iOS 26 widget long-press menu offers size switching ("Home-Bildschirm bearbeiten", size icons) – user-controlled. | PASS_SIMULATOR |
| Bug | Interpolated strings in `configurationDisplayName` crash the widget extension ("Formatted text … is not supported") → whole bundle disappears from the gallery. | PASS_SIMULATOR |

## Not done yet (next steps)
- Lock Screen: exact area diff, tap on Live Activity button while locked, lock-screen widgets (accessory families), Control widget in Control Center / Lock Screen (`SLControl` is implemented, not placed).
- Notification Content Extension (`NotificationLab`, full UIKit incl. scroll, text field, WKWebView): built, **not yet exercised**.
- StandBy (incl. full-screen Live Activity): not attempted; Simulator support unknown → likely `BLOCKED`.
- Other devices (iPhone 16e without Dynamic Island, Pro Max), accessibility/VoiceOver, colour modes, final comparison matrix and answers to the 10 questions.
- Simulator layout note: page 0 now holds Tile A/B, Apple's Maps/Calendar widgets (untouched) and an Agent Surface widget; page 1 holds tiles A–D. No Apple widget was removed.
