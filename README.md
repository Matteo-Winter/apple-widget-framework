# Apple Widget Framework — Agent-native iPhone UI Lab

**Status (November 2026): experimental research / prototype. Not a validated startup product.**

## Why this repository exists

We are investigating whether an iPhone can become a **universal, adaptive interaction surface for independent AI agents**. The phone should show relevant information and decisions where they matter — in an existing Home Screen widget, a Live Activity / Dynamic Island, or a notification — without requiring the user to repeatedly open different agent chats.

**Core principle:** we do **not** build the agents or pre-build an interface for every task. A compatible agent sends a declarative description of its content, layout, available actions and lifecycle. Our framework renders that within safe, preinstalled native UI components, then sends user decisions back to the right agent.

A longer-term optional *attention layer* could rank and schedule interactions across agents using permissioned context (e.g., desktop availability, calendar, location). This is a **hypothesis**, not the first thing to build.

## Immediate priority: test actual iOS limitations

**Before building accounts, an agent platform, a backend, or a business model, test how far native iPhone widgets can be pushed on a real device.**

The specific hypothesis to challenge: `can a fixed WidgetKit extension display radically different agent-defined content on demand without constantly rebuilding/installing the widget?`

- **Layout changes** within a preinstalled SwiftUI component vocabulary: possible in principle.
- **Visible changes at an arbitrary instant** without user interaction: **not guaranteed** by iOS. WidgetKit controls refresh. New WidgetKit push updates are opportunistic and budgeted.
- **Widget button/toggle:** Apple documents an automatic timeline reload after an App Intent completes.
- **Live Activity:** a distinct update mechanism for ongoing, time-limited activities; also subject to system constraints.
- **Arbitrary downloaded code, fake persistent background activity or bypassing Apple sandbox:** **out of scope**.

The first experiments measure native behavior — we will not claim a bypass without repeatable results on a non-developer-mode physical device.

## Documents

- [Project vision, constraints, and chat-derived decisions](docs/PROJECT_CONTEXT.md)
- [Technology & Apple API evidence](docs/IOS_FEASIBILITY.md)
- [Experiment plan and success criteria](docs/WIDGET_EXPERIMENTS.md)
- [Questions, market risks and competitor map](docs/OPEN_QUESTIONS.md)
- [iPhone lab setup](prototype/README.md)

## Build/test order

1. Install a minimal native widget extension on an **actual iPhone**.
2. Switch between status, choice and summary *layouts* using shared JSON, with and without requesting a timeline refresh.
3. Test a button-driven App Intent updating the same widget **without launching the app**.
4. Measure timeline-based scheduled changes; compare behavior with normal/developer WidgetKit modes.
5. Compare to local Live Activity updates. **Then** add APNs WidgetKit pushes and remote agent messages in a separate milestone.
6. Integrate one real agent only after the iOS rendering and response-path tests.

## Non-goals for this phase

No replacement for the system Home Screen, no scraping other apps, no universal access to ChatGPT/Claude conversation sessions, no promised sub-second widget streaming, no business-plan-driven scope expansion.

## Security

The repository is public. Do not commit API keys, provisioning profiles, certificates, APNs keys, user locations or real agent data. Initial fixtures are synthetic.

## References

See [iOS feasibility notes](docs/IOS_FEASIBILITY.md) for Apple documentation and limits.
