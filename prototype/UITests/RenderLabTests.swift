import XCTest

/// RenderLab Simulator automation (German SpringBoard labels).
/// Parameters come from TEST_RUNNER_* environment variables (xcodebuild strips the prefix):
///   RL_SWIPES   gallery swipes before "Widget hinzufügen" (selects kind + size)
///   RL_PREFIX   identifier prefix of hit regions to tap (default "rl-")
///   RL_EDGE     also tap 4 near-edge points per region at this inset in points (0 = centers only)
///   RL_GAP_MS   pause between taps
/// Output lines: AWL|<epoch ms>|<key>|<json>
final class RenderLabTests: XCTestCase {
    let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    var env: [String: String] { ProcessInfo.processInfo.environment }

    func emit(_ key: String, _ obj: [String: Any] = [:]) {
        let d = (try? JSONSerialization.data(withJSONObject: obj)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        print("AWL|\(Int(Date().timeIntervalSince1970 * 1000))|\(key)|\(d)")
    }

    func goHome() {
        XCUIDevice.shared.press(.home); usleep(700_000)
        XCUIDevice.shared.press(.home); usleep(500_000)
    }

    /// Dumps the widget gallery for our app after 0…N swipes (to learn the kind/size order).
    func testGalleryDump() {
        goHome()
        openGallery()
        let n = Int(env["RL_SWIPES"] ?? "8") ?? 8
        for i in 0...n {
            let texts = sb.staticTexts.allElementsBoundByIndex.prefix(40).map(\.label).filter { !$0.isEmpty }
            emit("gallery", ["swipes": i, "texts": Array(texts)])
            sb.swipeLeft(); usleep(700_000)
        }
        if sb.buttons["Abbrechen"].exists { sb.buttons["Abbrechen"].tap() }
        goHome()
    }

    func openGallery() {
        sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.80)).press(forDuration: 1.6)
        _ = sb.buttons["Bearbeiten"].waitForExistence(timeout: 3)
        sb.buttons["Bearbeiten"].tap()
        sb.buttons["Widget hinzufügen"].tap()
        let search = sb.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Agent")
        sb.cells["Agent Lab"].firstMatch.tap()
        sleep(1)
    }

    func testAddWidget() {
        goHome()
        openGallery()
        let n = Int(env["RL_SWIPES"] ?? "0") ?? 0
        for _ in 0..<n { sb.swipeLeft(); usleep(700_000) }
        let texts = sb.staticTexts.allElementsBoundByIndex.prefix(30).map(\.label)
        emit("adding", ["swipes": n, "texts": Array(texts)])
        sb.buttons.matching(NSPredicate(format: "label CONTAINS 'Widget hinzufügen'")).firstMatch.tap()
        sleep(1)
        if sb.buttons["Fertig"].exists { sb.buttons["Fertig"].tap() }
        sleep(1)
        goHome()
    }

    /// Lists every hit region (identifier prefix) with its on-screen frame.
    /// Launching the test runner switches SpringBoard to home page 2 (same artifact as simctl push);
    /// one Home press returns to page 1 where the RenderLab widgets live.
    func page1() { XCUIDevice.shared.press(.home); sleep(1) }

    func testRegionFrames() {
        page1()
        let prefix = env["RL_PREFIX"] ?? "rl-"
        let els = sb.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).allElementsBoundByIndex
        let all = sb.buttons.allElementsBoundByIndex.prefix(80).map { "\($0.identifier)|\($0.label)" }
        emit("buttons_debug", ["n": all.count, "items": Array(all), "tree": String(sb.debugDescription.prefix(3000))])
        emit("regions", ["count": els.count, "items": els.map { ["id": $0.identifier, "label": $0.label, "type": $0.elementType.rawValue,
                                                                  "hittable": $0.isHittable,
                                                                  "x": $0.frame.minX, "y": $0.frame.minY, "w": $0.frame.width, "h": $0.frame.height] }])
    }

    /// Taps every region by *coordinate* (center, optionally near-edge points) and records
    /// the intended region + tap time. The host matches these against rl_hit events.
    func testTapRegions() {
        let prefix = env["RL_PREFIX"] ?? "rl-"
        let edge = Double(env["RL_EDGE"] ?? "0") ?? 0
        let gap = UInt32(Int(env["RL_GAP_MS"] ?? "1500") ?? 1500) * 1000
        let limit = Int(env["RL_LIMIT"] ?? "400") ?? 400
        page1()
        let els = sb.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).allElementsBoundByIndex
        let frames = els.prefix(limit).map { ($0.identifier, $0.frame) }
        emit("tap_plan", ["regions": frames.count])
        let origin = sb.coordinate(withNormalizedOffset: .zero)
        for (id, f) in frames {
            var pts = [(CGFloat(f.midX), CGFloat(f.midY), "c")]
            if edge > 0 {
                let e = CGFloat(edge)
                pts += [(f.minX + e, f.midY, "l"), (f.maxX - e, f.midY, "r"), (f.midX, f.minY + e, "t"), (f.midX, f.maxY - e, "b")]
            }
            for (x, y, tag) in pts {
                let t = Date().timeIntervalSince1970
                origin.withOffset(CGVector(dx: x, dy: y)).tap()
                emit("tap", ["want": String(id.dropFirst(3)), "pt": tag, "x": x, "y": y, "t": Int(t * 1000)])
                usleep(gap)
            }
        }
        emit("tap_done")
    }

    /// Taps explicit screen points (pt) computed on the host from agent scene coordinates.
    /// RL_POINTS = base64(JSON [[want, x, y, tag], …]). Proves touch routing without relying
    /// on the accessibility tree.
    func testTapPoints() {
        let gap = UInt32(Int(env["RL_GAP_MS"] ?? "1300") ?? 1300) * 1000
        guard let b = env["RL_POINTS"], let d = Data(base64Encoded: b),
              let pts = try? JSONSerialization.jsonObject(with: d) as? [[Any]] else { return XCTFail("RL_POINTS") }
        page1()
        let origin = sb.coordinate(withNormalizedOffset: .zero)
        emit("tap_plan", ["points": pts.count])
        for p in pts {
            guard let want = p[0] as? String, let x = p[1] as? Double, let y = p[2] as? Double else { continue }
            let t = Date().timeIntervalSince1970
            origin.withOffset(CGVector(dx: x, dy: y)).tap()
            emit("tap", ["want": want, "x": x, "y": y, "pt": (p.count > 3 ? p[3] as? String : nil) ?? "c", "t": Int(t * 1000)])
            usleep(gap)
        }
        emit("tap_done")
    }
}
