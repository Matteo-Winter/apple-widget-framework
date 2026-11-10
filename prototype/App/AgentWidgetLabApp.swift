import SwiftUI
import WidgetKit

@main
struct AgentWidgetLabApp: App {
    var body: some Scene {
        WindowGroup {
            LabView()
        }
    }
}

struct LabView: View {
    @State private var jsonText = WidgetStore.formattedJSON(WidgetStore.load())
    @State private var message = "Ready. Publish different schemas to the same installed widget."
    @State private var doReload = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Experiment: same widget, changing layout") {
                    Text("Edit this declarative JSON and publish. The widget can show status, choice or result layouts without changing installed widget code.")
                        .font(.footnote)
                    TextEditor(text: $jsonText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 310)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Toggle("Request WidgetCenter reload", isOn: $doReload)
                    Button("Publish JSON") { publish() }
                        .buttonStyle(.borderedProminent)
                    Button("Load status / choice / result demo") {
                        let existing = WidgetStore.load()
                        jsonText = WidgetStore.formattedJSON(existing)
                        message = "For direct widget interaction, tap the next arrow in the widget."
                    }
                }
                Section("Last result") {
                    Text(message).font(.footnote)
                    Text("A reload request is NOT a guarantee of instant visible change. Record real-device latency and any stale UI.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Agent UI Lab")
        }
    }

    private func publish() {
        guard var payload = WidgetStore.parse(jsonText) else {
            message = "Invalid schema: require status/choice/result, valid options and bounded text."
            return
        }
        // Version is monotonic for the local experiment, not a production identity.
        payload.revision = max(payload.revision, WidgetStore.load().revision + 1)
        payload.updatedAt = ISO8601DateFormatter().string(from: Date())
        if WidgetStore.save(payload) {
            message = "Saved \(payload.kind) at \(payload.updatedAt). Reload requested: \(doReload)."
            if doReload { WidgetCenter.shared.reloadTimelines(ofKind: "AgentWidget") }
        } else {
            message = "Could not write shared App Group state. Check entitlements and provisioning."
        }
        jsonText = WidgetStore.formattedJSON(payload)
    }
}
