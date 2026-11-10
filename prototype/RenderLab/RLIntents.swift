import AppIntents
import WidgetKit

/// One intent for every agent-defined hit region. The region id (namespaced
/// "agent:region" in multi-agent layouts) is the only thing the intent needs to
/// route the interaction; no per-agent code exists in the binary.
struct RLHitIntent: AppIntent {
    static var title: LocalizedStringResource = "RenderLab hit"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    @Parameter(title: "Region") var region: String
    @Parameter(title: "Agent") var agent: String
    @Parameter(title: "Run") var run: String

    init() {}
    init(region: String, agent: String, run: String) { self.region = region; self.agent = agent; self.run = run }

    func perform() async throws -> some IntentResult {
        Log.event("rl_hit", detail: "run=\(run) agent=\(agent) region=\(region)")
        if var s = RLStore.spec() {
            s.selected = region
            s.hits = (s.hits ?? 0) + 1
            RLStore.save(s)
        }
        return .result()
    }
}

/// In-widget navigation without scrolling: page through agent-provided scenes.
struct RLPageIntent: AppIntent {
    static var title: LocalizedStringResource = "RenderLab page"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    @Parameter(title: "Delta") var delta: Int
    init() {}
    init(delta: Int) { self.delta = delta }

    func perform() async throws -> some IntentResult {
        if var s = RLStore.spec() {
            s.page = max(0, (s.page ?? 0) + delta)
            RLStore.save(s)
            Log.event("rl_page", detail: "run=\(s.run) page=\(s.page ?? 0)")
        }
        return .result()
    }
}
