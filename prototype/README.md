# Native iPhone widget lab — setup and first experiments

**Current status:** source scaffold committed; **not yet compiled or tested on a physical iPhone**.

This is a minimal native SwiftUI app and WidgetKit extension. It demonstrates a **fixed installed widget rendering different declarative schemas**, not arbitrary downloaded executable code and not guaranteed server-side live refresh.

## Prerequisites
- A Mac with an Xcode release supporting iOS 17+ and a physical iPhone.
- An Apple development/signing team able to provision a matching App Group for the app and widget extension.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate an Xcode project from `project.yml` (e.g. `brew install xcodegen`).

## Prepare your bundle IDs and App Group
The included IDs are placeholders:
- app: `com.example.AgentWidgetLab`
- extension: `com.example.AgentWidgetLab.Widgets`
- App Group: `group.com.example.AgentWidgetLab`

Choose unique IDs available to your signing team and edit **all** these locations consistently:
1. `project.yml` app and extension bundle identifiers
2. `App/AgentWidgetLab.entitlements`
3. `Widget/AgentWidgetExtension.entitlements`
4. `Shared/WidgetModel.swift` `WidgetStore.groupId`

Configure your Apple Developer App Group and signing entitlements. Xcode may require explicit profile/team configuration. Do not commit secrets or provisioning profiles.

## Generate and run
From the repository root:

```bash
cd prototype
xcodegen generate
open AgentWidgetLab.xcodeproj
```

In Xcode:
1. Select the application scheme/target and your signing team.
2. Ensure the widget extension uses the same team and has its App Group entitlement.
3. Build and run on the **physical iPhone**. Fix any toolchain/provisioning issues before reporting a pass.
4. On the iPhone Home Screen, add the **Agent UI Lab** widget (medium size).
5. In the host app, edit the JSON body and press **Publish JSON**, first with reload enabled, then disabled.
6. On the Home Screen widget, tap the arrow button to cycle **status -> choice -> result**. On a choice card, tap a response to locally acknowledge it.
7. Collect evidence for the experiment log in `../docs/WIDGET_EXPERIMENTS.md`.

## First questions
- Does a JSON document that changes `kind` from `status` to `choice` produce a different component tree in the SAME installed widget?
- Is the visible change immediate after a **button action**?
- How long does an app-triggered `WidgetCenter.reloadTimelines` request take to show?
- Does shared-data write **without** a reload visibly change anything in the observation period?
- What happens after locking the phone, going offline, force closing the app, or leaving it in the background?

**Measure visible changes, not just the method return value.**

## Sample UI schema

```json
{
  "revision": 2,
  "requestId": "request-2",
  "kind": "choice",
  "title": "Agent needs your input",
  "message": "Choose the next step",
  "progress": 0.2,
  "options": [
    {"id": "test", "label": "Run tests"},
    {"id": "stop", "label": "Stop"}
  ],
  "updatedAt": "2026-11-10T10:00:00Z",
  "selectedOption": null
}
```

Only `status`, `choice`, and `result` are rendered in this scaffold. Widget actions are limited to two visible options. They **do not contact external agents**, process payments, modify files or issue real approvals.

## Important limitations

- This project intentionally tests only local App Group state sharing, timeline requests, and native widget App Intents. APNs push and Live Activity experiments are documented but **not yet implemented**.
- The widget has a 60-second timeline request for measurement, **not** a guaranteed one-minute refresh.
- App Group signing and widget intents must be tested on real hardware. A simulator pass is insufficient.
- The current choice acknowledgement is local proof of the response pathway. Production requires signed request IDs, expiry, idempotency, backend acknowledgement and secure agent transport.
- If the app-group write fails, the widget may show the static sample; treat this as a setup failure, not an experiment pass.
- For this first native POC use two choices. More complex interactions will require tested UI controls and possibly a transition into the app.
- This is intentionally not a complete agent platform, not a replacement for Apple's Home Screen, and not an App Store-ready app.

## Troubleshooting

- Widget does not appear: check extension target, WidgetKit extension Info.plist, deployment target and signing, then reinstall.
- Always shows the sample: verify BOTH targets use the exact same registered App Group ID and entitlements.
- Button doesn't respond: check App Intents compilation / target membership and iOS version.
- New JSON doesn't appear: check whether host app reported a save success; then inspect refresh trigger and WidgetKit logs.
- Compilation errors: record exact Xcode/SDK version and error in the experiment log before making assumptions.

## Next milestone

Once E01–E06 have been validated, add a remote JSON event sender and APNs WidgetKit push experiment, with precise send/receipt/display timestamps. Keep the remote agent bridge separate from the native renderer.
