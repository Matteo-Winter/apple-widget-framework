import UIKit
import WebKit
import WidgetKit

/// App-side pre-rendering for RenderLab: the app (not the widget extension)
/// produces the pixels and hands a finished bitmap to WidgetKit via the App Group.
///   op=cg    RLScene → CoreGraphics → PNG/JPEG/HEIC
///   op=html  HTML/CSS → WKWebView snapshot → PNG/JPEG/HEIC
///   op=reload  only reload RenderLab timelines
/// Triggered by silent push payload {"renderlab": {...}} or agentlab://renderlab?...
enum RLPrerender {
    @MainActor
    static func handle(_ cmd: [String: Any]) async {
        if let jobs = cmd["jobs"] as? [[String: Any]] {
            for j in jobs { await run(j) }
        } else { await run(cmd) }
        WidgetCenter.shared.reloadTimelines(ofKind: RLKind.widget)
        WidgetCenter.shared.reloadTimelines(ofKind: RLKind.widget + "Margins")
        Log.event("reload_requested", detail: "renderlab")
    }

    @MainActor
    static func run(_ cmd: [String: Any]) async {
        let op = cmd["op"] as? String ?? "reload"
        let out = cmd["out"] as? String ?? "prerender.png"
        let type = cmd["type"] as? String ?? (out as NSString).pathExtension
        let pw = cmd["pw"] as? Int ?? 1086, ph = cmd["ph"] as? Int ?? 510
        let q = cmd["quality"] as? Double ?? 0.85
        let t0 = Date(), m0 = RLMetrics.footprintMB()
        var detail = ""
        switch op {
        case "cg":
            if let sc = RLStore.scene(cmd["scene"] as? String) {
                let (img, st) = RLCG.render(sc, pw: pw, ph: ph, imageDir: RLStore.dir, symbol: nil)
                let te = Date()
                if let img, let d = RLCG.encode(img, type: type, quality: q), let u = RLStore.url(out) {
                    try? d.write(to: u, options: .atomic)
                    detail = "renderMs=\(Int(st.ms)) encodeMs=\(RLMetrics.ms(since: te)) bytes=\(d.count)"
                } else { detail = "cg failed" }
            }
        case "html":
            if let name = cmd["html"] as? String, let d = RLStore.data(name), let html = String(data: d, encoding: .utf8) {
                let scale = cmd["scale"] as? Double ?? 3
                let size = CGSize(width: Double(pw) / scale, height: Double(ph) / scale)
                if let img = await snapshot(html: html, size: size, scale: scale), let cg = img.cgImage {
                    let te = Date()
                    if let enc = RLCG.encode(cg, type: type, quality: q), let u = RLStore.url(out) {
                        try? enc.write(to: u, options: .atomic)
                        detail = "snapshotMs=\(Int(Date().timeIntervalSince(t0) * 1000)) encodeMs=\(RLMetrics.ms(since: te)) bytes=\(enc.count) px=\(cg.width)x\(cg.height)"
                    }
                } else { detail = "webview snapshot failed appState=\(UIApplication.shared.applicationState.rawValue)" }
            }
        default:
            detail = "reload only"
        }
        Log.event("rl_prerender", detail: "op=\(op) out=\(out) totalMs=\(RLMetrics.ms(since: t0)) memBefore=\(String(format: "%.1f", m0)) memAfter=\(String(format: "%.1f", RLMetrics.footprintMB())) appState=\(UIApplication.shared.applicationState.rawValue) \(detail)")
    }

    private static var keep: [WKWebView] = []

    @MainActor
    static func snapshot(html: String, size: CGSize, scale: Double) async -> UIImage? {
        let cfg = WKWebViewConfiguration()
        cfg.suppressesIncrementalRendering = true
        let wv = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: cfg)
        wv.isOpaque = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        // WKWebView only paints when it is in a window; park it off-screen.
        let host = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.windows.first }.first
        if let host { wv.frame.origin = CGPoint(x: -size.width * 4, y: 0); host.addSubview(wv) }
        keep.append(wv)
        defer { wv.removeFromSuperview(); keep.removeAll { $0 === wv } }
        let loader = Loader()
        wv.navigationDelegate = loader
        wv.loadHTMLString(html, baseURL: RLStore.dir)
        let ok = await loader.wait(timeout: 8)
        guard ok else { return nil }
        try? await Task.sleep(nanoseconds: 150_000_000)   // fonts/layout settle
        let c = WKSnapshotConfiguration()
        c.rect = CGRect(origin: .zero, size: size)
        c.snapshotWidth = NSNumber(value: Double(size.width))
        c.afterScreenUpdates = true
        let img = try? await wv.takeSnapshot(configuration: c)
        guard let img else { return nil }
        // takeSnapshot returns the screen scale; re-render at the requested pixel size
        let f = UIGraphicsImageRendererFormat(); f.scale = scale; f.opaque = false
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    }

    private final class Loader: NSObject, WKNavigationDelegate {
        private var cont: CheckedContinuation<Bool, Never>?
        private var done: Bool?
        func wait(timeout: Double) async -> Bool {
            if let d = done { return d }
            return await withCheckedContinuation { c in
                cont = c
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.finish(false) }
            }
        }
        private func finish(_ ok: Bool) {
            if done == nil { done = ok }
            cont?.resume(returning: ok); cont = nil
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish(true) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(false) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(false) }
    }
}
