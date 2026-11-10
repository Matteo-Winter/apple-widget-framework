import XCTest

/// SurfaceLab Simulator automation (German SpringBoard). Screenshots are written to
/// SL_SHOT_DIR (host path) when the Simulator allows it, and always attached to the result.
/// Output lines: AWL|<epoch ms>|<key>|<json>
final class SurfaceTests: XCTestCase {
    let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    var env: [String: String] { ProcessInfo.processInfo.environment }

    func emit(_ key: String, _ obj: [String: Any] = [:]) {
        let d = (try? JSONSerialization.data(withJSONObject: obj)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        print("AWL|\(Int(Date().timeIntervalSince1970 * 1000))|\(key)|\(d)")
    }

    func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s); a.name = name; a.lifetime = .keepAlways; add(a)
        if let dir = env["SL_SHOT_DIR"] {
            let ok = (try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))) != nil
            emit("shot", ["name": name, "written": ok])
        }
    }

    func frames(_ q: XCUIElementQuery) -> [[String: Any]] {
        q.allElementsBoundByIndex.map { ["id": $0.identifier, "label": $0.label, "value": "\($0.value ?? "")",
                                         "x": $0.frame.minX, "y": $0.frame.minY, "w": $0.frame.width, "h": $0.frame.height] }
    }

    /// All widget containers on the current Home Screen page (SpringBoard exposes them as Icon with value "Widget").
    func testWidgetFrames() {
        if env["SL_HOME"] == "1" { XCUIDevice.shared.press(.home); sleep(1) }
        let w = sb.icons.matching(NSPredicate(format: "value == 'Widget'"))
        let screen = sb.windows.firstMatch.frame
        emit("widget_frames", ["screen": ["w": screen.width, "h": screen.height], "widgets": frames(w)])
        emit("tree", ["tree": String(sb.debugDescription.prefix(6000))])
        shot(env["SL_NAME"] ?? "widgets")
    }

    /// Dynamic Island: compact (as is) and expanded (long press on the island).
    func testIsland() {
        XCUIDevice.shared.press(.home); sleep(2)
        shot("island-compact")
        emit("hold", ["what": "island-compact"]); sleep(UInt32(env["SL_HOLD"] ?? "0") ?? 0)
        let island = sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04))
        island.press(forDuration: 1.2)
        sleep(1)
        shot("island-expanded")
        emit("hold", ["what": "island-expanded"]); sleep(UInt32(env["SL_HOLD"] ?? "0") ?? 0)
        emit("island_tree", ["tree": String(sb.debugDescription.prefix(4000))])
        if let x = Double(env["SL_TAP_X"] ?? ""), let y = Double(env["SL_TAP_Y"] ?? "") {
            sb.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y)).tap()
            emit("island_tap", ["x": x, "y": y]); sleep(2); shot("island-after-tap")
        }
        XCUIDevice.shared.press(.home); sleep(1)
    }

    /// Rich notification: wait for the banner, long-press to expand the content extension,
    /// then exercise button, text field and scrolling by coordinates.
    func testNotificationExpand() {
        XCUIDevice.shared.press(.home); sleep(1)
        let banner = sb.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'SurfaceLab' OR label CONTAINS 'Long-press'")).firstMatch
        let found = banner.waitForExistence(timeout: Double(env["SL_WAIT"] ?? "15") ?? 15)
        emit("banner", ["found": found, "frame": found ? ["x": banner.frame.minX, "y": banner.frame.minY, "w": banner.frame.width, "h": banner.frame.height] : [:]])
        guard found else { shot("notif-no-banner"); return }
        shot("notif-banner")
        banner.press(forDuration: 1.5)
        sleep(2)
        shot("notif-expanded")
        emit("hold", ["what": "notif-expanded"]); sleep(UInt32(env["SL_HOLD"] ?? "0") ?? 0)
        emit("notif_tree", ["tree": String(sb.debugDescription.prefix(8000))])
        let origin = sb.coordinate(withNormalizedOffset: .zero)
        for (k, v) in [("BUTTON", "button"), ("FIELD", "field"), ("SCROLL", "scroll")] {
            guard let x = Double(env["SL_\(k)_X"] ?? ""), let y = Double(env["SL_\(k)_Y"] ?? "") else { continue }
            let p = origin.withOffset(CGVector(dx: x, dy: y))
            switch v {
            case "scroll": p.press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: x, dy: y - 220)))
            case "field": p.tap(); sleep(1); sb.typeText("agent reply\n")
            default: p.tap()
            }
            emit("notif_action", ["what": v, "x": x, "y": y]); sleep(1)
        }
        shot("notif-after-actions")
        emit("hold", ["what": "notif-after-actions"]); sleep(UInt32(env["SL_HOLD"] ?? "0") ?? 0)
    }

    /// Add a widget from the gallery after N swipes (same flow as RenderLabTests.testAddWidget).
    func testAdd() {
        XCUIDevice.shared.press(.home); sleep(1)
        if env["SL_PAGE_SWIPE"] == "1" { sb.swipeLeft(); sleep(1) }
        sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).press(forDuration: 1.6)
        _ = sb.buttons["Bearbeiten"].waitForExistence(timeout: 3)
        sb.buttons["Bearbeiten"].tap()
        sb.buttons["Widget hinzufügen"].tap()
        let search = sb.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Agent")
        sb.cells["Agent Lab"].firstMatch.tap(); sleep(1)
        let n = Int(env["SL_SWIPES"] ?? "0") ?? 0
        for _ in 0..<n { sb.swipeLeft(); usleep(700_000) }
        emit("adding", ["swipes": n, "texts": sb.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label)])
        sb.buttons.matching(NSPredicate(format: "label CONTAINS 'Widget hinzufügen'")).firstMatch.tap()
        sleep(1)
        if sb.buttons["Fertig"].exists { sb.buttons["Fertig"].tap() }
        sleep(1)
    }

    /// Taps explicit screen points (pt); RL_POINTS-compatible format, base64 JSON [[want,x,y,tag],…].
    func testTapPoints() {
        let gap = UInt32(Int(env["SL_GAP_MS"] ?? "1300") ?? 1300) * 1000
        guard let b = env["SL_POINTS"], let d = Data(base64Encoded: b),
              let pts = try? JSONSerialization.jsonObject(with: d) as? [[Any]] else { return XCTFail("SL_POINTS") }
        if env["SL_NOHOME"] != "1" {   // a Home press on the Lock Screen would unlock the (passcode-less) Simulator
            XCUIDevice.shared.press(.home); sleep(1)
            for _ in 0..<(Int(env["SL_PAGE"] ?? "0") ?? 0) { sb.swipeLeft(); sleep(1) }   // Home press lands on page 0
        }
        let origin = sb.coordinate(withNormalizedOffset: .zero)
        for p in pts {
            guard let want = p[0] as? String, let x = p[1] as? Double, let y = p[2] as? Double else { continue }
            let t = Date().timeIntervalSince1970
            origin.withOffset(CGVector(dx: x, dy: y)).tap()
            emit("tap", ["want": want, "x": x, "y": y, "pt": "c", "t": Int(t * 1000)])
            usleep(gap)
        }
    }

    /// Removes every widget on the current Home Screen page (lab Simulator only).
    func testRemoveWidgets() {
        XCUIDevice.shared.press(.home); sleep(1)
        for _ in 0..<8 {
            // Only our own widgets (label = app name "Agent Lab") on the visible page; never other apps' widgets.
            let only = env["SL_ONLY_Y"].flatMap(Double.init)
            guard let w = sb.icons.matching(NSPredicate(format: "value == 'Widget' AND label == 'Agent Lab'")).allElementsBoundByIndex
                .first(where: { $0.frame.width > 0 && $0.frame.minX >= 0 && $0.frame.minX < 400 && (only == nil || abs($0.frame.minY - only!) < 5) })
            else { break }
            w.press(forDuration: 1.5)
            let rm = sb.descendants(matching: .any).matching(NSPredicate(format: "label == 'Widget entfernen'")).firstMatch
            guard rm.waitForExistence(timeout: 3) else { emit("remove_failed", ["tree": String(sb.debugDescription.prefix(3000))]); break }
            rm.tap()
            let ok = sb.descendants(matching: .any).matching(NSPredicate(format: "label == 'Entfernen'")).firstMatch
            if ok.waitForExistence(timeout: 3) { ok.tap() }
            sleep(1)
            emit("removed", ["label": w.label])
        }
        if sb.buttons["Fertig"].exists { sb.buttons["Fertig"].tap() }
    }

    /// Inventory: widget frames + screenshot of the first SL_PAGES Home Screen pages.
    func testPages() {
        XCUIDevice.shared.press(.home); sleep(1)
        let n = Int(env["SL_PAGES"] ?? "4") ?? 4
        for i in 0..<n {
            let w = sb.icons.matching(NSPredicate(format: "value == 'Widget'")).allElementsBoundByIndex
                .filter { $0.frame.width > 0 && $0.frame.minX >= 0 && $0.frame.minX < 400 }
            let icons = sb.icons.allElementsBoundByIndex.filter { $0.frame.width > 0 && $0.frame.minX >= 0 && $0.frame.minX < 400 && "\($0.value ?? "")" != "Widget" }.prefix(24)
            emit("icons", ["index": i, "icons": icons.map { ["label": $0.label, "x": $0.frame.minX, "y": $0.frame.minY, "w": $0.frame.width, "h": $0.frame.height] }])
            emit("page", ["index": i, "widgets": w.map { ["label": $0.label, "x": $0.frame.minX, "y": $0.frame.minY, "w": $0.frame.width, "h": $0.frame.height] }])
            shot("page-\(i)")
            sb.swipeLeft(); sleep(1)
        }
        XCUIDevice.shared.press(.home); sleep(1)
    }

    /// Exploratory: Lock Screen customisation (device must already be locked by the host).
    /// SL_STEPS = comma list of labels to tap in order; dumps the tree after each step.
    func testLockCustomize() {
        let hold = UInt32(env["SL_HOLD"] ?? "3") ?? 3
        if let a = env["SL_PRE"], !a.isEmpty { let e = sb.descendants(matching: .any).matching(NSPredicate(format: "label == %@", a)).firstMatch; if e.waitForExistence(timeout: 3) { e.tap(); sleep(2) } }
        sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: Double(env["SL_LP_Y"] ?? "0.45") ?? 0.45)).press(forDuration: 2.5)
        sleep(2)
        emit("lc_tree", ["step": "longpress", "tree": String(sb.debugDescription.prefix(5000))])
        emit("hold", ["what": "lc-0-longpress"]); sleep(hold)
        for (i, l) in (env["SL_STEPS"] ?? "").split(separator: ",").map(String.init).enumerated() where !l.isEmpty {
            let e = sb.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR identifier == %@", l, l)).firstMatch
            let found = e.waitForExistence(timeout: 4)
            if found { e.tap() }
            sleep(2)
            emit("lc_tree", ["step": l, "found": found, "tree": String(sb.debugDescription.prefix(5000))])
            emit("hold", ["what": "lc-\(i + 1)"]); sleep(hold)
        }
    }

    /// Exploratory: open Control Center (swipe down from the top-right corner) and dump its tree.
    func testControlCenter() {
        XCUIDevice.shared.press(.home); sleep(1)
        let start = sb.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.005))
        start.press(forDuration: 0.1, thenDragTo: sb.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.6)))
        sleep(2)
        emit("cc_tree", ["tree": String(sb.debugDescription.prefix(6000))])
        emit("hold", ["what": "cc-open"]); sleep(UInt32(env["SL_HOLD"] ?? "3") ?? 3)
        for (i, l) in (env["SL_STEPS"] ?? "").split(separator: ",").map(String.init).enumerated() where !l.isEmpty {
            let e = sb.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR identifier == %@", l, l)).firstMatch
            let found = e.waitForExistence(timeout: 4)
            if found { e.tap() }
            sleep(2)
            emit("cc_tree", ["step": l, "found": found, "tree": String(sb.debugDescription.prefix(6000))])
            emit("hold", ["what": "cc-\(i + 1)"]); sleep(UInt32(env["SL_HOLD"] ?? "3") ?? 3)
        }
        XCUIDevice.shared.press(.home); sleep(1)
    }

    /// Coordinate-only steps with host screenshots (for system UIs missing from the AX tree).
    /// SL_OPEN_CC=1 opens Control Center first. SL_STEPS_XY = "x,y;x,y;…" (pt), "type:<text>" types text.
    func testCoordSteps() {
        let hold = UInt32(env["SL_HOLD"] ?? "2") ?? 2
        if env["SL_NOHOME"] != "1" { XCUIDevice.shared.press(.home); sleep(1) }
        if env["SL_OPEN_CC"] == "1" {
            sb.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.005))
                .press(forDuration: 0.1, thenDragTo: sb.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.6)))
            sleep(2)
        }
        emit("hold", ["what": "step-0"]); sleep(hold)
        let origin = sb.coordinate(withNormalizedOffset: .zero)
        for (i, st) in (env["SL_STEPS_XY"] ?? "").split(separator: ";").map(String.init).enumerated() {
            if st.hasPrefix("type:") { sb.typeText(String(st.dropFirst(5))) }
            else {
                let v = st.split(separator: ",").compactMap { Double($0) }
                if v.count == 2 { origin.withOffset(CGVector(dx: v[0], dy: v[1])).tap() }
                if v.count == 3 { origin.withOffset(CGVector(dx: v[0], dy: v[1])).press(forDuration: v[2]) }
            }
            sleep(2)
            emit("hold", ["what": "step-\(i + 1)"]); sleep(hold)
        }
    }
}
