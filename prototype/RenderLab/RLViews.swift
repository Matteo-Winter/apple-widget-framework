import SwiftUI
import UIKit
import AppIntents
import WidgetKit
#if canImport(Charts)
import Charts
#endif

// MARK: - Scene geometry helper

struct RLFit {
    let scale: CGFloat, ox: CGFloat, oy: CGFloat
    init(scene: RLScene, in size: CGSize, fill: Bool = false) {
        let sx = size.width / CGFloat(scene.w), sy = size.height / CGFloat(scene.h)
        scale = fill ? max(sx, sy) : min(sx, sy)
        ox = (size.width - CGFloat(scene.w) * scale) / 2
        oy = (size.height - CGFloat(scene.h) * scale) / 2
    }
    func rect(_ r: RLRegion) -> CGRect {
        CGRect(x: ox + CGFloat(r.x) * scale, y: oy + CGFloat(r.y) * scale, width: CGFloat(r.w) * scale, height: CGFloat(r.h) * scale)
    }
}

private func color(_ hex: String?) -> Color? { RLColor.cg(hex).map { Color(cgColor: $0) } }

private func swiftUIFont(_ op: RLOp) -> Font {
    let size = CGFloat(op.size ?? 12)
    if let n = op.font, !n.isEmpty, UIFont(name: n, size: size) != nil { return .custom(n, fixedSize: size) }
    let w: Font.Weight
    switch op.weight {
    case "medium": w = .medium; case "semibold": w = .semibold; case "bold": w = .bold
    case "heavy": w = .heavy; case "black": w = .black; default: w = .regular
    }
    return .system(size: size, weight: w)
}

private func uiImage(_ name: String?) -> UIImage? {
    guard let n = name, let u = RLStore.url(n) else { return nil }
    return UIImage(contentsOfFile: u.path)
}

// MARK: - Technique: SwiftUI Canvas (one view, immediate-mode drawing)

struct RLCanvasView: View {
    let scene: RLScene
    var run: String = ""
    var fill = false

    var body: some View {
        Canvas { ctx, size in
            let t0 = Date()
            let f = RLFit(scene: scene, in: size, fill: fill)
            ctx.translateBy(x: f.ox, y: f.oy)
            ctx.scaleBy(x: f.scale, y: f.scale)
            if let bg = color(scene.bg) {
                ctx.fill(Path(CGRect(x: 0, y: 0, width: scene.w, height: scene.h)), with: .color(bg))
            }
            for op in scene.ops { RLCanvasView.draw(op, &ctx) }
            Log.event("rl_canvas_draw", detail: "run=\(run) ops=\(scene.ops.count) ms=\(RLMetrics.ms(since: t0)) size=\(Int(size.width))x\(Int(size.height)) mem=\(RLMetrics.footprintMB())")
        }
    }

    static func draw(_ op: RLOp, _ ctx: inout GraphicsContext) {
        var c = ctx
        if let a = op.alpha { c.opacity = a }
        switch op.k {
        case "rect", "oval", "line", "poly", "arc":
            guard let cg = op.path else { return }
            let p = Path(cg)
            if let f = color(op.fill), op.k != "line", op.k != "arc" { c.fill(p, with: .color(f)) }
            if let s = color(op.stroke) {
                c.stroke(p, with: .color(s), style: StrokeStyle(lineWidth: op.lw ?? 1, lineCap: .round, lineJoin: .round))
            }
        case "lgrad", "rgrad":
            let cols = (op.c ?? []).compactMap(color)
            guard cols.count >= 2 else { return }
            let r = op.rect
            let shape = Path(roundedRect: r, cornerRadius: op.r ?? 0)
            if op.k == "lgrad" {
                c.fill(shape, with: .linearGradient(Gradient(colors: cols), startPoint: CGPoint(x: r.minX, y: r.minY),
                                                    endPoint: CGPoint(x: op.x2 ?? r.maxX, y: op.y2 ?? r.maxY)))
            } else {
                c.fill(shape, with: .radialGradient(Gradient(colors: cols), center: CGPoint(x: r.midX, y: r.midY),
                                                    startRadius: 0, endRadius: max(r.width, r.height) / 2))
            }
        case "text":
            let anchor: UnitPoint = op.align == "center" ? .top : op.align == "right" ? .topTrailing : .topLeading
            c.draw(Text(op.t ?? "").font(swiftUIFont(op)).foregroundColor(color(op.fill) ?? .black),
                   at: CGPoint(x: op.x ?? 0, y: op.y ?? 0), anchor: anchor)
        case "img":
            guard let ui = uiImage(op.name) else { return }
            let r = op.rect
            c.clip(to: Path(roundedRect: r, cornerRadius: op.r ?? 0))
            c.draw(Image(uiImage: ui), in: r)
        case "sym":
            var img = c.resolve(Image(systemName: op.name ?? "questionmark"))
            img.shading = .color(color(op.fill) ?? .black)
            c.draw(img, in: op.rect)
        default:
            break
        }
    }
}

// MARK: - Technique: SwiftUI view per operation (retained view tree, free positions)

struct RLViewsView: View {
    let scene: RLScene
    var body: some View {
        GeometryReader { geo in
            let f = RLFit(scene: scene, in: geo.size)
            ZStack(alignment: .topLeading) {
                if let bg = color(scene.bg) { bg.frame(width: scene.w, height: scene.h) }
                ForEach(Array(scene.ops.enumerated()), id: \.offset) { _, op in
                    // Every op gets the full scene frame so no child can grow the ZStack
                    // (a centered text would otherwise shift the whole composition).
                    RLOpView(op: op).frame(width: scene.w, height: scene.h, alignment: .topLeading)
                }
            }
            .frame(width: scene.w, height: scene.h, alignment: .topLeading)
            .scaleEffect(f.scale, anchor: .topLeading)
            .offset(x: f.ox, y: f.oy)
        }
    }
}

private struct PathShape: Shape {
    let cg: CGPath
    func path(in rect: CGRect) -> Path { Path(cg) }
}

private struct RLOpView: View {
    let op: RLOp
    var body: some View {
        content.opacity(op.alpha ?? 1)
    }
    @ViewBuilder private var content: some View {
        let r = op.rect
        switch op.k {
        case "rect", "oval", "line", "poly", "arc":
            if let cg = op.path {
                ZStack {
                    if let f = color(op.fill), op.k != "line", op.k != "arc" { PathShape(cg: cg).fill(f) }
                    if let s = color(op.stroke) {
                        PathShape(cg: cg).stroke(s, style: StrokeStyle(lineWidth: op.lw ?? 1, lineCap: .round, lineJoin: .round))
                    }
                }
            }
        case "lgrad":
            LinearGradient(colors: (op.c ?? []).compactMap(color), startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(RoundedRectangle(cornerRadius: op.r ?? 0, style: .continuous))
                .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
        case "rgrad":
            RadialGradient(colors: (op.c ?? []).compactMap(color), center: .center, startRadius: 0, endRadius: max(r.width, r.height) / 2)
                .clipShape(RoundedRectangle(cornerRadius: op.r ?? 0, style: .continuous))
                .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
        case "text":
            // 1-pt anchor frame: the frame alignment decides in which direction the text overflows.
            Text(op.t ?? "").font(swiftUIFont(op)).foregroundStyle(color(op.fill) ?? .black)
                .fixedSize()
                .frame(width: 1, height: 1, alignment: op.align == "center" ? .top : op.align == "right" ? .topTrailing : .topLeading)
                .offset(x: op.x ?? 0, y: op.y ?? 0)
        case "img":
            if let ui = uiImage(op.name) {
                Image(uiImage: ui).resizable().scaledToFill().frame(width: r.width, height: r.height)
                    .clipShape(RoundedRectangle(cornerRadius: op.r ?? 0)).offset(x: r.minX, y: r.minY)
            }
        case "sym":
            Image(systemName: op.name ?? "questionmark").resizable().scaledToFit()
                .foregroundStyle(color(op.fill) ?? .black).frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
        default:
            EmptyView()
        }
    }
}

// MARK: - Native interaction layer above any graphic

struct RLHitOverlay: View {
    let regions: [RLRegion]
    let sceneW: Double, sceneH: Double
    let run: String
    var debug = false
    var selected: String? = nil
    var style = "clear"        // clear | faint
    var namespace: String? = nil

    var body: some View {
        GeometryReader { geo in
            let f = RLFit(scene: RLScene(w: sceneW, h: sceneH, ops: []), in: geo.size)
            ZStack(alignment: .topLeading) {
                ForEach(regions, id: \.self) { r in
                    let rect = f.rect(r)
                    let id = namespace.map { "\($0):\(r.id)" } ?? r.id
                    Group {
                        if let a = r.action, a.hasPrefix("page:"), let d = Int(a.dropFirst(5)) {
                            Button(intent: RLPageIntent(delta: d)) { hitShape(selected: false) }
                        } else {
                            Button(intent: RLHitIntent(region: id, agent: r.agent ?? namespace ?? "", run: run)) {
                                hitShape(selected: selected == id)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .accessibilityLabel(r.label ?? id)
                    .accessibilityIdentifier("rl-\(id)")
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    @ViewBuilder private func hitShape(selected: Bool) -> some View {
        ZStack {
            if style == "faint" { Color.white.opacity(0.01) } else { Color.clear }
            if debug { Rectangle().strokeBorder(Color.red.opacity(0.7), lineWidth: 1) }
            if selected { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white, lineWidth: 3)
                .shadow(color: .black.opacity(0.6), radius: 0, x: 0, y: 0) }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Swift Charts (native charting framework)

struct RLChartsView: View {
    let n: Int
    var body: some View {
        #if canImport(Charts)
        let pts = (0..<max(2, n)).map { i in (i, sin(Double(i) / 6) * 40 + Double(i % 7) * 4 + 50) }
        Chart {
            ForEach(pts, id: \.0) { p in
                AreaMark(x: .value("t", p.0), y: .value("v", p.1)).foregroundStyle(.linearGradient(colors: [.orange.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("t", p.0), y: .value("v", p.1)).foregroundStyle(.orange)
            }
            RuleMark(y: .value("avg", 55)).foregroundStyle(.gray).lineStyle(StrokeStyle(dash: [3, 3]))
        }
        .chartXAxis(.hidden)
        .padding(12)
        #else
        Text("Charts unavailable")
        #endif
    }
}

// MARK: - Negative controls

/// UIKit view inside a widget. Apple: widgets only render SwiftUI; UIViewRepresentable is not supported.
struct RLUIKitLabel: UIViewRepresentable {
    func makeUIView(context: Context) -> UILabel {
        let l = UILabel(); l.text = "UIKit UILabel"; l.font = .boldSystemFont(ofSize: 22); l.textColor = .systemRed
        return l
    }
    func updateUIView(_ uiView: UILabel, context: Context) {}
}
