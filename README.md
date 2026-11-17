# Agent-native iPhone UI Lab

**What if an AI agent could ask for a decision right on your iPhone Home Screen — without sending you back into another chat?**

This repository investigates a **shared mobile interface for independent AI agents**. An agent could send a status update, a choice or a completed result; an installed native widget would render the appropriate UI, and a user's response could eventually be routed back to that agent.

**Status: experimental SwiftUI / WidgetKit research prototype, not a shipping agent platform.** The code currently demonstrates local widget state and actions, *not* real agent connections or proven low-latency remote updates.

## The problem

AI agents increasingly work in separate tools and sessions. One may be running tests, another researching, and a third waiting for approval. If progress, errors and questions remain buried in separate chats, using several agents becomes surprisingly manual.

The long-term idea is not to replace Siri, Claude or ChatGPT. It is to **connect their workflows to a common, context-aware interaction surface**: a status view when work is ongoing, a decision card when human input is needed, and a short result when the task finishes. Home Screen widgets, notifications, Live Activities and Dynamic Island are potential surfaces — each with different Apple-defined limits.

## The technical question

**Can one preinstalled WidgetKit extension render different agent-defined interfaces through changing data, without shipping a new widget implementation for every use case?**

The approach is declarative: agents may describe supported layouts and actions as **data**. The device renders them using already compiled SwiftUI components. It does **not** download or execute arbitrary Swift or JavaScript.

### Conceptual flow (not yet an implemented end-to-end integration)

```text
Claude Code / Codex / another compatible agent
                    |
            events + UI schema
                    |
         [future authenticated bridge]
                    |
         native iOS rendering layer
                    |
    status   <->   choice   <->   result
                    |
         [future response routing]
                    |
               source agent
```

An eventual attention layer might choose *when* an agent interrupts, or consolidate several requests based on permissions and context. That layer remains a **product hypothesis**, not an implemented capability.

## What is in the repository today?

The [`prototype/`](prototype/) folder contains a minimal **native iOS host app and WidgetKit extension** built with SwiftUI, App Intents and an App Group.

| Component | Present in source | What it does |
| --- | --- | --- |
| Native widget | Yes | Renders `status`, `choice` and `result` layouts from a small, predefined schema |
| Host app | Yes | Lets a tester edit JSON and publish it into shared App Group storage |
| Widget actions | Yes | Switch between demo cards and acknowledge one of two visible choices through App Intents |
| Refresh experiment | Yes | Requests a timeline reload; actual display timing is controlled by iOS |
| External Claude/Codex integration | No | No real remote agent is contacted by the demo buttons |
| APNs WidgetKit push | No | Planned separately from local interaction tests |
| Live Activities / Dynamic Island | No | Research scope, not in the committed prototype |
| Agent management / prioritization | No | Longer-term hypothesis, not a validated feature |

**Important distinction:** The code is committed, but the repository's own experiment records do not establish a successful build, installation or controlled test on a physical iPhone. Treat the above as **implemented source paths**, not measured real-device performance. The widget refresh policy is a scheduling hint, not a promise of updates every five minutes or at any other fixed interval.

### Example UI payload

A compatible future sender might describe a question this way:

```json
{
  "revision": 2,
  "requestId": "demo-2",
  "kind": "choice",
  "title": "Tests need your input",
  "message": "Investigate the failure or stop?",
  "progress": 0.2,
  "options": [
    { "id": "investigate", "label": "Investigate" },
    { "id": "stop", "label": "Stop" }
  ],
  "updatedAt": "2026-11-10T10:00:00Z",
  "selectedOption": null
}
```

The supported schema is deliberately limited: only three `kind` values, bounded text and a maximum of two **visible** option buttons in the widget. This is a rendering and interaction experiment, not a universal remote UI or an approval mechanism for real-world operations.

## Run the native prototype

You need a **Mac with Xcode**, [XcodeGen](https://github.com/yonaskolb/XcodeGen), an iPhone or simulator for initial development, and correctly configured Apple signing/App Group capabilities for on-device testing.

```bash
git clone https://github.com/Matteo-Winter/apple-widget-framework.git
cd apple-widget-framework/prototype
xcodegen generate
open AgentWidgetLab.xcodeproj
```

Before building, replace the example bundle IDs and App Group identifier across `project.yml`, both entitlement files and `Shared/WidgetModel.swift`. Choose the signing team in Xcode. Then install the host app, add the **Agent UI Lab** widget to the Home Screen and test publishing `status`, `choice` and `result` JSON. Use the widget's arrow and option buttons to exercise the local App Intent flow.

**Full setup, prerequisites and troubleshooting:** [prototype/README.md](prototype/README.md).

A simulator is useful during development, but does **not** establish refresh reliability, interaction latency or resource limits on a real device.

## Research goals and constraints

This project is intentionally built around **falsifiable tests** rather than promises about iOS workarounds:

1. **Rendering flexibility:** Can one widget show materially different layouts without reinstalling it?
2. **Direct interactions:** Can a person respond through native widget controls without opening the host app?
3. **Visible-update reliability:** How long do app-initiated reloads, timeline updates and, later, push updates actually take?
4. **Practical limits:** What happens with malformed payloads, stale choices, locked screens or backgrounded apps?
5. **Safety:** How should an eventual authenticated agent response prevent stale, duplicated or unauthorized actions?

Apple controls WidgetKit refresh and the available UI surfaces. Widgets are not general-purpose embedded web apps: arbitrary downloaded code, unrestricted continuous updates, free-form text entry and replacement of the entire system Home Screen are **not supported design assumptions**.

## Research documentation

| Document | What you will find |
| --- | --- |
| [Project context](docs/PROJECT_CONTEXT.md) | Vision, initial users, architecture hypothesis and scope decisions |
| [iOS feasibility](docs/IOS_FEASIBILITY.md) | Apple API references, interaction possibilities and platform limitations |
| [Widget experiments](docs/WIDGET_EXPERIMENTS.md) | Proposed experiments, success criteria and evidence requirements |
| [Open questions](docs/OPEN_QUESTIONS.md) | Competitor context, market risks and validation questions |
| [Prototype instructions](prototype/README.md) | Local build, signing, sample JSON, test plan and troubleshooting |

## What comes next?

The immediate next step is **repeatable device-level evidence**: verify build/signing, measure layout and response changes in normal conditions, and document failures just as carefully as successes. Only then does it make sense to add a minimal authenticated bridge to a real agent and compare the experience with existing mobile-agent tools.

**This is public research code, not an App Store app or a production security reference.** Do not put real credentials, sensitive agent transcripts, personal location data or production approvals into the demo. No explicit software license is currently provided in this repository.
