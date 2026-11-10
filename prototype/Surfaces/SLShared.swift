import Foundation
import AppIntents
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

// SurfaceLab: experiments on how much screen area a third-party app can occupy
// outside its own app (Home Screen tiles, Live Activity / Dynamic Island,
// notification content extension, controls). Isolated from the agent renderer.
// Control file: App Group `surfacelab/spec.json`, written by tools/sl/*.py.

struct SLTile: Codable, Hashable {
    var image: String? = nil      // file in surfacelab/, drawn full bleed (aspect fill)
    var scene: String? = nil      // RLScene file in surfacelab/, drawn by Canvas
    var bg: String? = nil         // container background: "clear" | "#RRGGBB(AA)" | nil (system)
    var label: String? = nil      // optional big text (for identification)
}

struct SLSpec: Codable {
    var run: String
    /// Keyed by "<tile>-<family>" first, then "<tile>" (tile = A…F).
    var tiles: [String: SLTile] = [:]
    var regions: Bool? = nil
    var debug: Bool? = nil
    var selected: String? = nil
}

enum SLStore {
    static var dir: URL? {
        guard let d = Store.dir?.appendingPathComponent("surfacelab", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func url(_ n: String) -> URL? { dir?.appendingPathComponent(n) }
    static func spec() -> SLSpec? {
        guard let u = url("spec.json"), let d = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(SLSpec.self, from: d)
    }
    static func save(_ s: SLSpec) {
        guard let u = url("spec.json"), let d = try? JSONEncoder().encode(s) else { return }
        try? d.write(to: u, options: .atomic)
    }
    static func scene(_ n: String?) -> RLScene? {
        guard let n, let u = url(n), let d = try? Data(contentsOf: u) else { return nil }
        return RLScene.load(d)
    }
}

/// Tap on a tile region (tile-namespaced id).
struct SLHitIntent: AppIntent {
    static var title: LocalizedStringResource = "SurfaceLab hit"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false
    @Parameter(title: "Region") var region: String
    init() {}
    init(region: String) { self.region = region }
    func perform() async throws -> some IntentResult {
        Log.event("sl_hit", detail: "region=\(region)")
        if var s = SLStore.spec() { s.selected = region; SLStore.save(s) }
        WidgetCenter.shared.reloadAllTimelines()   // shared state → every tile re-renders
        return .result()
    }
}

/// Control Center / Lock Screen / Action button control (iOS 18+).
struct SLControlIntent: AppIntent {
    static var title: LocalizedStringResource = "SurfaceLab control"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false
    init() {}
    func perform() async throws -> some IntentResult {
        Log.event("sl_control")
        return .result()
    }
}

#if canImport(ActivityKit)
struct SLActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var label: String
        var color: String      // hex
        var rev: Int
        var h: Double? = nil   // requested height (pt) to probe system caps
    }
    var name: String
}

/// Button inside the measurement Live Activity (runs in the app process).
struct SLActivityTapIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "SurfaceLab activity tap"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false
    @Parameter(title: "Name") var name: String
    @Parameter(title: "Button") var button: String
    init() {}
    init(name: String, button: String) { self.name = name; self.button = button }
    func perform() async throws -> some IntentResult {
        Log.event("sl_la_tap", detail: "activity=\(name) button=\(button)")
        for a in Activity<SLActivityAttributes>.activities where a.attributes.name == name {
            var st = a.content.state; st.rev += 1; st.label = "tapped \(button)"
            await a.update(ActivityContent(state: st, staleDate: nil))
        }
        return .result()
    }
}
#endif
