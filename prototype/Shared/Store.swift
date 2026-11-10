import Foundation
import os

// Shared App Group storage. Plain files (not UserDefaults) so that the Mac-side
// tools can read/write the exact same files in the simulator container, and so
// that every process sees the latest bytes without cross-process caching.

enum Store {
    /// group.<app bundle id>; derived at runtime so no ID is hard-coded.
    static var groupId: String {
        var id = Bundle.main.bundleIdentifier ?? "com.example.AgentWidgetLab"
        for suffix in [".Widgets", ".UITests.xctrunner", ".UITests"] where id.hasSuffix(suffix) {
            id = String(id.dropLast(suffix.count))
        }
        return "group." + id
    }

    static var dir: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupId)
    }

    static var process: String {
        let id = Bundle.main.bundleIdentifier ?? ""
        return id.hasSuffix(".Widgets") ? "ext" : "app"
    }

    private static func url(_ name: String) -> URL? { dir?.appendingPathComponent(name) }

    // MARK: Surface

    static func loadSurface() -> Surface {
        guard let u = url("surface.json"), let data = try? Data(contentsOf: u) else { return Presets.status }
        switch Surface.decode(data) {
        case .success(let s): return s
        case .failure(let e):
            Log.event("surface_invalid", detail: e.description)
            return Presets.invalid(e.description)
        }
    }

    /// Saves only if `surface.revision` is >= stored revision (stale-update guard).
    @discardableResult
    static func save(_ surface: Surface, force: Bool = false) -> Bool {
        guard let u = url("surface.json") else { Log.event("save_failed", detail: "no app group container"); return false }
        if !force, let old = try? Data(contentsOf: u), case .success(let cur) = Surface.decode(old),
           cur.agent == surface.agent, surface.revision < cur.revision {
            Log.event("save_rejected_stale", rev: surface.revision, detail: "current \(cur.revision)")
            return false
        }
        do {
            let data = try JSONEncoder().encode(surface)
            try data.write(to: u, options: .atomic)
            Log.event("surface_saved", rev: surface.revision, detail: surface.id)
            return true
        } catch {
            Log.event("save_failed", detail: error.localizedDescription)
            return false
        }
    }

    // MARK: Config

    struct Config: Codable {
        var bridgeURL: String = "http://127.0.0.1:8787"
        var pullOnReload: Bool = false
        var postResponses: Bool = true
    }

    static func config() -> Config {
        guard let u = url("config.json"), let d = try? Data(contentsOf: u),
              let c = try? JSONDecoder().decode(Config.self, from: d) else { return Config() }
        return c
    }

    static func saveConfig(_ c: Config) {
        guard let u = url("config.json"), let d = try? JSONEncoder().encode(c) else { return }
        try? d.write(to: u, options: .atomic)
    }

    // MARK: Outbox (response back-channel, durable until acknowledged)

    struct Response: Codable, Hashable {
        var responseId: String
        var surfaceId: String
        var agent: String
        var revision: Int
        var action: String
        var text: String?
        var channel: String        // widget | activity | notification | app
        var createdAt: String
        var deliveredAt: String?
    }

    static func outbox() -> [Response] {
        guard let u = url("outbox.json"), let d = try? Data(contentsOf: u) else { return [] }
        return (try? JSONDecoder().decode([Response].self, from: d)) ?? []
    }

    static func saveOutbox(_ items: [Response]) {
        guard let u = url("outbox.json"), let d = try? JSONEncoder().encode(Array(items.suffix(200))) else { return }
        try? d.write(to: u, options: .atomic)
    }

    static func appendResponse(_ r: Response) {
        var all = outbox(); all.append(r); saveOutbox(all)
    }

    static func markDelivered(_ id: String) {
        var all = outbox()
        if let i = all.firstIndex(where: { $0.responseId == id }) { all[i].deliveredAt = ISO.string() }
        saveOutbox(all)
    }

    // MARK: Push tokens (written by app / widget push handler for Mac tools)

    static func saveToken(_ name: String, _ token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        guard let u = url("token-\(name).txt") else { return }
        try? hex.write(to: u, atomically: true, encoding: .utf8)
        Log.event("token", detail: "\(name) \(hex.prefix(12))…")
    }
}

// MARK: - Instrumentation

/// Append-only JSON-lines log in the App Group: one line per event with a
/// millisecond epoch timestamp and the emitting process. Mac tools read it from
/// the simulator container (or the app shows/exports it on device) to compute
/// latencies such as publish → getTimeline → visible.
enum Log {
    private static let logger = Logger(subsystem: "AgentWidgetLab", category: "lab")

    static func event(_ name: String, rev: Int? = nil, detail: String = "") {
        let ms = Int64(Date().timeIntervalSince1970 * 1000)
        var obj: [String: Any] = ["t": ms, "p": Store.process, "e": name]
        if let rev { obj["rev"] = rev }
        if !detail.isEmpty { obj["d"] = detail }
        logger.log("\(name, privacy: .public) rev=\(rev ?? -1) \(detail, privacy: .public)")
        guard let dir = Store.dir,
              let line = try? JSONSerialization.data(withJSONObject: obj) else { return }
        // One write(2) with O_APPEND per line: atomic w.r.t. other processes
        // (app, widget extension) appending to the same file.
        var data = line; data.append(0x0a)
        let path = dir.appendingPathComponent("events.jsonl").path
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        close(fd)
    }

    static func tail(_ n: Int = 300) -> [String] {
        guard let u = Store.dir?.appendingPathComponent("events.jsonl"),
              let s = try? String(contentsOf: u, encoding: .utf8) else { return [] }
        return Array(s.split(separator: "\n").suffix(n).map(String.init).reversed())
    }

    static func clear() {
        guard let u = Store.dir?.appendingPathComponent("events.jsonl") else { return }
        try? FileManager.default.removeItem(at: u)
    }
}
