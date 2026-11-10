import Foundation

// Synthetic fixtures. Every preset is pure data rendered by the same generic
// renderer — none of them has dedicated SwiftUI code.

private func T(_ s: String, _ style: String = "body", color: String? = nil, weight: String? = nil, lines: Int? = nil) -> UINode {
    UINode(type: "text", text: s, style: style, weight: weight, color: color, lineLimit: lines)
}
private func V(_ c: [UINode], spacing: Double = 6, align: String = "leading") -> UINode {
    UINode(type: "vstack", children: c, spacing: spacing, alignment: align)
}
private func H(_ c: [UINode], spacing: Double = 6) -> UINode { UINode(type: "hstack", children: c, spacing: spacing) }
private func B(_ label: String, _ action: String, prominent: Bool = false, symbol: String? = nil) -> UINode {
    UINode(type: "button", text: label, symbol: symbol, action: action, prominent: prominent)
}
private func header(_ agent: String, _ badge: String, symbol: String) -> UINode {
    H([UINode(type: "symbol", symbol: symbol, style: "caption"),
       T(agent.uppercased(), "caption", color: "secondary", weight: "semibold", lines: 1),
       UINode(type: "spacer"),
       UINode(type: "badge", text: badge)])
}

enum Presets {
    static let cycle = ["status", "decision", "decision4", "grid8", "list", "timer", "calendar"]

    static func named(_ n: String) -> Surface {
        switch n {
        case "decision": return decision
        case "decision4": return decision4
        case "grid8": return grid8
        case "list": return list
        case "timer": return timer()
        case "calendar": return calendar
        case "scheduled": return scheduled()
        default: return status
        }
    }

    static var status: Surface {
        Surface(id: "status-1", agent: "Research Agent", revision: 1, issuedAt: ISO.string(),
                root: V([header("Research Agent", "RUNNING", symbol: "circle.dotted"),
                         T("Analyzing 12 sources", "headline", lines: 2),
                         T("Step 3 of 5 · literature review", "caption", color: "secondary"),
                         UINode(type: "spacer"),
                         UINode(type: "progress", value: 0.42)]),
                layouts: ["accessoryRectangular": V([T("Research Agent", "caption", weight: "semibold"),
                                                     UINode(type: "progress", value: 0.42)], spacing: 2),
                          "accessoryInline": T("Research 42%")])
    }

    static var decision: Surface {
        Surface(id: "decision-1", agent: "Coding Agent", revision: 1, issuedAt: ISO.string(),
                expiresAt: ISO.string(Date().addingTimeInterval(3600)),
                root: V([header("Coding Agent", "NEEDS INPUT", symbol: "questionmark.circle"),
                         T("3 tests failed after refactor", "headline", lines: 2),
                         T("Should I investigate or revert?", "caption", color: "secondary", lines: 2),
                         UINode(type: "spacer"),
                         H([B("Investigate", "investigate", prominent: true), B("Revert", "revert")])]),
                onAction: [
                    "investigate": V([header("Coding Agent", "SENT", symbol: "checkmark.circle"),
                                      T("Investigating failures", "headline"),
                                      UINode(type: "relative", date: ISO.string(), style: "caption", color: "secondary")]),
                    "revert": V([header("Coding Agent", "SENT", symbol: "arrow.uturn.backward"),
                                 T("Reverting refactor", "headline")]),
                ])
    }

    static var decision4: Surface {
        Surface(id: "decision4-1", agent: "Travel Agent", revision: 1, issuedAt: ISO.string(),
                root: V([header("Travel Agent", "CHOOSE", symbol: "airplane"),
                         T("Pick a flight to Berlin", "headline"),
                         H([B("07:05", "f1", prominent: true), B("09:40", "f2")]),
                         H([B("13:15", "f3"), B("18:50", "f4")])], spacing: 6))
    }

    static var grid8: Surface {
        let rows = stride(from: 0, to: 8, by: 4).map { r in
            H((0..<4).map { i in B("\(r + i + 1)", "opt\(r + i + 1)") }, spacing: 4)
        }
        return Surface(id: "grid8-1", agent: "Survey Agent", revision: 1, issuedAt: ISO.string(),
                       root: V([header("Survey Agent", "RATE", symbol: "number"),
                                T("How focused was this session?", "callout", weight: "semibold")] + rows, spacing: 4))
    }

    static var list: Surface {
        let items = [("Invoice #2231", "Approve"), ("PR #418 review", "Open"), ("Flight check-in", "Do")]
        return Surface(id: "list-1", agent: "Inbox Agent", revision: 1, issuedAt: ISO.string(),
                       root: V([header("Inbox Agent", "3 ITEMS", symbol: "tray")] +
                               items.enumerated().map { i, it in
                                   H([T(it.0, "callout", lines: 1), UINode(type: "spacer"), B(it.1, "item\(i)")])
                               } + [UINode(type: "divider"),
                                    H([UINode(type: "spacer"), UINode(type: "button", text: "Refresh", symbol: "arrow.clockwise", action: "__pull")])]))
    }

    /// Time-based rendering: the countdown and relative text keep moving with zero updates.
    static func timer(seconds: Double = 600) -> Surface {
        let start = Date(), end = start.addingTimeInterval(seconds)
        return Surface(id: "timer-1", agent: "Build Agent", revision: 1, issuedAt: ISO.string(),
                       root: V([header("Build Agent", "ETA", symbol: "hammer"),
                                T("Release build running", "headline"),
                                UINode(type: "timer", date: ISO.string(start), endDate: ISO.string(end), style: "title", weight: "semibold"),
                                UINode(type: "progress", date: ISO.string(start), endDate: ISO.string(end))]))
    }

    static var calendar: Surface {
        Surface(id: "calendar-1", agent: "Calendar", revision: 1, issuedAt: ISO.string(),
                root: V([header("Calendar", "TODAY", symbol: "calendar"),
                         H([T("10:00", "caption", color: "secondary"), T("Design review", "callout", weight: "semibold")]),
                         H([T("13:30", "caption", color: "secondary"), T("Investor call", "callout", weight: "semibold")]),
                         H([T("17:00", "caption", color: "secondary"), T("Gym", "callout", weight: "semibold")])]))
    }

    /// Pre-scheduled layouts: one surface, several future trees, zero further updates.
    static func scheduled(step: TimeInterval = 60) -> Surface {
        let now = Date()
        let steps = ["Queued", "Compiling", "Testing", "Uploading", "Done"]
        var s = Surface(id: "scheduled-1", agent: "Deploy Agent", revision: 1, issuedAt: ISO.string(),
                        root: V([header("Deploy Agent", "PLAN", symbol: "clock"), T("Waiting to start", "headline")]))
        s.schedule = steps.enumerated().map { i, name in
            ScheduledNode(at: ISO.string(now.addingTimeInterval(step * Double(i + 1))),
                          root: V([header("Deploy Agent", "STEP \(i + 1)/\(steps.count)", symbol: "clock"),
                                   T(name, "title", weight: "bold"),
                                   T("scheduled for " + ISO.string(now.addingTimeInterval(step * Double(i + 1))).suffix(13).prefix(8), "caption", color: "secondary"),
                                   UINode(type: "progress", value: Double(i + 1) / Double(steps.count))]))
        }
        return s
    }

    static func ack(agent: String, label: String) -> UINode {
        V([header(agent, "SENT", symbol: "checkmark.circle"),
           T("Response: \(label)", "headline", lines: 2),
           T("Waiting for agent…", "caption", color: "secondary")])
    }

    static func invalid(_ reason: String) -> Surface {
        Surface(id: "invalid", agent: "Lab", revision: 0,
                root: V([header("Lab", "INVALID", symbol: "exclamationmark.triangle"),
                         T("Schema rejected", "headline"), T(reason, "caption", color: "secondary", lines: 3)]))
    }
}
