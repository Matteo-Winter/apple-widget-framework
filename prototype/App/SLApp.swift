import UIKit
import WidgetKit
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif

/// SurfaceLab commands for the app (Live Activities, rich notifications, reloads).
/// Triggered by `simctl launch <bundle> -slcmd <base64 JSON>` (foreground) or a silent push {"surfacelab": {...}}.
enum SLApp {
    @MainActor
    static func handle(_ cmd: [String: Any]) async {
        let op = cmd["op"] as? String ?? "reload"
        Log.event("sl_cmd", detail: "op=\(op) appState=\(UIApplication.shared.applicationState.rawValue)")
        switch op {
        case "la-start":
            #if canImport(ActivityKit)
            let names = cmd["names"] as? [String] ?? ["Agent 1"]
            let colors = ["#FF7A18", "#4DA3FF", "#7CFFB2", "#C77DFF", "#FF3B30", "#FFD166"]
            for (i, n) in names.enumerated() {
                do {
                    let a = try Activity.request(attributes: SLActivityAttributes(name: n),
                                                 content: ActivityContent(state: .init(label: "started", color: colors[i % colors.count], rev: 1, h: cmd["h"] as? Double), staleDate: nil))
                    Log.event("sl_la_started", detail: "name=\(n) id=\(a.id) total=\(Activity<SLActivityAttributes>.activities.count)")
                } catch {
                    Log.event("sl_la_failed", detail: "name=\(n) \(error.localizedDescription)")
                }
            }
            #endif
        case "la-end":
            #if canImport(ActivityKit)
            for a in Activity<SLActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
            for a in Activity<AgentActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
            Log.event("sl_la_ended")
            #endif
        case "notify":
            await registerCategory()
            let c = UNMutableNotificationContent()
            c.title = "SurfaceLab"; c.body = "Long-press to expand the custom content extension"
            c.categoryIdentifier = "SL_RICH"; c.interruptionLevel = .timeSensitive
            let delay = cmd["delay"] as? Double ?? 3
            let r = UNNotificationRequest(identifier: "sl-\(Int(Date().timeIntervalSince1970))", content: c,
                                          trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false))
            do { try await UNUserNotificationCenter.current().add(r); Log.event("sl_notify_scheduled", detail: "delay=\(delay)") }
            catch { Log.event("sl_notify_failed", detail: error.localizedDescription) }
        default:
            break
        }
        WidgetCenter.shared.reloadAllTimelines()
        Log.event("reload_requested", detail: "surfacelab")
    }

    static func registerCategory() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        var cats = await center.notificationCategories()
        cats = cats.filter { $0.identifier != "SL_RICH" }
        cats.insert(UNNotificationCategory(identifier: "SL_RICH",
                                           actions: [UNNotificationAction(identifier: "sl-ok", title: "OK (system action)", options: [])],
                                           intentIdentifiers: [], options: []))
        center.setNotificationCategories(cats)
    }
}
