// macOS "server" renderer: same RLScene + RLCG code as the app and widget extension.
// Build: swiftc -O -o tools/runtime/rl_render prototype/RenderLab/RLScene.swift prototype/RenderLab/RLCoreGraphics.swift tools/rl/main.swift
// Usage: rl_render <scene.json> <out.(png|jpg|heic)> <pw> <ph> [imageDir] [quality]
import Foundation
let a = CommandLine.arguments
guard a.count >= 5, let d = FileManager.default.contents(atPath: a[1]), let scene = RLScene.load(d),
      let pw = Int(a[3]), let ph = Int(a[4]) else { print("usage"); exit(2) }
let dir = a.count > 5 ? URL(fileURLWithPath: a[5]) : nil
let q = a.count > 6 ? Double(a[6]) ?? 0.85 : 0.85
let (img, st) = RLCG.render(scene, pw: pw, ph: ph, imageDir: dir)
let t0 = Date()
guard let img, let out = RLCG.encode(img, type: (a[2] as NSString).pathExtension.lowercased(), quality: q) else { print("render failed"); exit(1) }
try out.write(to: URL(fileURLWithPath: a[2]))
print("{\"renderMs\":\(Int(st.ms)),\"encodeMs\":\(Int(Date().timeIntervalSince(t0) * 1000)),\"bytes\":\(out.count),\"ops\":\(st.ops),\"skipped\":\(st.skipped)}")
