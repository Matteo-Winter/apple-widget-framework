import Foundation

// MARK: - Universal declarative UI schema
//
// An agent sends DATA describing a tree of precompiled components. The widget
// extension never downloads or executes code: it only walks this tree and maps
// each `type` to a fixed SwiftUI view. Unknown types render as nothing, so old
// widget binaries degrade gracefully when agents use newer components.

struct UINode: Codable, Hashable {
    /// vstack | hstack | zstack | text | symbol | progress | gauge | timer |
    /// relative | spacer | divider | button | badge | row | image
    var type: String
    var children: [UINode]? = nil

    // Content
    var text: String? = nil
    var symbol: String? = nil          // SF Symbol name
    var value: Double? = nil           // progress / gauge 0...1
    var date: String? = nil            // ISO-8601, timer / relative / interval start
    var endDate: String? = nil         // ISO-8601, timer countdown target / interval end
    var imageData: String? = nil       // base64 PNG/JPEG (small, bounded)
    var action: String? = nil          // button: action id defined by the agent
    var url: String? = nil             // button: deep link (opens app) instead of intent

    // Style (semantic, never raw code)
    var style: String? = nil           // largeTitle|title|headline|body|callout|caption|footnote|mono
    var weight: String? = nil          // regular|medium|semibold|bold
    var color: String? = nil           // primary|secondary|accent|green|red|orange|blue|white|black
    var background: String? = nil      // same palette, used by badge/button/stack
    var spacing: Double? = nil
    var padding: Double? = nil
    var alignment: String? = nil       // leading|center|trailing
    var lineLimit: Int? = nil
    var prominent: Bool? = nil         // button: filled vs. outlined
    var families: [String]? = nil      // render only in these widget families
}

struct Surface: Codable, Hashable {
    var schema: Int? = 1   // optional: synthesized Decodable ignores defaults (found by E05)
    /// Stable id of the request/conversation turn this surface represents.
    var id: String
    /// Originating agent; used to route the response back.
    var agent: String
    /// Monotonic per agent; widget ignores stale (lower) revisions.
    var revision: Int
    var issuedAt: String? = nil
    /// After this instant actions are rejected and `expiredRoot` (or a generic card) shows.
    var expiresAt: String? = nil

    /// Default tree for every family.
    var root: UINode
    /// Optional per-family override: systemSmall, systemMedium, systemLarge,
    /// accessoryRectangular, accessoryInline, accessoryCircular, activity, island.
    var layouts: [String: UINode]? = nil

    /// Optimistic follow-up trees keyed by action id. Applied locally inside the
    /// App Intent so the widget changes right after the tap, without waiting
    /// for the network round trip to the agent.
    var onAction: [String: UINode]? = nil

    /// Pre-computed future trees. Each becomes a TimelineEntry, so iOS can switch
    /// layouts at known instants without waking the app or the network.
    var schedule: [ScheduledNode]? = nil

    var expiredRoot: UINode? = nil

    /// Filled in locally after the user acted (idempotency guard).
    var answeredAction: String? = nil
    var answeredAt: String? = nil
}

struct ScheduledNode: Codable, Hashable {
    var at: String
    var root: UINode
}

// MARK: - Validation (fail closed)

enum SchemaLimits {
    static let maxDepth = 8
    static let maxNodes = 80
    static let maxButtons = 12
    static let maxText = 600
    static let maxImageBase64 = 60_000
    static let maxSchedule = 60
}

enum SchemaError: Error, CustomStringConvertible {
    case decode(String), tooDeep, tooManyNodes(Int), tooManyButtons(Int), textTooLong, imageTooLarge, scheduleTooLong
    var description: String {
        switch self {
        case .decode(let s): return "decode: \(s)"
        case .tooDeep: return "tree deeper than \(SchemaLimits.maxDepth)"
        case .tooManyNodes(let n): return "\(n) nodes > \(SchemaLimits.maxNodes)"
        case .tooManyButtons(let n): return "\(n) buttons > \(SchemaLimits.maxButtons)"
        case .textTooLong: return "text > \(SchemaLimits.maxText) chars"
        case .imageTooLarge: return "image > \(SchemaLimits.maxImageBase64) base64 chars"
        case .scheduleTooLong: return "schedule > \(SchemaLimits.maxSchedule) entries"
        }
    }
}

extension UINode {
    func stats(depth: Int = 1) -> (depth: Int, nodes: Int, buttons: Int, maxText: Int, maxImage: Int) {
        var d = depth, n = 1, b = type == "button" ? 1 : 0
        var t = text?.count ?? 0, img = imageData?.count ?? 0
        for c in children ?? [] {
            let s = c.stats(depth: depth + 1)
            d = max(d, s.depth); n += s.nodes; b += s.buttons; t = max(t, s.maxText); img = max(img, s.maxImage)
        }
        return (d, n, b, t, img)
    }

    var actionIds: [String] {
        (type == "button" ? [action].compactMap { $0 } : []) + (children ?? []).flatMap { $0.actionIds }
    }
}

extension Surface {
    static func decode(_ data: Data) -> Result<Surface, SchemaError> {
        do {
            let s = try JSONDecoder().decode(Surface.self, from: data)
            try s.validate()
            return .success(s)
        } catch let e as SchemaError {
            return .failure(e)
        } catch {
            return .failure(.decode(String(describing: error).prefix(240).description))
        }
    }

    func validate() throws {
        var trees = [root] + Array((layouts ?? [:]).values) + Array((onAction ?? [:]).values)
        trees += (schedule ?? []).map(\.root)
        if let e = expiredRoot { trees.append(e) }
        if (schedule?.count ?? 0) > SchemaLimits.maxSchedule { throw SchemaError.scheduleTooLong }
        for t in trees {
            let s = t.stats()
            if s.depth > SchemaLimits.maxDepth { throw SchemaError.tooDeep }
            if s.nodes > SchemaLimits.maxNodes { throw SchemaError.tooManyNodes(s.nodes) }
            if s.buttons > SchemaLimits.maxButtons { throw SchemaError.tooManyButtons(s.buttons) }
            if s.maxText > SchemaLimits.maxText { throw SchemaError.textTooLong }
            if s.maxImage > SchemaLimits.maxImageBase64 { throw SchemaError.imageTooLarge }
        }
    }

    var isExpired: Bool {
        guard let e = expiresAt, let d = ISO.parse(e) else { return false }
        return d < Date()
    }

    func tree(for family: String) -> UINode {
        if isExpired {
            return expiredRoot ?? UINode(type: "vstack", children: [
                UINode(type: "badge", text: agent.uppercased()),
                UINode(type: "text", text: "Request expired", style: "headline"),
            ])
        }
        return layouts?[family] ?? root
    }
}

enum ISO {
    static func string(_ d: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }
    static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

enum WidgetKinds {
    static let surface = "AgentSurface"
    static let pushSurface = "AgentSurfacePush"
}
