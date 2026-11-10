import Foundation
import WidgetKit

// RenderLab experiment control. The host (tools/rl.py) writes `renderlab/spec.json`
// plus scene / bitmap / pdf / font files into the App Group, then triggers a reload.
// The RenderLab widget renders exactly what the spec asks for, with one technique,
// so all techniques are compared on identical input.

struct RLPane: Codable, Hashable {
    var agent: String
    var technique: String          // canvas | cg | bitmap | json | views
    /// Normalized frame inside the widget (0…1).
    var x: Double, y: Double, w: Double, h: Double
    var scene: String? = nil
    var bitmap: String? = nil
    var surfaceFile: String? = nil
}

struct RLSpec: Codable {
    var run: String
    /// json | views | canvas | cg | bitmap | pdf | charts | uiview | svg | font | coreimage | multi | blank
    var technique: String
    var scene: String? = nil
    var bitmap: String? = nil
    var pdf: String? = nil
    var surfaceFile: String? = nil
    var bypassLimits: Bool? = nil
    var regions: Bool? = nil           // add transparent native hit overlay from scene.regions
    var debugRegions: Bool? = nil      // outline the regions (lab only)
    var hitStyle: String? = nil        // clear | faint
    var cgScale: Double? = nil         // in-extension CG render scale (× display scale)
    var fontFile: String? = nil
    var fontName: String? = nil
    var panes: [RLPane]? = nil
    var padding: Double? = nil         // emulate default content margins (we disable them)
    var fill: Bool? = nil              // bitmap: aspect fill instead of fit
    var background: String? = nil      // container background hex; nil = system background
    // written by intents
    var selected: String? = nil
    var hits: Int? = nil
    var page: Int? = nil
}

enum RLStore {
    static var dir: URL? {
        guard let d = Store.dir?.appendingPathComponent("renderlab", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func url(_ name: String) -> URL? { dir?.appendingPathComponent(name) }

    static func spec() -> RLSpec? {
        guard let u = url("spec.json"), let d = try? Data(contentsOf: u) else { return nil }
        do { return try JSONDecoder().decode(RLSpec.self, from: d) }
        catch { Log.event("rl_spec_invalid", detail: String(describing: error).prefix(200).description); return nil }
    }

    static func save(_ s: RLSpec) {
        guard let u = url("spec.json"), let d = try? JSONEncoder().encode(s) else { return }
        try? d.write(to: u, options: .atomic)
    }

    static func data(_ name: String?) -> Data? {
        guard let n = name, let u = url(n) else { return nil }
        return try? Data(contentsOf: u)
    }

    static func scene(_ name: String?) -> RLScene? { data(name).flatMap(RLScene.load) }
}

enum RLMetrics {
    /// Physical memory footprint of the current process in MB (what jetsam limits use on device).
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    static func ms(since t: Date) -> Double { (Date().timeIntervalSince(t) * 10000).rounded() / 10 }
}

enum RLKind { static let widget = "RenderLab" }
