import Foundation
import CoreGraphics

// MARK: - RenderLab display list
//
// A *scene* is a flat list of drawing operations in an agent-chosen design
// coordinate space (w × h points). It is pure data, like the JSON node tree, but
// it carries no notion of components: positions, sizes, colors, gradients, paths
// and text placement are free. The same scene can be drawn by several renderers
// so they can be compared on identical input:
//   • SwiftUI Canvas (GraphicsContext)         – RLViews.swift, in the widget view
//   • SwiftUI view-per-op (ZStack + .position) – RLViews.swift, in the widget view
//   • Core Graphics (CGContext + CoreText)     – RLCoreGraphics.swift, in the timeline
//     provider, in the app, or on a server (same file compiles on macOS: tools/rl_render.swift)
//
// This file must stay portable (Foundation + CoreGraphics only).

struct RLScene: Codable {
    var w: Double
    var h: Double
    var bg: String? = nil
    var ops: [RLOp]
    /// Interaction regions in the same coordinate space. Rendered as transparent native
    /// Buttons above the graphic (see RLHitOverlay).
    var regions: [RLRegion]? = nil
}

struct RLOp: Codable {
    /// rect | oval | line | poly | text | lgrad | rgrad | img | sym | arc
    var k: String
    var x: Double? = nil, y: Double? = nil, w: Double? = nil, h: Double? = nil
    var r: Double? = nil                 // corner radius (rect), radius (arc)
    var fill: String? = nil              // #RRGGBB or #RRGGBBAA
    var stroke: String? = nil
    var lw: Double? = nil
    var pts: [Double]? = nil             // poly/line: x0,y0,x1,y1,…
    var close: Bool? = nil
    var c: [String]? = nil               // gradient stops (evenly spaced)
    var x2: Double? = nil, y2: Double? = nil   // linear gradient end (start = x,y)
    var t: String? = nil                 // text
    var size: Double? = nil              // font size (points)
    var weight: String? = nil            // regular|medium|semibold|bold|heavy|black
    var font: String? = nil              // PostScript name (system font if nil/unknown)
    var align: String? = nil             // left|center|right (text anchored at x)
    var name: String? = nil              // img: file in App Group; sym: SF Symbol
    var a0: Double? = nil, a1: Double? = nil   // arc start/end (degrees, clockwise from 12 o'clock)
    var alpha: Double? = nil
}

struct RLRegion: Codable, Hashable {
    var id: String
    var agent: String? = nil
    var x: Double, y: Double, w: Double, h: Double
    var label: String? = nil
    /// nil → RLHitIntent (report to agent). "page:+1" / "page:-1" → local navigation (RLPageIntent).
    var action: String? = nil
}

enum RLColor {
    /// Parses #RGB, #RRGGBB, #RRGGBBAA. Returns sRGB components.
    static func rgba(_ s: String?) -> (Double, Double, Double, Double)? {
        guard var hex = s?.trimmingCharacters(in: .whitespaces), hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        if hex.count == 6 { hex += "FF" }
        guard hex.count == 8, let v = UInt64(hex, radix: 16) else { return nil }
        return (Double((v >> 24) & 0xff) / 255, Double((v >> 16) & 0xff) / 255,
                Double((v >> 8) & 0xff) / 255, Double(v & 0xff) / 255)
    }

    static func cg(_ s: String?) -> CGColor? {
        guard let (r, g, b, a) = rgba(s) else { return nil }
        return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

extension RLOp {
    var rect: CGRect { CGRect(x: x ?? 0, y: y ?? 0, width: w ?? 0, height: h ?? 0) }
    var points: [CGPoint] {
        guard let p = pts else { return [] }
        return stride(from: 0, to: p.count - 1, by: 2).map { CGPoint(x: p[$0], y: p[$0 + 1]) }
    }
    /// Path for geometric ops in scene coordinates (nil for text/img/sym/gradients).
    var path: CGPath? {
        switch k {
        case "rect":
            let rr = min(r ?? 0, min(rect.width, rect.height) / 2)
            return CGPath(roundedRect: rect, cornerWidth: rr, cornerHeight: rr, transform: nil)
        case "oval":
            return CGPath(ellipseIn: rect, transform: nil)
        case "line", "poly":
            let m = CGMutablePath()
            let p = points
            guard let first = p.first else { return nil }
            m.move(to: first)
            for q in p.dropFirst() { m.addLine(to: q) }
            if close == true { m.closeSubpath() }
            return m
        case "arc":
            // Clockwise from 12 o'clock in a y-down space.
            let m = CGMutablePath()
            let c = CGPoint(x: x ?? 0, y: y ?? 0)
            let s = ((a0 ?? 0) - 90) * .pi / 180, e = ((a1 ?? 360) - 90) * .pi / 180
            m.addArc(center: c, radius: r ?? 10, startAngle: s, endAngle: e, clockwise: false)
            return m
        default:
            return nil
        }
    }
}

extension RLScene {
    static func load(_ data: Data) -> RLScene? { try? JSONDecoder().decode(RLScene.self, from: data) }
    var opCounts: [String: Int] { ops.reduce(into: [:]) { $0[$1.k, default: 0] += 1 } }
}
