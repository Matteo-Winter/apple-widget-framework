# iOS technical feasibility: testable claims, constraints, source links

Status: research hypotheses / documentation, **not device-verified**. Validate against the exact iOS and Xcode SDK installed on the test device.

## 1. Native WidgetKit is not a general webview/app runtime
- Widget extension and supported views are compiled into the app.
- A remote agent may send data / a component schema; the extension can render different precompiled SwiftUI branches or layouts.
- A new arbitrary Swift executable cannot be downloaded and run in a WidgetKit extension.
- Different layout/content != guaranteed instantaneous remote refresh.
- A third-party app owns widget positions it provides, **not** the system Home Screen or arbitrary other apps' widgets.

Sources: [WidgetKit](https://developer.apple.com/documentation/widgetkit), [WidgetKit TimelineProvider](https://developer.apple.com/documentation/widgetkit/timelineprovider), [App Review Guidelines 2.5.2](https://developer.apple.com/app-store/review/guidelines/).

## 2. Update paths to measure separately
| Path | Trigger | Key concern |
| --- | --- | --- |
| Shared App Group state + `WidgetCenter.reloadTimelines` | Foreground container app | Reload request is not proof of screen refresh |
| App Intent in widget | User presses widget Button | The system can re-render the affected widget after the intent; record measured latency |
| Timeline entries | Predicted future state | Useful for known dates/timers, not unpredictable external agent messages |
| WidgetKit push updates | APNs from backend (OS/SDK permitting) | Delivery and refresh budget are system-controlled; needs signing/backend |
| Live Activity updates | ActivityKit local or push | Better suited to an ongoing task, **not** a permanent widget refresh bypass |
| Native timer progress views | System time | Can appear to progress without server updates, but cannot reflect unknown agent progress |

Sources: [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date), [WidgetKit push notifications](https://developer.apple.com/documentation/widgetkit/updating-widgets-with-widgetkit-push-notifications), [App Intents](https://developer.apple.com/documentation/appintents), [ActivityKit](https://developer.apple.com/documentation/activitykit).

## 3. Interactions
- WidgetKit interactive buttons/toggles use App Intents; not arbitrary TextFields.
- Interactive notifications support category actions, including `UNTextInputNotificationAction`, subject to notification delivery and iOS presentation rules.
- A safe response needs a request ID, idempotency key, authorization, expiry, and backend/runtime acknowledgement.
- A button press means the user *requested* an action, not that the external agent completed it.

Sources: [Adding interactivity to widgets](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities), [UNTextInputNotificationAction](https://developer.apple.com/documentation/usernotifications/untextinputnotificationaction).

## 4. Agent connectivity
- Claude Code Hooks and Claude Agent SDK can expose events and certain request/response workflows.
- Codex app-server exposes JSON-RPC notifications and approval/user-input calls for managed sessions.
- MCP tools can permit explicit agent-originated UI messages, but do not automatically grant full access to closed consumer chat sessions.
- First iPhone experiment does not require any external agent/account. Use a controlled local JSON fixture, then a minimal mock sender.

Sources: [Claude Code hooks](https://code.claude.com/docs/en/hooks), [Claude Agent SDK](https://platform.claude.com/docs/en/agent-sdk/overview), [Codex app-server](https://developers.openai.com/codex/app-server/), [Model Context Protocol](https://modelcontextprotocol.io/).

## 5. Candidate improvements to test (not 'loopholes')
- Keep one widget installed; hot-swap **declarative content and layout**, not widget binary.
- Have a tiny fixed component vocabulary that can express status, choice, details and completed UI.
- Batch unimportant external events, and use high-quality interactive push for time-critical questions.
- Use widget App Intents for intentional user-triggered navigation and refresh.
- Use ActivityKit for genuine, bounded ongoing tasks and Dynamic Island.
- Use time-based native SwiftUI views for elapsed time rather than streaming text every second.
- Run tests in normal device conditions; avoid mistaking Developer Mode budget exemptions for production capability.

## 6. Device measurement rules
Record event created time, shared storage write time, reload request time, screenshot-observed update time, visibility (Home Screen, lock, StandBy), power mode, network state, OS version and whether Developer Mode is enabled.

No assumption that `WidgetCenter.reloadTimelines` forces instant refresh. Record failure, delay and stale-render cases.

## Validation status (2026-11-10)
Simulator results for dynamic layout switching, App Intent behavior, scheduled entries, background-push wake-ups, Live Activity intents and notification text input are in [RESULTS.md](RESULTS.md). The list below is still open **on device**.

## Not yet validated on device
- Real device iOS refresh rates / percentiles
- Dynamic layout switching in compiled widget
- App Intent response behavior while locked
- WidgetKit push setup and reliability
- Dynamic Island prioritization
- App Store acceptance
