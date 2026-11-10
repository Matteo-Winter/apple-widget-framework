# Agent surface schema v1

A **surface** is pure data. The widget extension maps each node `type` to a precompiled SwiftUI view
(`prototype/Shared/Renderer.swift`). No code is downloaded or executed.

## Surface

| Field | Type | Meaning |
| --- | --- | --- |
| `schema` | int, optional | Schema version (1) |
| `id` | string | Request / turn id; responses reference it |
| `agent` | string | Originating agent; used for routing and stale-update checks |
| `revision` | int | Monotonic per agent. Lower revisions are rejected; taps on an older revision are rejected |
| `issuedAt`, `expiresAt` | ISO-8601 | After `expiresAt`, actions are rejected and `expiredRoot` is shown (also as a scheduled timeline entry) |
| `root` | node | Default tree |
| `layouts` | {family: node} | Per-family override: `systemSmall`, `systemMedium`, `systemLarge`, `accessoryRectangular`, `accessoryInline`, `accessoryCircular`, `activity`, `island` |
| `onAction` | {actionId: node} | Optimistic tree shown right after a tap (applied inside the App Intent, no network) |
| `schedule` | [{at, root}] | Future trees, each becomes a timeline entry (≤ 60) |
| `expiredRoot` | node | Shown after expiry |
| `answeredAction`, `answeredAt` | set locally | Idempotency guard |

Bridge-only extension: `agentReplies` {actionId: surface}. The bridge returns it as `next` in the response to
`POST /response`, so the intent can render the agent's real follow-up immediately.

## Nodes

| `type` | Uses | Notes |
| --- | --- | --- |
| `vstack`, `hstack`, `zstack` | `children`, `spacing`, `alignment`, `padding` | |
| `text` | `text`, `style`, `weight`, `color`, `lineLimit` | styles: largeTitle, title, headline, body, callout, caption, footnote, mono |
| `symbol` | `symbol` (SF Symbol), `style`, `color` | |
| `image` | `imageData` (base64, ≤ 60 KB) | |
| `badge` | `text`, `background` | |
| `progress` | `value` 0…1 **or** `date`+`endDate` | the date form advances with system time, no updates |
| `gauge` | `value`, `text` | |
| `timer` | `date`, `endDate` | countdown that ticks without updates |
| `relative` | `date` | "2 min, 5 s ago", ticks without updates |
| `spacer`, `divider` | | |
| `button` | `text`, `symbol`, `action`, `prominent` | App Intent in widget, `LiveActivityIntent` in Live Activity. `action: "__pull"` = refresh from bridge. With `url`: opens the app (Link) |
| anything else | | ignored (forward compatible) |

Colors are semantic only: primary, secondary, accent, green, red, orange, blue, white, black.

## Validation limits (fail closed)
depth ≤ 8 · nodes ≤ 80 per tree · buttons ≤ 12 · text ≤ 600 chars · image ≤ 60 000 base64 chars · schedule ≤ 60.
Invalid surfaces render a "Schema rejected" card and log `surface_invalid`.

## Response envelope (POST /response)
```json
{"responseId":"uuid","surfaceId":"demo-decision-1","agent":"Coding Agent","revision":12,
 "action":"fix","text":null,"channel":"widget|activity|notification","createdAt":"…","deliveredAt":null}
```
Responses are stored in the App Group outbox first and retried by the app (launch / background wake) until acknowledged.
Production needs authentication, signed request ids and server-side idempotency (not implemented).
