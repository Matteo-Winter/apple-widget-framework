import WidgetKit
import SwiftUI
import UIKit
import CoreText
import CoreImage
import CoreImage.CIFilterBuiltins

// RenderLab widget: renders exactly one technique per spec (see RenderLab/RLSpec.swift).
// Measurements are written to events.jsonl:
//   rl_timeline   preparation inside the provider (decode / offscreen render), memory before/after
//   rl_view       SwiftUI body evaluation for the archived snapshot
//   rl_canvas_draw  Canvas closure execution (only for canvas technique)

struct RLEntry: TimelineEntry {
    var date: Date
    var spec: RLSpec?
    var family: WidgetFamily
    var size: CGSize
    var scene: RLScene? = nil
    var image: UIImage? = nil
    var paneImages: [String: UIImage] = [:]
    var paneScenes: [String: RLScene] = [:]
    var surface: Surface? = nil
    var note: String = ""
}

struct RLProvider: TimelineProvider {
    func placeholder(in context: Context) -> RLEntry {
        RLEntry(date: .now, spec: nil, family: context.family, size: context.displaySize, note: "placeholder")
    }

    func getSnapshot(in context: Context, completion: @escaping (RLEntry) -> Void) {
        completion(make(context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RLEntry>) -> Void) {
        completion(Timeline(entries: [make(context)], policy: .never))
    }

    /// "{p}" → page index, "{f}" → widget family (systemMedium, systemLarge, …)
    private func sceneName(_ spec: RLSpec, _ name: String?) -> String? {
        name?.replacingOccurrences(of: "{p}", with: "\(spec.page ?? 0)")
            .replacingOccurrences(of: "{f}", with: "\(fam)")
    }
    private var fam: String { RLProvider.currentFamily }
    nonisolated(unsafe) static var currentFamily = ""

    func make(_ context: Context) -> RLEntry {
        let t0 = Date(), m0 = RLMetrics.footprintMB()
        RLProvider.currentFamily = "\(context.family)"
        var e = RLEntry(date: .now, spec: RLStore.spec(), family: context.family, size: context.displaySize)
        guard let spec = e.spec else { e.note = "no spec"; return e }
        let scale = CGFloat(spec.cgScale ?? 3)
        var detail = ""
        switch spec.technique {
        case "canvas", "views":
            e.scene = RLStore.scene(sceneName(spec, spec.scene))
            detail = "ops=\(e.scene?.ops.count ?? -1)"
        case "cg":
            if spec.fontFile != nil { detail += RLFonts.register(spec.fontFile) + " " }   // rasterize runtime fonts in-process
            if let sc = RLStore.scene(sceneName(spec, spec.scene)) {
                e.scene = sc
                let (img, st) = RLCG.render(sc, pw: Int(context.displaySize.width * scale), ph: Int(context.displaySize.height * scale),
                                            imageDir: RLStore.dir, symbol: RLSymbols.draw)
                e.image = img.map { UIImage(cgImage: $0, scale: scale, orientation: .up) }
                detail += "ops=\(st.ops) renderMs=\(Int(st.ms)) px=\(Int(context.displaySize.width * scale))x\(Int(context.displaySize.height * scale)) skipped=\(st.skipped)"
            } else { detail = "scene missing" }
        case "bitmap":
            let name = sceneName(spec, spec.bitmap)
            if let n = name, let u = RLStore.url(n), let raw = UIImage(contentsOfFile: u.path) {
                let td = Date()
                e.image = raw.preparingForDisplay() ?? raw     // force decode to measure it
                let bytes = (try? FileManager.default.attributesOfItem(atPath: u.path)[.size] as? Int) ?? -1
                detail = "file=\(n) bytes=\(bytes) px=\(Int(raw.size.width * raw.scale))x\(Int(raw.size.height * raw.scale)) decodeMs=\(RLMetrics.ms(since: td))"
            } else { detail = "bitmap missing/undecodable \(name ?? "-")" }
            e.scene = RLStore.scene(sceneName(spec, spec.scene))   // optional: regions only
        case "pdf":
            if let u = sceneName(spec, spec.pdf).flatMap(RLStore.url), let doc = CGPDFDocument(u as CFURL), let page = doc.page(at: 1) {
                let box = page.getBoxRect(.mediaBox)
                let pw = Int(context.displaySize.width * scale), ph = Int(context.displaySize.height * scale)
                let r = UIGraphicsImageRenderer(size: context.displaySize, format: { let f = UIGraphicsImageRendererFormat(); f.scale = scale; return f }())
                e.image = r.image { c in
                    let cg = c.cgContext
                    let s = min(context.displaySize.width / box.width, context.displaySize.height / box.height)
                    cg.translateBy(x: 0, y: context.displaySize.height); cg.scaleBy(x: s, y: -s)
                    cg.drawPDFPage(page)
                }
                detail = "pdf box=\(Int(box.width))x\(Int(box.height)) px=\(pw)x\(ph)"
            } else { detail = "pdf missing/undecodable" }
            e.scene = RLStore.scene(sceneName(spec, spec.scene))
        case "svg":
            let d = RLStore.data(spec.bitmap)
            let img = d.flatMap { UIImage(data: $0) }
            e.image = img
            detail = "bytes=\(d?.count ?? -1) UIImage(data:)=\(img == nil ? "nil" : "ok")"
        case "font":
            detail = RLFonts.register(spec.fontFile)
            e.scene = RLStore.scene(sceneName(spec, spec.scene))
        case "coreimage":
            let td = Date()
            let qr = CIFilter.qrCodeGenerator(); qr.message = Data((spec.run + " · agent payload").utf8); qr.correctionLevel = "M"
            let ctx = CIContext()
            if let out = qr.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
               let cg = ctx.createCGImage(out, from: out.extent) { e.image = UIImage(cgImage: cg) }
            detail = "ciMs=\(RLMetrics.ms(since: td)) ok=\(e.image != nil)"
        case "json":
            if let d = RLStore.data(spec.surfaceFile) {
                if spec.bypassLimits == true {
                    e.surface = try? JSONDecoder().decode(Surface.self, from: d)
                    detail = "decoded(bypass)=\(e.surface != nil) nodes=\(e.surface?.root.stats().nodes ?? -1)"
                } else {
                    switch Surface.decode(d) {
                    case .success(let s): e.surface = s; detail = "valid nodes=\(s.root.stats().nodes)"
                    case .failure(let err): e.surface = Presets.invalid(err.description); detail = "rejected: \(err.description)"
                    }
                }
            }
        case "multi":
            for p in spec.panes ?? [] {
                switch p.technique {
                case "cg":
                    if let sc = RLStore.scene(sceneName(spec, p.scene)) {
                        e.paneScenes[p.agent] = sc
                        let w = context.displaySize.width * p.w, h = context.displaySize.height * p.h
                        let (img, _) = RLCG.render(sc, pw: Int(w * scale), ph: Int(h * scale), imageDir: RLStore.dir, symbol: RLSymbols.draw)
                        if let img { e.paneImages[p.agent] = UIImage(cgImage: img, scale: scale, orientation: .up) }
                    }
                case "bitmap":
                    if let u = sceneName(spec, p.bitmap).flatMap(RLStore.url), let ui = UIImage(contentsOfFile: u.path) { e.paneImages[p.agent] = ui.preparingForDisplay() ?? ui }
                    if let sc = RLStore.scene(sceneName(spec, p.scene)) { e.paneScenes[p.agent] = sc }
                case "json":
                    if let d = RLStore.data(p.surfaceFile), case .success(let s) = Surface.decode(d) { e.paneScenes[p.agent] = nil; e.surface = s }
                default:
                    if let sc = RLStore.scene(sceneName(spec, p.scene)) { e.paneScenes[p.agent] = sc }
                }
            }
            detail = "panes=\(spec.panes?.count ?? 0) images=\(e.paneImages.count)"
        default:
            break
        }
        let m1 = RLMetrics.footprintMB()
        Log.event("rl_timeline", detail: "run=\(spec.run) tech=\(spec.technique) family=\(context.family) size=\(Int(context.displaySize.width))x\(Int(context.displaySize.height)) prepMs=\(RLMetrics.ms(since: t0)) memBefore=\(String(format: "%.1f", m0)) memAfter=\(String(format: "%.1f", m1)) \(detail)")
        e.note = detail
        return e
    }
}

enum RLSymbols {
    /// SF Symbol drawing for the CG path (iOS only; servers cannot draw SF Symbols).
    static func draw(_ op: RLOp, _ ctx: CGContext) -> Bool {
        guard let n = op.name, let img = UIImage(systemName: n, withConfiguration: UIImage.SymbolConfiguration(pointSize: 64)),
              let tinted = img.withTintColor(RLColor.cg(op.fill).map { UIColor(cgColor: $0) } ?? .black, renderingMode: .alwaysOriginal).cgImageRendered()
        else { return false }
        let r = op.rect
        ctx.translateBy(x: 0, y: r.maxY + r.minY); ctx.scaleBy(x: 1, y: -1)
        let ar = img.size.width / img.size.height
        let w = min(r.width, r.height * ar), h = w / ar
        ctx.draw(tinted, in: CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h))
        return true
    }
}

private extension UIImage {
    func cgImageRendered() -> CGImage? {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in draw(at: .zero) }.cgImage
    }
}

enum RLFonts {
    /// Registers a font file shipped as *data* (App Group) at runtime, process-scoped.
    static func register(_ file: String?) -> String {
        guard let u = file.flatMap(RLStore.url), let d = try? Data(contentsOf: u) else { return "font file missing" }
        guard let prov = CGDataProvider(data: d as CFData), let f = CGFont(prov) else { return "CGFont decode failed" }
        let ps = (f.postScriptName as String?) ?? "?"
        var err: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterGraphicsFont(f, &err)
        let msg = err?.takeRetainedValue().localizedDescription ?? ""
        let usable = UIFont(name: ps, size: 12) != nil
        return "font=\(ps) registered=\(ok) usable=\(usable) \(msg.prefix(80))"
    }
}

// MARK: - View

struct RLWidgetView: View {
    let entry: RLEntry

    var body: some View {
        let spec = entry.spec
        let _ = Log.event("rl_view", detail: "run=\(spec?.run ?? "-") tech=\(spec?.technique ?? "-") family=\(entry.family)")
        ZStack {
            content
            if spec?.regions == true, let sc = entry.scene, let regs = sc.regions, spec?.technique != "multi" {
                RLHitOverlay(regions: regs, sceneW: sc.w, sceneH: sc.h, run: spec?.run ?? "",
                             debug: spec?.debugRegions == true, selected: spec?.selected, style: spec?.hitStyle ?? "clear")
            }
        }
        .padding(CGFloat(spec?.padding ?? 0))
        .containerBackground(for: .widget) {
            if let bg = spec?.background, let c = RLColor.cg(bg) { Color(cgColor: c) } else { Color(uiColor: .systemBackground) }
        }
    }

    @ViewBuilder private var content: some View {
        if let spec = entry.spec {
            switch spec.technique {
            case "canvas":
                if let sc = entry.scene { RLCanvasView(scene: sc, run: spec.run, fill: spec.fill == true) } else { missing }
            case "views":
                if let sc = entry.scene { RLViewsView(scene: sc) } else { missing }
            case "cg", "bitmap", "pdf", "coreimage":
                if let img = entry.image {
                    if spec.fill == true {
                        Image(uiImage: img).resizable().interpolation(spec.technique == "coreimage" ? .none : .high).scaledToFill()
                    } else {
                        Image(uiImage: img).resizable().interpolation(spec.technique == "coreimage" ? .none : .high).scaledToFit()
                    }
                } else { missing }
            case "svg":
                if let img = entry.image { Image(uiImage: img).resizable().scaledToFit() } else { Text("SVG: UIImage(data:) == nil").font(.caption) }
            case "font":
                if let sc = entry.scene { RLCanvasView(scene: sc, run: spec.run) } else { Text(entry.note).font(.caption2) }
            case "json":
                if let s = entry.surface { SurfaceView(surface: s, family: "\(entry.family)", channel: .widget, showStamp: false).padding(16) } else { missing }
            case "charts":
                RLChartsView(n: Int(spec.cgScale ?? 40))
            case "uiview":
                RLUIKitLabel()
            case "multi":
                RLPanesView(entry: entry, spec: spec)
            case "blank":
                Color.clear
            default:
                missing
            }
        } else {
            VStack(spacing: 4) { Text("RenderLab").font(.headline); Text("no spec").font(.caption) }
        }
    }

    private var missing: some View { Text("missing: \(entry.note)").font(.caption2).foregroundStyle(.red) }
}

/// Multi-agent compositor: each pane is produced independently (possibly by a
/// different technique), placed in its normalized frame, and gets a hit layer
/// whose region ids are namespaced with the pane's agent.
struct RLPanesView: View {
    let entry: RLEntry
    let spec: RLSpec

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(spec.panes ?? [], id: \.self) { p in
                    let r = CGRect(x: geo.size.width * p.x, y: geo.size.height * p.y, width: geo.size.width * p.w, height: geo.size.height * p.h)
                    pane(p)
                        .overlay {
                            if let sc = entry.paneScenes[p.agent], let regs = sc.regions {
                                RLHitOverlay(regions: regs, sceneW: sc.w, sceneH: sc.h, run: spec.run,
                                             debug: spec.debugRegions == true, selected: spec.selected, style: spec.hitStyle ?? "clear", namespace: p.agent)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .frame(width: r.width, height: r.height)
                        .offset(x: r.minX, y: r.minY)
                }
            }
        }
    }

    @ViewBuilder private func pane(_ p: RLPane) -> some View {
        switch p.technique {
        case "cg", "bitmap":
            if let img = entry.paneImages[p.agent] { Image(uiImage: img).resizable().scaledToFill() } else { Color.gray }
        case "json":
            if let s = entry.surface { SurfaceView(surface: s, family: "systemSmall", channel: .widget, showStamp: false).padding(10).background(Color(white: 0.96)) } else { Color.gray }
        default:
            if let sc = entry.paneScenes[p.agent] { RLCanvasView(scene: sc, run: spec.run) } else { Color.gray }
        }
    }
}

private let rlFamilies: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge,
                                           .accessoryRectangular, .accessoryCircular, .accessoryInline]

struct RenderLabWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RLKind.widget, provider: RLProvider()) { RLWidgetView(entry: $0) }
            .configurationDisplayName("Render Lab")
            .description("Rendering-freedom experiments (full bleed).")
            .supportedFamilies(rlFamilies)
            .contentMarginsDisabled()
    }
}

/// Same widget with the system's default content margins, for the margin comparison.
struct RenderLabMarginsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RLKind.widget + "Margins", provider: RLProvider()) { RLWidgetView(entry: $0) }
            .configurationDisplayName("Render Lab (margins)")
            .description("Rendering-freedom experiments with default margins.")
            .supportedFamilies(rlFamilies)
    }
}
