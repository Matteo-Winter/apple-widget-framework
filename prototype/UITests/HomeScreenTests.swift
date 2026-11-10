import XCTest

/// Simulator-only automation of SpringBoard (German UI labels of the lab simulator).
/// Adds the widget, then measures latencies through the accessibility tree.
/// Every measurement line is printed as  AWL|<epoch ms>|<key>|<json>  for tools/parse_uitest.py.
final class HomeScreenTests: XCTestCase {
    let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let app = XCUIApplication()

    func emit(_ key: String, _ obj: [String: Any] = [:]) {
        let d = (try? JSONSerialization.data(withJSONObject: obj)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        print("AWL|\(Int(Date().timeIntervalSince1970 * 1000))|\(key)|\(d)")
    }

    var now: Double { Date().timeIntervalSince1970 }

    /// Polls the SpringBoard accessibility tree until `predicate` matches. Returns seconds or nil.
    func waitFor(_ predicate: NSPredicate, timeout: Double, in root: XCUIElement? = nil) -> Double? {
        let t0 = now
        let q = (root ?? sb).descendants(matching: .any).matching(predicate)
        while now - t0 < timeout {
            if q.firstMatch.exists { return now - t0 }
        }
        return nil
    }

    func label(_ s: String) -> NSPredicate { NSPredicate(format: "label CONTAINS %@", s) }
    func ident(_ s: String) -> NSPredicate { NSPredicate(format: "identifier == %@", s) }

    /// Seconds until no element matches (layout no longer contains it).
    func waitGone(_ predicate: NSPredicate, timeout: Double) -> Double? {
        let t0 = now
        let q = sb.descendants(matching: .any).matching(predicate)
        while now - t0 < timeout { if !q.firstMatch.exists { return now - t0 } }
        return nil
    }

    func goHome() {
        XCUIDevice.shared.press(.home); usleep(700_000)
        XCUIDevice.shared.press(.home); usleep(500_000)   // second press → first page
    }

    func publish(_ preset: String, reload: Bool = true) -> Double {
        app.open(URL(string: "agentlab://preset/\(preset)?reload=\(reload ? 1 : 0)")!)
        _ = app.wait(for: .runningForeground, timeout: 5)
        let t = now
        emit("published", ["preset": preset, "reload": reload])
        return t
    }

    func testZ_DumpHome() {
        if sb.buttons["Abbrechen"].exists { sb.buttons["Abbrechen"].tap() }
        _ = publish("decision", reload: true)
        goHome(); goHome()
        sleep(3)
        emit("home_tree", ["tree": sb.debugDescription])
    }

    // MARK: - Setup

    func testA_AddWidgets() {
        goHome()
        for page in [1, 0] {             // medium, then small
            sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)).press(forDuration: 1.6)
            _ = sb.buttons["Bearbeiten"].waitForExistence(timeout: 3)
            sb.buttons["Bearbeiten"].tap()
            sb.buttons["Widget hinzufügen"].tap()
            let search = sb.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.tap(); search.typeText("Agent")
            sb.cells["Agent Lab"].firstMatch.tap()
            sleep(1)
            for _ in 0..<page { sb.swipeLeft(); usleep(600_000) }
            sb.buttons.matching(label("Widget hinzufügen")).firstMatch.tap()
            sleep(1)
            if sb.buttons["Fertig"].exists { sb.buttons["Fertig"].tap() }
            sleep(1)
        }
        emit("widgets_added", ["tree": String(sb.debugDescription.prefix(4000))])
    }

    // MARK: - E01 publish in app → visible on Home Screen (app foreground, reload requested)

    func testB_PublishToVisible() {
        for i in 0..<8 {
            let preset = i % 2 == 0 ? "decision" : "status"
            let tPub = publish(preset, reload: true)
            goHome()
            let tHome = now
            let dt = preset == "decision" ? waitFor(ident("action-investigate"), timeout: 20)
                                          : waitGone(ident("action-investigate"), timeout: 20)
            emit("E01_visible", ["iter": i, "preset": preset, "secondsAfterHome": dt ?? -1,
                                 "secondsAfterPublish": dt.map { $0 + (tHome - tPub) } ?? -1])
        }
    }

    // MARK: - E03 tap widget button → new layout (app not launched)

    func testC_TapLatency() {
        for i in 0..<10 {
            _ = publish("decision", reload: true)
            goHome()
            app.terminate()  // app NOT running: proves the intent needs no foreground app
            guard waitFor(ident("action-investigate"), timeout: 20) != nil else { emit("E03_setup_failed", ["iter": i]); continue }
            let button = sb.buttons.matching(ident("action-investigate")).firstMatch
            let tap0 = now
            button.tap()
            let tapDone = now
            let dt = waitGone(ident("action-investigate"), timeout: 20)
            emit("E03_tap", ["iter": i, "tapStart": tap0, "tapCallSeconds": tapDone - tap0,
                             "visibleSecondsAfterTapStart": dt.map { $0 + (tapDone - tap0) } ?? -1,
                             "appState": app.state.rawValue])
            sleep(1)
        }
    }

    // MARK: - E05/E06 replay: double tap must yield exactly one response

    func testD_DoubleTap() {
        _ = publish("decision", reload: true)
        goHome()
        guard waitFor(ident("action-investigate"), timeout: 20) != nil else { return XCTFail("widget not showing decision") }
        let inv = sb.buttons.matching(ident("action-investigate")).firstMatch
        let rev = sb.buttons.matching(ident("action-revert")).firstMatch
        let a = inv.frame, b = rev.frame
        let ca = sb.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: a.midX, dy: a.midY))
        let cb = sb.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: b.midX, dy: b.midY))
        ca.tap(); cb.tap(); ca.tap()   // coordinate taps: no waiting for idle between taps
        sleep(3)
        emit("E06_double_tap_done")
    }

    // MARK: - Widget capacity: how many buttons are hittable in each size

    func testE_Capacity() {
        for preset in ["decision4", "grid8", "list"] {
            _ = publish(preset, reload: true)
            goHome()
            sleep(3)
            let buttons = sb.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'action-'")).allElementsBoundByIndex
            emit("capacity", ["preset": preset, "buttons": buttons.map { ["label": $0.label, "hittable": $0.isHittable,
                                                                           "w": $0.frame.width, "h": $0.frame.height] }])
        }
    }

    // MARK: - Phase 4 round trip with tools/agent_demo.py running on the host

    func testH_RoundTrip() {
        goHome()
        guard let appear = waitFor(ident("action-fix"), timeout: 90) else { return XCTFail("decision never appeared") }
        emit("RT_decision_visible", ["waitedSeconds": appear])
        let b = sb.buttons.matching(ident("action-fix")).firstMatch
        let t0 = now
        b.tap()
        let gone = waitGone(ident("action-fix"), timeout: 20)
        emit("RT_tap", ["tapStart": t0, "layoutChangedSecondsAfterTapStart": gone ?? -1, "appState": app.state.rawValue])
        sleep(3)
        emit("RT_after_tree", ["tree": String(sb.debugDescription.prefix(3000))])
    }

    // MARK: - Live Activity + Dynamic Island interaction

    func testG_LiveActivity() {
        app.open(URL(string: "agentlab://la/end")!)
        sleep(1)
        _ = publish("decision", reload: true)
        app.open(URL(string: "agentlab://la/start")!)
        sleep(2)
        goHome()
        sleep(2)
        emit("LA_home_tree", ["tree": String(sb.debugDescription.prefix(5000))])
        // Expand the Dynamic Island (long press on the island region at top center).
        let island = sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.025))
        island.press(forDuration: 1.2)
        sleep(1)
        let expanded = sb.buttons.matching(ident("action-investigate")).firstMatch
        emit("LA_expanded", ["buttonFound": expanded.exists, "tree": String(sb.debugDescription.prefix(5000))])
        if expanded.exists {
            let t0 = now
            expanded.tap()
            let gone = waitGone(ident("action-investigate"), timeout: 15)
            emit("LA_tap", ["tapStart": t0, "goneSeconds": gone ?? -1, "appState": app.state.rawValue])
        }
    }

    // MARK: - Interactive notification with text input (no app UI opened)

    func testI_NotificationText() {
        app.open(URL(string: "agentlab://perm")!)
        let allow = sb.buttons["Erlauben"]
        if allow.waitForExistence(timeout: 4) { allow.tap() }
        _ = publish("decision", reload: true)
        app.open(URL(string: "agentlab://notify/text?delay=6")!)
        goHome()
        sleep(6)
        emit("NT_banner_tree", ["tree": sb.debugDescription])
        let banner = sb.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'commit message'")).firstMatch
        guard banner.waitForExistence(timeout: 6) else { return emit("NT_no_banner") }
        banner.press(forDuration: 1.0)   // long-look with actions
        sleep(1)
        emit("NT_expanded", ["tree": sb.debugDescription])
        let reply = sb.buttons["Reply"]
        if reply.waitForExistence(timeout: 3) {
            reply.tap()
            sleep(1)
            let field = sb.textFields.firstMatch.exists ? sb.textFields.firstMatch : sb.textViews.firstMatch
            field.typeText("ship it after lunch")
            let send = sb.buttons["Send"]
            let t0 = now
            if send.exists { send.tap() } else { field.typeText("\n") }
            sleep(3)
            emit("NT_sent", ["tapStart": t0, "appState": app.state.rawValue])
        } else {
            emit("NT_no_reply_button")
        }
    }

    // MARK: - E06b stale card: widget shows revision N, store already has N+1 → tap must be rejected

    func testJ_StaleCard() {
        _ = publish("decision", reload: true)
        goHome()
        guard waitFor(ident("action-investigate"), timeout: 20) != nil else { return XCTFail("no decision") }
        app.open(URL(string: "agentlab://bumprev")!)
        sleep(1)
        goHome()
        let t0 = now
        sb.buttons.matching(ident("action-investigate")).firstMatch.tap()
        sleep(3)
        emit("E06b_stale_tap", ["tapStart": t0, "buttonsStillThere": sb.buttons.matching(ident("action-investigate")).firstMatch.exists])
    }
}
