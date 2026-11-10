# Native iPhone widget lab

**Status (2026-11-10):** builds and runs in the iOS 26.3 Simulator; full experiment suite executed there
(see [`docs/RESULTS.md`](../docs/RESULTS.md)). **Not yet run on a physical iPhone** (blocked: Apple PLA, no device connection).

## What is in here
| Path | Purpose |
| --- | --- |
| `Shared/Schema.swift` | Universal declarative surface schema + validation |
| `Shared/Renderer.swift` | The one generic SwiftUI renderer (widget, Live Activity, in-app preview) |
| `Shared/Actions.swift` | Generic App Intents (widget / Live Activity), response processing, bridge client |
| `Shared/Store.swift` | App Group files: `surface.json`, `outbox.json`, `config.json`, `events.jsonl` (instrumentation) |
| `Shared/Presets.swift` | Synthetic fixtures (data only) |
| `Widget/AgentWidget.swift` | Timeline provider (pull-on-reload, scheduled entries, expiry), widget, iOS 26 push widget, Live Activity |
| `App/` | Lab app: presets, raw JSON, bridge config, Live Activity, notifications (text input), silent push, BG refresh, URL automation |
| `UITests/HomeScreenTests.swift` | Simulator automation of SpringBoard: add widgets, tap, measure |
| `../tools/` | `bridge.py` (agent stand-in), `agent_demo.py`, `lab.py`, `run_experiments.py`, `analyze.py` |

## Setup
```bash
brew install xcodegen
cd prototype
cat > Config/Local.xcconfig <<'EOF'   # gitignored
DEVELOPMENT_TEAM = <your team id>
AWL_APP_BUNDLE_ID = com.<you>.agentwidgetlab
EOF
xcodegen generate
```
The App Group is derived as `group.<AWL_APP_BUNDLE_ID>` (entitlements and runtime). Automatic signing with
`-allowProvisioningUpdates` registers IDs, App Group and Push. This requires an accepted, current Apple Program License Agreement.

**Keep DerivedData out of iCloud-synced folders** (codesign fails with "detritus not allowed"):
```bash
DD=~/Library/Developer/Xcode/DerivedData/AWL
xcodebuild -project AgentWidgetLab.xcodeproj -scheme AgentWidgetLab \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath $DD build
```

## Simulator experiment suite
```bash
python3 ../tools/bridge.py &                       # agent stand-in on :8787
xcodebuild test ... -only-testing:AgentWidgetLabUITests/HomeScreenTests/testA_AddWidgets   # once (German SpringBoard labels)
xcodebuild test ... -only-testing:AgentWidgetLabUITests/HomeScreenTests/testB_PublishToVisible \
                    -only-testing:AgentWidgetLabUITests/HomeScreenTests/testC_TapLatency
python3 ../tools/run_experiments.py E05 E10 E12 E04 E02   # host-side (needs Accessibility permission for Cmd+Shift+H)
python3 ../tools/agent_demo.py & xcodebuild test ... -only-testing:.../testH_RoundTrip
python3 ../tools/lab.py events                     # App Group event log
```

## Physical iPhone (next step)
1. Accept the PLA at developer.apple.com → Account.
2. Connect via USB once (university Wi-Fi isolates devices), enable Developer Mode, trust the Mac.
3. `xcodebuild -destination 'id=<udid>' -allowProvisioningUpdates build`, then install with `xcrun devicectl device install app`.
4. In the app: set the bridge URL to `http://<mac-ip>:8787` (same network or hotspot), allow notifications.
5. Add the widget manually; repeat E01/E03/E04/E06b/E07/C3, also with the phone **locked**. Export the log via the app's share button.
   UI tests can also drive SpringBoard on device, but the label strings depend on the device language.

## Lab-only shortcuts (not production behavior)
- `agentlab://…` URL commands for automation (in the Simulator, `simctl openurl` shows a confirmation dialog; UI tests use `XCUIApplication.open`).
- `sim-push-payload.json`: the Simulator delivers `content-available` pushes as payload-less background fetch, so `lab.py` drops the payload there.
- `NSAllowsArbitraryLoads` for the plain-HTTP bridge.
