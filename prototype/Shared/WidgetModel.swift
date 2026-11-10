import Foundation

// A deliberately small, declarative "agent UI" vocabulary.
// The agent supplies DATA and COMPONENT CHOICES, never downloaded executable code.
struct ChoiceItem: Codable, Hashable, Identifiable {
    let id: String
    let label: String
}

struct WidgetPayload: Codable {
    var revision: Int
    var requestId: String
    var kind: String // status | choice | result
    var title: String
    var message: String
    var progress: Double
    var options: [ChoiceItem]
    var updatedAt: String
    var selectedOption: String?

    static let sample = WidgetPayload(
        revision: 1, requestId: "demo-1", kind: "status",
        title: "Research Agent", message: "Analyzing 12 sources", progress: 0.35,
        options: [], updatedAt: ISO8601DateFormatter().string(from: Date()),
        selectedOption: nil
    )
}

enum WidgetStore {
    // Change for your own signing team. The same App Group must be enabled on
    // both application and widget-extension targets in Apple Developer/Xcode.
    static let groupId = "group.com.example.AgentWidgetLab"
    static let key = "currentAgentWidgetPayload"
    static let acceptedKey = "lastAcceptedResponse"

    static func load() -> WidgetPayload {
        guard let store = UserDefaults(suiteName: groupId),
              let data = store.data(forKey: key),
              let value = try? JSONDecoder().decode(WidgetPayload.self, from: data) else {
            return .sample
        }
        return value
    }

    @discardableResult
    static func save(_ payload: WidgetPayload) -> Bool {
        guard let store = UserDefaults(suiteName: groupId),
              let data = try? JSONEncoder().encode(payload) else { return false }
        store.set(data, forKey: key)
        return true
    }

    static func formattedJSON(_ payload: WidgetPayload) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    static func parse(_ json: String) -> WidgetPayload? {
        guard let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(WidgetPayload.self, from: data),
              ["status", "choice", "result"].contains(value.kind),
              value.title.count <= 160, value.message.count <= 800,
              value.options.count <= 3,
              value.options.allSatisfy({ $0.label.count <= 80 }),
              value.progress.isFinite else { return nil }
        return value
    }
}
