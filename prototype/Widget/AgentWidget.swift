import WidgetKit
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

struct AgentEntry: TimelineEntry {
    var date: Date
    var surface: Surface
}

struct AgentProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgentEntry { AgentEntry(date: .now, surface: Presets.status) }

    func getSnapshot(in context: Context, completion: @escaping (AgentEntry) -> Void) {
        completion(AgentEntry(date: .now, surface: context.isPreview ? Presets.decision : Store.loadSurface()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgentEntry>) -> Void) {
        Task {
            var surface = Store.loadSurface()
            Log.event("get_timeline", rev: surface.revision, detail: "\(context.family)")

            // Pull-on-reload: whenever iOS grants a reload (budget, push, intent),
            // fetch the agent's newest surface first. Bounded timeout.
            if Store.config().pullOnReload, let remote = await Bridge.fetchSurface(timeout: 3),
               remote.revision > surface.revision || remote.id != surface.id {
                if Store.save(remote) { surface = remote }
            }

            // Current tree + pre-scheduled future trees as separate timeline entries.
            var entries = [AgentEntry(date: .now, surface: surface)]
            for item in surface.schedule ?? [] {
                guard let at = ISO.parse(item.at), at > .now else { continue }
                var s = surface; s.root = item.root; s.layouts = nil
                entries.append(AgentEntry(date: at, surface: s))
            }
            if let exp = surface.expiresAt.flatMap(ISO.parse), exp > .now {
                entries.append(AgentEntry(date: exp, surface: surface)) // view resolves expiredRoot
            }
            entries.sort { $0.date < $1.date }
            // Request (not guarantee) a reload 15 min after the last entry.
            let next = (entries.last?.date ?? .now).addingTimeInterval(15 * 60)
            Log.event("timeline_built", rev: surface.revision, detail: "entries=\(entries.count)")
            completion(Timeline(entries: entries, policy: .after(next)))
        }
    }
}

struct AgentWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AgentEntry

    var body: some View {
        SurfaceView(surface: entry.surface, family: "\(family)", channel: .widget,
                    showStamp: family != .accessoryInline && family != .accessoryCircular)
            .containerBackground(.background, for: .widget)
    }
}

private let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge,
                                         .accessoryRectangular, .accessoryInline, .accessoryCircular]

struct AgentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.surface, provider: AgentProvider()) { entry in
            AgentWidgetView(entry: entry)
        }
        .configurationDisplayName("Agent Surface")
        .description("One widget that renders any agent-defined layout.")
        .supportedFamilies(families)
    }
}

/// Identical widget with a WidgetKit push handler (iOS 26+ only).
@available(iOS 26.0, *)
struct AgentPushWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKinds.pushSurface, provider: AgentProvider()) { entry in
            AgentWidgetView(entry: entry)
        }
        .configurationDisplayName("Agent Surface (Push)")
        .description("Same renderer, plus WidgetKit push updates (iOS 26+).")
        .supportedFamilies(families)
        .pushHandler(AgentWidgetPushHandler.self)
    }
}

@available(iOS 26.0, *)
struct AgentWidgetPushHandler: WidgetPushHandler {
    init() {}
    func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) {
        Store.saveToken("widget", pushInfo.token)
        Log.event("widget_push_token", detail: "widgets=\(widgets.count)")
    }
}

#if canImport(ActivityKit)
struct AgentLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentActivityAttributes.self) { ctx in
            SurfaceView(surface: ctx.state.surface, family: "activity", channel: .activity)
                .padding(14)
                .activityBackgroundTint(Color(uiColor: .systemBackground))
        } dynamicIsland: { ctx in
            let s = ctx.state.surface
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    SurfaceView(surface: s, family: "island", channel: .activity, showStamp: false)
                }
            } compactLeading: {
                Image(systemName: s.answeredAction == nil ? "sparkles" : "checkmark")
            } compactTrailing: {
                Text(verbatim: "r\(s.revision)").font(.caption2).monospacedDigit()
            } minimal: {
                Image(systemName: "sparkles")
            }
        }
    }
}
#endif

@main
struct AgentWidgetBundle: WidgetBundle {
    var body: some Widget {
        AgentWidget()
        RenderLabWidget()
        RenderLabMarginsWidget()
        SLTileA(); SLTileB(); SLTileC(); SLTileD()
        if #available(iOS 26.0, *) {
            AgentPushWidget()
        }
        #if canImport(ActivityKit)
        AgentLiveActivity()
        SLLiveActivity()
        #endif
        if #available(iOS 18.0, *) {
            SLControl()
        }
    }
}
