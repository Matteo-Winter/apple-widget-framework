import Foundation
import CoreGraphics
import CoreText
import ImageIO

// Core Graphics renderer for RLScene. Portable: compiles into the iOS app, the
// widget extension and the macOS server tool (tools/rl_render.swift), so the
// "server render", "app pre-render" and "in-extension offscreen render" paths
// draw identical pixels from identical data.

enum RLCG {
    struct Stats { var ms: Double; var pixels: Int; var ops: Int; var skipped: Int }

    /// Renders `scene` into an sRGB bitmap of `pw × ph` pixels, scene scaled uniformly to fit.
    /// `symbol` lets the iOS side draw SF Symbols (not available to plain CoreGraphics on a server).
    static func render(_ scene: RLScene, pw: Int, ph: Int, imageDir: URL?,
                       symbol: ((RLOp, CGContext) -> Bool)? = nil) -> (CGImage?, Stats) {
        let t0 = Date()
        guard pw > 0, ph > 0,
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return (nil, Stats(ms: 0, pixels: 0, ops: 0, skipped: 0)) }
        // y-down scene space
        let s = min(Double(pw) / scene.w, Double(ph) / scene.h)
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: (CGFloat(pw) - CGFloat(scene.w * s)) / 2, y: (CGFloat(ph) - CGFloat(scene.h * s)) / 2)
        ctx.scaleBy(x: CGFloat(s), y: CGFloat(s))
        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        if let bg = RLColor.cg(scene.bg) {
            ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: 0, width: scene.w, height: scene.h))
        }
        var skipped = 0
        for op in scene.ops {
            if !draw(op, in: ctx, imageDir: imageDir, symbol: symbol) { skipped += 1 }
        }
        let img = ctx.makeImage()
        return (img, Stats(ms: Date().timeIntervalSince(t0) * 1000, pixels: pw * ph, ops: scene.ops.count, skipped: skipped))
    }

    @discardableResult
    static func draw(_ op: RLOp, in ctx: CGContext, imageDir: URL?, symbol: ((RLOp, CGContext) -> Bool)?) -> Bool {
        ctx.saveGState(); defer { ctx.restoreGState() }
        if let a = op.alpha { ctx.setAlpha(CGFloat(a)) }
        switch op.k {
        case "rect", "oval", "line", "poly", "arc":
            guard let p = op.path else { return false }
            if let f = RLColor.cg(op.fill), op.k != "line", op.k != "arc" {
                ctx.addPath(p); ctx.setFillColor(f); ctx.fillPath()
            }
            if let st = RLColor.cg(op.stroke) {
                ctx.addPath(p); ctx.setStrokeColor(st); ctx.setLineWidth(CGFloat(op.lw ?? 1))
                ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.strokePath()
            }
            return true
        case "lgrad", "rgrad":
            let cols = (op.c ?? []).compactMap { RLColor.cg($0) }
            guard cols.count >= 2,
                  let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: cols as CFArray, locations: nil)
            else { return false }
            let rect = op.rect
            let clip = CGPath(roundedRect: rect, cornerWidth: min(op.r ?? 0, rect.width / 2), cornerHeight: min(op.r ?? 0, rect.height / 2), transform: nil)
            ctx.addPath(clip); ctx.clip()
            if op.k == "lgrad" {
                ctx.drawLinearGradient(g, start: CGPoint(x: rect.minX, y: rect.minY),
                                       end: CGPoint(x: op.x2 ?? rect.maxX, y: op.y2 ?? rect.maxY), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            } else {
                let c = CGPoint(x: rect.midX, y: rect.midY)
                ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: max(rect.width, rect.height) / 2, options: [.drawsAfterEndLocation])
            }
            return true
        case "text":
            drawText(op, ctx)
            return true
        case "img":
            guard let name = op.name, let dir = imageDir,
                  let src = CGImageSourceCreateWithURL(dir.appendingPathComponent(name) as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return false }
            let r = op.rect
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(op.r ?? 0, r.width / 2), cornerHeight: min(op.r ?? 0, r.height / 2), transform: nil))
            ctx.clip()
            // flip back for the image
            ctx.translateBy(x: 0, y: r.maxY + r.minY); ctx.scaleBy(x: 1, y: -1)
            ctx.draw(img, in: r)
            return true
        case "sym":
            return symbol?(op, ctx) ?? false
        default:
            return false
        }
    }

    static func ctFont(_ op: RLOp) -> CTFont {
        let size = CGFloat(op.size ?? 12)
        if let n = op.font, !n.isEmpty {
            let f = CTFontCreateWithName(n as CFString, size, nil)
            // CTFontCreateWithName silently falls back; accept only an exact match.
            if (CTFontCopyPostScriptName(f) as String) == n { return f }
        }
        let w: CGFloat
        switch op.weight {
        case "medium": w = 0.23; case "semibold": w = 0.3; case "bold": w = 0.4
        case "heavy": w = 0.56; case "black": w = 0.62; default: w = 0
        }
        let base = CTFontCreateUIFontForLanguage(.system, size, nil)!
        let desc = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(base),
            [kCTFontTraitsAttribute: [kCTFontWeightTrait: w]] as CFDictionary)
        return CTFontCreateWithFontDescriptor(desc, size, nil)
    }

    static func drawText(_ op: RLOp, _ ctx: CGContext) {
        let font = ctFont(op)
        let color = RLColor.cg(op.fill) ?? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let attr = NSAttributedString(string: op.t ?? "", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ])
        let line = CTLineCreateWithAttributedString(attr)
        var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &asc, &desc, &lead))
        var x = CGFloat(op.x ?? 0)
        if op.align == "center" { x -= width / 2 } else if op.align == "right" { x -= width }
        let baseline = CGFloat(op.y ?? 0) + asc
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)   // y-down space
        ctx.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, ctx)
    }

    // MARK: Encoding (used by app pre-render and the server tool)

    static func encode(_ img: CGImage, type: String, quality: Double = 0.85) -> Data? {
        let uti: CFString
        switch type {
        case "jpeg", "jpg": uti = "public.jpeg" as CFString
        case "heic": uti = "public.heic" as CFString
        default: uti = "public.png" as CFString
        }
        let data = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(data, uti, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dst) ? data as Data : nil
    }
}
