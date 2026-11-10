# Project context — captured from START Vienna discussions

Last updated: 2026-11-10. This is a faithful project brief, **not** a verbatim transcript.

## One-sentence vision
**An adaptive, agent-native interaction layer for smartphones:** independent agents render their own safe dynamic UIs within preinstalled widget surfaces, and users can act without constantly opening agent chats.

## User problem
- Information and requests are scattered across apps, chats and notifications.
- AI agents may operate in the background and stall on unanswered questions.
- As independent agents multiply, users may receive too many simultaneous interruptions and lose track of what matters.
- Changing context (desktop active vs away, focus, next calendar event) should change *when and where* an agent addresses the user.

## What is distinctive in the intended design
- The developer of the platform does **not** implement an interface for every use case. Third-party agents publish declarative component trees and actions.
- A fixed iOS widget is a **rendering frame**; its content and supported layout can change as the agent sends new schemas.
- Answers (yes/no, choices, approvals) should return to the initiating agent with an authenticated, session-specific transaction ID.
- Widgets, push action notifications, Live Activities and Dynamic Island are complementary presentation channels.
- A possible attention engine selects relevant interactions rather than broadcasting everything.
- A regular calendar view could become an agent question and then revert to the calendar, with no new widget installation.
- The product is **not** intended to become another Siri/ChatGPT replacement, create proprietary agents, or sell custom-built agents.

## First user and longer-term users
- Today: developers, founders and AI power users with multiple independent coding/research agents.
- Future hypothesis: everyday consumers with agents for personal logistics, email, calendar, shopping, travel etc.
- The team explicitly recognizes that future adoption may be too early for mass-market monetization.

## Proposed business model (unvalidated)
- Free agent hub / basic UI rendering and interactions.
- Potential paid Personal Agent Manager for attention ranking, user-context-based presentation, cross-agent summaries / coordination.
- Indicative consumer pricing discussed: ~EUR 5/month initially, and ~EUR 9.99–14.99/month for richer manager capabilities. **No proven willingness to pay.**
- Do **not** pivot this project into a B2B notifications platform without a separate product decision.

## Real competitive and strategic concerns
- Glance supports agent-driven dynamic widget layouts (UI on Demand); dynamic layouts are not unique.
- Agent HUD, Nomo and other coding-agent apps already provide status, remote control and mobile approvals.
- Some tools already suppress redundant notifications when the user is on the desktop.
- iOS controls widget refresh timing and available system surfaces.
- Apple/Google could implement large portions of the interaction layer.
- If most consumers use one closed assistant rather than many independent agents, a paid cross-agent manager may have insufficient demand.
- Proving dynamic UI technical feasibility is not the same as proving commercial differentiation.

## Architecture hypothesis
Agent SDK/MCP/Claude Code hooks/Codex app-server -> normalized events -> permissions & attention decision -> declarative UI state -> native iOS renderer -> response envelope -> originating agent.
A future context broker could share a small, permissioned, purpose-limited view of user context rather than full raw location/calendar.

## Decisions made
1. **Do the physical iPhone experiments before building the platform.**
2. Keep experiments evidence-driven and distinguish supported mechanisms from unverified workarounds.
3. Avoid undocumented background-execution tricks and forbidden app behavior.
4. No arbitrary Swift/JavaScript execution in widget extensions.
5. Prioritize the mobile UI render/update/response mechanism, before production agent connectors and billing.
6. Preserve traceable findings and negative results in GitHub.

## Questions for further validation
- Can a single widget dynamically switch between materially different component arrangements on device?
- What is the latency distribution of app-triggered, AppIntent-triggered, timeline, and WidgetKit push updates?
- Which interactivity is available directly in widgets vs notification actions vs full app?
- How well can foreground desktop presence avoid unnecessary mobile interruptions?
- What differentiated value remains versus Glance/Agent HUD?
- Will target users pay EUR 5/month for benefits not already supplied by those competitors?

## What must NOT be claimed
- That any prototype has already been installed and tested on physical iPhone.
- That an app can replace the whole iOS Home Screen.
- That every existing ChatGPT / Claude chat can be monitored or remotely resumed.
- That WidgetKit supports unrestricted per-second live refresh.
- That the premium agent manager or business model has been validated.
