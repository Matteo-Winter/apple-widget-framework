import AppIntents
import WidgetKit
import Foundation

struct NextCardIntent: AppIntent {
    static var title: LocalizedStringResource = "Next demo card"
    static var description = IntentDescription("Cycles the current widget content without opening the app.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        var payload = WidgetStore.load()
        payload.revision += 1
        payload.updatedAt = ISO8601DateFormatter().string(from: Date())
        payload.selectedOption = nil
        switch payload.kind {
        case "status":
            payload.kind = "choice"
            payload.title = "Agent needs a decision"
            payload.message = "Should I investigate the failed test?"
            payload.requestId = "demo-\(payload.revision)"
            payload.options = [
                ChoiceItem(id: "yes", label: "Investigate"),
                ChoiceItem(id: "no", label: "Stop")
            ]
        case "choice":
            payload.kind = "result"
            payload.title = "Report ready"
            payload.message = "Review complete. No external action was executed."
            payload.options = []
        default:
            payload.kind = "status"
            payload.title = "Research Agent"
            payload.message = "Analyzing 12 sources"
            payload.progress = 0.35
            payload.options = []
        }
        _ = WidgetStore.save(payload)
        WidgetCenter.shared.reloadTimelines(ofKind: "AgentWidget")
        return .result()
    }
}

struct ChooseOptionIntent: AppIntent {
    static var title: LocalizedStringResource = "Respond to agent"
    static var description = IntentDescription("Select one of the agent-defined options.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Request ID")
    var requestId: String

    @Parameter(title: "Option ID")
    var optionId: String

    init() {}

    init(requestId: String, optionId: String) {
        self.requestId = requestId
        self.optionId = optionId
    }

    func perform() async throws -> some IntentResult {
        var current = WidgetStore.load()
        // Fail closed: no stale card or unsupported option may be acknowledged.
        guard current.kind == "choice", current.requestId == requestId,
              current.selectedOption == nil,
              current.options.contains(where: { $0.id == optionId }) else {
            return .result()
        }
        current.selectedOption = optionId
        current.kind = "result"
        current.title = "Response captured"
        current.message = "Selected \(optionId). Demo only: no agent was contacted."
        current.options = []
        current.revision += 1
        current.updatedAt = ISO8601DateFormatter().string(from: Date())
        _ = WidgetStore.save(current)
        WidgetCenter.shared.reloadTimelines(ofKind: "AgentWidget")
        return .result()
    }
}
