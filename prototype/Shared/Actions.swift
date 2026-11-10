import AppIntents
import Foundation
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Bridge client (Mac-side tools/bridge.py stands in for "the agent")

enum Bridge {
    static func post(_ r: Store.Response, timeout: TimeInterval = 4) async -> (ok: Bool, next: Surface?) {
        let cfg = Store.config()
        guard cfg.postResponses, let url = URL(string: cfg.bridgeURL + "/response") else { return (false, nil) }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(r)
        let t0 = Date()
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                Log.event("bridge_post_http_error", detail: "\(ms)ms"); return (false, nil)
            }
            Store.markDelivered(r.responseId)
            var next: Surface?
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let s = obj["next"], let d = try? JSONSerialization.data(withJSONObject: s),
               case .success(let surf) = Surface.decode(d) { next = surf }
            Log.event("bridge_post_ok", rev: next?.revision, detail: "\(ms)ms next=\(next != nil)")
            return (true, next)
        } catch {
            Log.event("bridge_post_failed", detail: "\(Int(Date().timeIntervalSince(t0) * 1000))ms \(error.localizedDescription)")
            return (false, nil)
        }
    }

    /// Pull the agent's current surface. Used by the timeline provider (pull-on-reload),
    /// background pushes, background refresh and the in-widget refresh button.
    static func fetchSurface(timeout: TimeInterval = 4) async -> Surface? {
        guard let url = URL(string: Store.config().bridgeURL + "/surface") else { return nil }
        let t0 = Date()
        do {
            let (data, resp) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: timeout))
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { Log.event("bridge_fetch_http_error", detail: "\(ms)ms"); return nil }
            switch Surface.decode(data) {
            case .success(let s): Log.event("bridge_fetch_ok", rev: s.revision, detail: "\(ms)ms"); return s
            case .failure(let e): Log.event("bridge_fetch_invalid", detail: e.description); return nil
            }
        } catch {
            Log.event("bridge_fetch_failed", detail: "\(Int(Date().timeIntervalSince(t0) * 1000))ms \(error.localizedDescription)")
            return nil
        }
    }

    /// Retry undelivered responses (called from app launch / background wake).
    static func flushOutbox() async {
        for r in Store.outbox() where r.deliveredAt == nil { _ = await post(r) }
    }
}

// MARK: - Generic action processing (shared by widget, Live Activity, notifications)

enum ActionProcessor {
    @discardableResult
    static func handle(surfaceId: String, action: String, revision: Int, text: String? = nil, channel: String) async -> Bool {
        Log.event("action_received", rev: revision, detail: "\(channel) \(surfaceId)/\(action)")
        let current = Store.loadSurface()

        // Fail closed: stale card, replay, expired request or unknown action.
        let known = Set(([current.root] + Array((current.layouts ?? [:]).values)).flatMap { $0.actionIds })
        guard current.id == surfaceId, current.revision == revision,
              current.answeredAction == nil, !current.isExpired,
              known.contains(action) || channel == "notification" else {
            Log.event("action_rejected", rev: current.revision,
                      detail: "want \(surfaceId)#\(revision) have \(current.id)#\(current.revision) answered=\(current.answeredAction ?? "-")")
            return false
        }

        let response = Store.Response(
            responseId: UUID().uuidString, surfaceId: surfaceId, agent: current.agent, revision: revision,
            action: action, text: text, channel: channel, createdAt: ISO.string(), deliveredAt: nil)
        Store.appendResponse(response)

        // 1) Optimistic local transition — visible on the next render without any network.
        var next = current
        next.revision += 1
        next.answeredAction = action
        next.answeredAt = response.createdAt
        next.root = current.onAction?[action] ?? Presets.ack(agent: current.agent, label: text ?? action)
        next.layouts = nil
        next.schedule = nil
        Store.save(next, force: true)

        // 2) Return channel: deliver to the agent; it may answer synchronously with its real next UI.
        let (ok, agentNext) = await Bridge.post(response)
        if ok, let agentNext, agentNext.revision > next.revision || agentNext.id != next.id {
            Store.save(agentNext, force: true)
        }
        Log.event("action_done", rev: Store.loadSurface().revision, detail: "delivered=\(ok)")
        return true
    }
}

// MARK: - Widget App Intents

struct AgentActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Respond to agent"
    static var description = IntentDescription("Sends an agent-defined action from the widget.")
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    @Parameter(title: "Surface") var surfaceId: String
    @Parameter(title: "Action") var actionId: String
    @Parameter(title: "Revision") var revision: Int

    init() {}
    init(surfaceId: String, actionId: String, revision: Int) {
        self.surfaceId = surfaceId; self.actionId = actionId; self.revision = revision
    }

    func perform() async throws -> some IntentResult {
        await ActionProcessor.handle(surfaceId: surfaceId, action: actionId, revision: revision, channel: "widget")
        // No explicit reloadTimelines: Apple documents that the system reloads the
        // widget's timeline when perform() returns. Experiment E03 measures this.
        return .result()
    }
}

/// User-initiated pull: tap in the widget → fetch the agent's latest surface.
struct PullIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh agent surface"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false
    init() {}
    func perform() async throws -> some IntentResult {
        Log.event("pull_intent")
        if let s = await Bridge.fetchSurface() { Store.save(s) }
        return .result()
    }
}

/// Lab helper: cycle through presets entirely inside the widget.
struct NextPresetIntent: AppIntent {
    static var title: LocalizedStringResource = "Next preset"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false
    init() {}
    func perform() async throws -> some IntentResult {
        let cur = Store.loadSurface()
        let names = Presets.cycle
        let idx = (names.firstIndex(of: cur.id.components(separatedBy: "-").first ?? "") ?? -1) + 1
        var s = Presets.named(names[idx % names.count])
        s.revision = cur.revision + 1
        Store.save(s, force: true)
        Log.event("next_preset", rev: s.revision, detail: s.id)
        return .result()
    }
}

// MARK: - Live Activity

#if canImport(ActivityKit)
struct AgentActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var surface: Surface
        var sentAt: String
    }
    var agent: String
}

/// LiveActivityIntent runs in the app process (launched in background if needed),
/// so it can update the Activity directly.
struct AgentActivityActionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Respond to agent (Live Activity)"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    @Parameter(title: "Surface") var surfaceId: String
    @Parameter(title: "Action") var actionId: String
    @Parameter(title: "Revision") var revision: Int

    init() {}
    init(surfaceId: String, actionId: String, revision: Int) {
        self.surfaceId = surfaceId; self.actionId = actionId; self.revision = revision
    }

    func perform() async throws -> some IntentResult {
        await ActionProcessor.handle(surfaceId: surfaceId, action: actionId, revision: revision, channel: "activity")
        let s = Store.loadSurface()
        for a in Activity<AgentActivityAttributes>.activities {
            await a.update(ActivityContent(state: .init(surface: s, sentAt: ISO.string()), staleDate: nil))
        }
        Log.event("activity_updated_from_intent", rev: s.revision)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
#endif
