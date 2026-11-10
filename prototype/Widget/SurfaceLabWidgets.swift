import WidgetKit
import SwiftUI
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - Home Screen tiles (one widget kind per tile, so each instance knows its tile id
// without user configuration; WidgetKit gives a widget no information about its position).

struct SLEntry: TimelineEntry {
    var date: Date
    var tile: String
    var family: WidgetFamily
    var size: CGSize
    var spec: SLSpec?
    var t: SLTile?
    var image: UIImage?
    var scene: RLScene?
}

struct SLProvider: TimelineProvider {
    let tile: String
    func placeholder(in context: Context) -> SLEntry { SLEntry(date: .now, tile: tile, family: context.family, size: context.displaySize) }
    func getSnapshot(in context: Context, completion: @escaping (SLEntry) -> Void) { completion(make(context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SLEntry>) -> Void) {
        completion(Timeline(entries: [make(context)], policy: .never))
    }
    func make(_ c: Context) -> SLEntry {
        let t0 = Date()
        let spec = SLStore.spec()
        let t = spec?.tiles["\(tile)-\(c.family)"] ?? spec?.tiles[tile]
        var e = SLEntry(date: .now, tile: tile, family: c.family, size: c.displaySize, spec: spec, t: t)
        if let n = t?.image, let u = SLStore.url(n), let img = UIImage(contentsOfFile: u.path) { e.image = img.preparingForDisplay() ?? img }
        e.scene = SLStore.scene(t?.scene)
        Log.event("sl_timeline", detail: "run=\(spec?.run ?? "-") tile=\(tile) family=\(c.family) size=\(c.displaySize.width)x\(c.displaySize.height) preview=\(c.isPreview) image=\(e.image != nil) scene=\(e.scene != nil) prepMs=\(RLMetrics.ms(since: t0)) selected=\(spec?.selected ?? "-")")
        return e
    }
}

struct SLTileView: View {
    let e: SLEntry
    var body: some View {
        ZStack {
            if let img = e.image {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: e.size.width, height: e.size.height).clipped()
            } else if let sc = e.scene {
                RLCanvasView(scene: sc, run: e.spec?.run ?? "")
            }
            if let l = e.t?.label ?? (e.spec == nil ? "Tile \(e.tile)" : nil) {
                Text(l).font(.system(size: 15, weight: .heavy)).foregroundStyle(.primary)
            }
            if let sel = e.spec?.selected {   // shared state, shown by every tile
                Text("selected: \(sel)").font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(4).background(.black.opacity(0.7)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(8)
            }
            if e.spec?.regions == true, let sc = e.scene, let regs = sc.regions {
                SLHitLayer(regions: regs, sceneW: sc.w, sceneH: sc.h, ns: e.tile, debug: e.spec?.debug == true, selected: e.spec?.selected)
            }
        }
        .containerBackground(for: .widget) { background }
    }

    @ViewBuilder private var background: some View {
        switch e.t?.bg {
        case "clear": Color.clear
        case let hex? where hex.hasPrefix("#"):
            if let c = RLColor.cg(hex) { Color(cgColor: c) } else { Color.gray }
        default: Color(uiColor: .systemBackground)
        }
    }
}

/// Same idea as RLHitOverlay, but routes to SLHitIntent with tile-namespaced ids.
struct SLHitLayer: View {
    let regions: [RLRegion]; let sceneW: Double; let sceneH: Double
    let ns: String; var debug = false; var selected: String? = nil
    var body: some View {
        GeometryReader { geo in
            let f = RLFit(scene: RLScene(w: sceneW, h: sceneH, ops: []), in: geo.size)
            ZStack(alignment: .topLeading) {
                ForEach(regions, id: \.self) { r in
                    let rect = f.rect(r); let id = "\(ns):\(r.id)"
                    Button(intent: SLHitIntent(region: id)) {
                        ZStack {
                            Color.clear
                            if debug { Rectangle().strokeBorder(Color.red, lineWidth: 1) }
                            if selected == id { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white, lineWidth: 3) }
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .accessibilityLabel(r.label ?? id)
                }
            }.frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}

private let slFamilies: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline]

enum SLTileConfig {
    static func make(_ tile: String) -> some WidgetConfiguration {
        // Interpolated literals become formatted LocalizedStringKeys, which WidgetKit rejects at runtime
        // ("Formatted text for `configurationDisplayName` is not supported") → pass plain Strings.
        let name: String = "Surface Tile " + tile, desc: String = "SurfaceLab tile " + tile
        return StaticConfiguration(kind: "SLTile" + tile, provider: SLProvider(tile: tile)) { SLTileView(e: $0) }
            .configurationDisplayName(name)
            .description(desc)
            .supportedFamilies(slFamilies)
            .contentMarginsDisabled()
    }
}

struct SLTileA: Widget { var body: some WidgetConfiguration { SLTileConfig.make("A") } }
struct SLTileB: Widget { var body: some WidgetConfiguration { SLTileConfig.make("B") } }
struct SLTileC: Widget { var body: some WidgetConfiguration { SLTileConfig.make("C") } }
struct SLTileD: Widget { var body: some WidgetConfiguration { SLTileConfig.make("D") } }

// MARK: - Measurement Live Activity (Lock Screen, Dynamic Island, StandBy)

#if canImport(ActivityKit)
private func hexColor(_ s: String) -> Color { RLColor.cg(s).map { Color(cgColor: $0) } ?? .orange }

/// Fills its region, prints its own size, logs it (sizes are only knowable inside the view).
struct SLMeasure: View {
    let region: String; let color: Color; var activity = ""
    var body: some View {
        GeometryReader { g in
            let _ = Log.event("sl_la_region", detail: "activity=\(activity) region=\(region) size=\(Int(g.size.width))x\(Int(g.size.height))")
            ZStack {
                color
                Text("\(region) \(Int(g.size.width))×\(Int(g.size.height))")
                    .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.white).minimumScaleFactor(0.5)
            }
        }
    }
}

struct SLLockScreenView: View {
    let name: String; let st: SLActivityAttributes.ContentState
    var body: some View {
        GeometryReader { g in
            let _ = Log.event("sl_la_region", detail: "activity=\(name) region=lockscreen size=\(Int(g.size.width))x\(Int(g.size.height))")
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [hexColor(st.color), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                // 20-pt ruler
                Path { p in
                    stride(from: 0.0, through: g.size.height, by: 20).forEach { y in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: 8, y: y)) }
                    stride(from: 0.0, through: g.size.width, by: 20).forEach { x in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: 8)) }
                }.stroke(.white.opacity(0.8), lineWidth: 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(name) · \(Int(g.size.width))×\(Int(g.size.height)) pt").font(.system(size: 13, weight: .heavy, design: .monospaced))
                    Text(st.label).font(.system(size: 11, weight: .semibold))
                    HStack(spacing: 8) {
                        Button(intent: SLActivityTapIntent(name: name, button: "A")) { Text("A").frame(maxWidth: .infinity, minHeight: 36) }
                        Button(intent: SLActivityTapIntent(name: name, button: "B")) { Text("B").frame(maxWidth: .infinity, minHeight: 36) }
                    }.buttonStyle(.bordered).tint(.white)
                }
                .foregroundStyle(.white).padding(14)
            }
        }
        .frame(minHeight: st.h ?? 160)   // probe: ask for more height than the system allows
    }
}

struct SLLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SLActivityAttributes.self) { ctx in
            SLLockScreenView(name: ctx.attributes.name, st: ctx.state)
                .activityBackgroundTint(.black)
        } dynamicIsland: { ctx in
            let n = ctx.attributes.name
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { SLMeasure(region: "leading", color: .red, activity: n) }
                DynamicIslandExpandedRegion(.trailing) { SLMeasure(region: "trailing", color: .blue, activity: n) }
                DynamicIslandExpandedRegion(.center) { SLMeasure(region: "center", color: .purple, activity: n) }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        SLMeasure(region: "bottom", color: .green, activity: n).frame(minHeight: ctx.state.h ?? 60)
                        Button(intent: SLActivityTapIntent(name: n, button: "island")) { Text("Island tap").frame(maxWidth: .infinity, minHeight: 30) }
                    }
                }
            } compactLeading: {
                SLMeasure(region: "compactL", color: .red, activity: n)
            } compactTrailing: {
                SLMeasure(region: "compactT", color: .blue, activity: n)
            } minimal: {
                SLMeasure(region: "minimal", color: .orange, activity: n)
            }
        }
    }
}
#endif

// MARK: - Control (Control Center, Lock Screen, Action button), iOS 18+

@available(iOS 18.0, *)
struct SLControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SLControl") {
            ControlWidgetButton(action: SLControlIntent()) {
                Label("Agent", systemImage: "sparkles")
            }
        }
        .displayName("Agent Surface Control")
    }
}
