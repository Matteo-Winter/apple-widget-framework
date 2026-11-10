import WidgetKit
import SwiftUI

struct AgentEntry: TimelineEntry {
    var date: Date
    var payload: WidgetPayload
}

struct AgentProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgentEntry {
        AgentEntry(date: .now, payload: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (AgentEntry) -> Void) {
        completion(AgentEntry(date: .now, payload: WidgetStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgentEntry>) -> Void) {
        let current = AgentEntry(date: .now, payload: WidgetStore.load())
        // A *requested* refresh in a minute is a test, not an update guarantee.
        completion(Timeline(entries: [current], policy: .after(Date().addingTimeInterval(60))))
    }
}

struct AgentWidgetView: View {
    let entry: AgentEntry

    var body: some View {
        let data = entry.payload
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: data.kind == "choice" ? "questionmark.circle" : "sparkles")
                Text(data.kind == "choice" ? "NEEDS INPUT" : "AGENT UI")
                    .font(.caption2).bold()
                Spacer()
                Text("v\(data.revision)").font(.caption2).foregroundStyle(.secondary)
            }
            Text(data.title).font(.headline).lineLimit(2)
            Text(data.message).font(.caption).lineLimit(3)
            if data.kind == "status" {
                ProgressView(value: min(1, max(0, data.progress)))
            } else if data.kind == "choice" {
                HStack(spacing: 6) {
                    ForEach(data.options.prefix(2)) { option in
                        Button(intent: ChooseOptionIntent(
                            requestId: data.requestId, optionId: option.id
                        )) {
                            Text(option.label).font(.caption2).lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                Label("Finished", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            }
            Spacer(minLength: 0)
            HStack {
                Text("Same widget, new schema").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button(intent: NextCardIntent()) {
                    Image(systemName: "arrow.right.circle.fill")
                }.buttonStyle(.plain)
            }
        }
        .padding(12)
        .containerBackground(.background, for: .widget)
    }
}

struct AgentWidget: Widget {
    let kind = "AgentWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgentProvider()) { entry in
            AgentWidgetView(entry: entry)
        }
        .configurationDisplayName("Agent UI Lab")
        .description("Experiments with agent-defined widget layouts and direct actions.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct AgentWidgetBundle: WidgetBundle {
    var body: some Widget {
        AgentWidget()
    }
}
