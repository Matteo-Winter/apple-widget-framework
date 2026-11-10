import SwiftUI
import WidgetKit
import UserNotifications
import BackgroundTasks
import ActivityKit

@main
struct AgentWidgetLabApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            LabView()
                .onOpenURL { Automation.handle($0) }
        }
        .onChange(of: phase) { _, p in Log.event("scene_\(p)") }
    }
}

// MARK: - Publishing

enum Publisher {
    /// The whole "agent changes the UI" path inside the app: write + optional reload.
    @discardableResult
    static func publish(_ surface: Surface, reload: Bool, source: String) -> Bool {
        var s = surface
        let cur = Store.loadSurface()
        if s.agent == cur.agent || s.revision <= cur.revision { s.revision = max(s.revision, cur.revision + 1) }
        s.issuedAt = ISO.string()
        Log.event("publish", rev: s.revision, detail: "\(source) \(s.id) reload=\(reload)")
        guard Store.save(s, force: true) else { return false }
        if reload {
            WidgetCenter.shared.reloadAllTimelines()
            Log.event("reload_requested", rev: s.revision)
        }
        Notifications.registerCategory(for: s)
        return true
    }
}

// MARK: - Automation (URL scheme so Mac scripts can drive the simulator/device)
// agentlab://preset/<name>?reload=1   agentlab://la/start|update|end
// agentlab://notify/choice|text       agentlab://config?bridge=<url>&pull=1&post=1
// agentlab://pull?reload=1            agentlab://bg/schedule

enum Automation {
    static func handle(_ url: URL) {
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func v(_ k: String) -> String? { q.first { $0.name == k }?.value }
        let parts = url.pathComponents.filter { $0 != "/" }
        Log.event("url_command", detail: url.absoluteString)
        switch url.host {
        case "preset":
            Publisher.publish(Presets.named(parts.first ?? "status"), reload: v("reload") != "0", source: "url")
        case "la":
            Task { await LiveActivities.handle(parts.first ?? "start") }
        case "notify":
            Notifications.schedule(kind: parts.first ?? "choice", delay: Double(v("delay") ?? "3") ?? 3)
        case "config":
            var c = Store.config()
            if let b = v("bridge") { c.bridgeURL = b }
            if let p = v("pull") { c.pullOnReload = p == "1" }
            if let p = v("post") { c.postResponses = p == "1" }
            Store.saveConfig(c)
        case "pull":
            Task {
                if let s = await Bridge.fetchSurface() { Publisher.publish(s, reload: v("reload") != "0", source: "pull") }
            }
        case "bumprev":   // lab: newer revision in the store, widget still shows the old one (no reload)
            var s = Store.loadSurface(); s.revision += 1; Store.save(s, force: true)
        case "perm":
            Task { _ = await Notifications.requestPermission() }
        case "bg":
            BackgroundRefresh.schedule()
        case "clearlog":
            Log.clear()
        default: break
        }
    }
}

// MARK: - App delegate: remote / silent push, notifications, background tasks

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ app: UIApplication, didFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Log.event("app_launch", detail: "state=\(app.applicationState.rawValue) remote=\(opts?[.remoteNotification] != nil)")
        UNUserNotificationCenter.current().delegate = self
        Notifications.registerBase()
        BackgroundRefresh.register()
        app.registerForRemoteNotifications()
        LiveActivities.observeTokens()
        Task { await Bridge.flushOutbox() }
        return true
    }

    func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        Store.saveToken("apns", token)
    }

    func application(_ app: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Log.event("apns_register_failed", detail: error.localizedDescription)
    }

    /// Silent / background push: the payload may carry the full surface (≤4 KB),
    /// otherwise we pull it from the bridge. Then request a widget reload.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        Log.event("silent_push", detail: "appState=\(application.applicationState.rawValue)")
        let info = userInfo
        Task {
            completionHandler(await AppDelegate.handleSilentPush(info))
        }
    }

    /// Legacy background fetch entry point (UIBackgroundModes=fetch). Logged to see
    /// which path the system uses for simulated content-available pushes.
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // The Simulator delivers simctl content-available pushes here WITHOUT payload.
        // Lab stand-in: tools/lab.py drops the intended payload into the App Group first.
        var info: [AnyHashable: Any] = [:]
        if let u = Store.dir?.appendingPathComponent("sim-push-payload.json"),
           let d = try? Data(contentsOf: u), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            info = obj
            try? FileManager.default.removeItem(at: u)
        }
        Log.event("perform_fetch", detail: "simPayload=\(!info.isEmpty)")
        // Without payload: content-free wake-up → pull the agent's surface from the bridge.
        Task { completionHandler(await AppDelegate.handleSilentPush(info)) }
    }

    static func handleSilentPush(_ info: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        if info["reloadOnly"] != nil {
            WidgetCenter.shared.reloadAllTimelines()
            Log.event("reload_requested", detail: "reloadOnly silent push")
            return .newData
        }
        var surface: Surface?
        if let obj = info["surface"], let d = try? JSONSerialization.data(withJSONObject: obj),
           case .success(let s) = Surface.decode(d) { surface = s }
        if surface == nil { surface = await Bridge.fetchSurface() }
        guard let s = surface else { return .failed }
        Store.save(s)
        WidgetCenter.shared.reloadAllTimelines()
        Log.event("reload_requested", rev: s.revision, detail: "from silent push")
        if info["updateActivity"] != nil { await LiveActivities.update(with: s) }
        return .newData
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification) async -> UNNotificationPresentationOptions {
        Log.event("notification_will_present", detail: n.request.content.categoryIdentifier)
        return [.banner, .list, .sound]
    }

    /// Notification action / text reply. Runs in background for non-foreground actions.
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
        let state = await UIApplication.shared.applicationState
        let text = (r as? UNTextInputNotificationResponse)?.userText
        let info = r.notification.request.content.userInfo
        let surfaceId = info["surfaceId"] as? String ?? Store.loadSurface().id
        let rev = info["revision"] as? Int ?? Store.loadSurface().revision
        Log.event("notification_action", rev: rev, detail: "\(r.actionIdentifier) text=\(text ?? "-") appState=\(state.rawValue)")
        guard r.actionIdentifier != UNNotificationDefaultActionIdentifier,
              r.actionIdentifier != UNNotificationDismissActionIdentifier else { return }
        await ActionProcessor.handle(surfaceId: surfaceId, action: r.actionIdentifier, revision: rev, text: text, channel: "notification")
        WidgetCenter.shared.reloadAllTimelines()
        Log.event("reload_requested", detail: "after notification action")
    }
}

// MARK: - Notifications (incl. text input)

enum Notifications {
    static func requestPermission() async -> Bool {
        let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        Log.event("notification_permission", detail: "\(ok)")
        return ok
    }

    static let textCategory = UNNotificationCategory(
        identifier: "AGENT_TEXT",
        actions: [UNTextInputNotificationAction(identifier: "reply", title: "Reply", options: [],
                                                textInputButtonTitle: "Send", textInputPlaceholder: "Answer the agent…"),
                  UNNotificationAction(identifier: "skip", title: "Skip", options: [])],
        intentIdentifiers: [])

    static func registerBase() {
        UNUserNotificationCenter.current().setNotificationCategories([textCategory])
    }

    /// Categories are static per identifier, so dynamic agent options must be
    /// registered by the app before the notification arrives (limitation C3).
    static func registerCategory(for s: Surface) {
        let ids = s.root.actionIds
        guard !ids.isEmpty else { return }
        let labels = labelMap(s.root)
        let actions = ids.prefix(10).map { UNNotificationAction(identifier: $0, title: labels[$0] ?? $0, options: []) }
        let cat = UNNotificationCategory(identifier: "AGENT_CHOICE", actions: actions, intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([textCategory, cat])
    }

    private static func labelMap(_ n: UINode) -> [String: String] {
        var m: [String: String] = [:]
        if n.type == "button", let a = n.action { m[a] = n.text ?? a }
        for c in n.children ?? [] { m.merge(labelMap(c)) { a, _ in a } }
        return m
    }

    static func schedule(kind: String, delay: Double) {
        let s = Store.loadSurface()
        let c = UNMutableNotificationContent()
        c.title = s.agent
        c.body = kind == "text" ? "What should the commit message say?" : "Needs a decision — choose below."
        c.categoryIdentifier = kind == "text" ? "AGENT_TEXT" : "AGENT_CHOICE"
        c.userInfo = ["surfaceId": s.id, "revision": s.revision]
        c.interruptionLevel = .timeSensitive
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: c,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false))
        UNUserNotificationCenter.current().add(req)
        Log.event("notification_scheduled", rev: s.revision, detail: kind)
    }
}

// MARK: - Background App Refresh (BGTaskScheduler)

enum BackgroundRefresh {
    static var id: String { (Bundle.main.bundleIdentifier ?? "") + ".refresh" }

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
            Log.event("bg_refresh_run")
            schedule()
            let work = Task {
                if let s = await Bridge.fetchSurface() {
                    Store.save(s)
                    WidgetCenter.shared.reloadAllTimelines()
                    Log.event("reload_requested", rev: s.revision, detail: "from bg refresh")
                }
                await Bridge.flushOutbox()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel(); Log.event("bg_refresh_expired") }
        }
    }

    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: id)
        r.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        do { try BGTaskScheduler.shared.submit(r); Log.event("bg_refresh_scheduled") }
        catch { Log.event("bg_refresh_schedule_failed", detail: error.localizedDescription) }
    }
}

// MARK: - Live Activities

enum LiveActivities {
    static func handle(_ cmd: String) async {
        switch cmd {
        case "start": start()
        case "end":
            for a in Activity<AgentActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
            Log.event("activity_ended")
        default: await update(with: Store.loadSurface())
        }
    }

    static func start() {
        let s = Store.loadSurface()
        let info = ActivityAuthorizationInfo()
        Log.event("activity_auth", detail: "enabled=\(info.areActivitiesEnabled) frequent=\(info.frequentPushesEnabled)")
        do {
            let a = try Activity.request(attributes: AgentActivityAttributes(agent: s.agent),
                                         content: .init(state: .init(surface: s, sentAt: ISO.string()), staleDate: nil),
                                         pushType: .token)
            Log.event("activity_started", rev: s.revision, detail: a.id)
            Task { for await t in a.pushTokenUpdates { Store.saveToken("activity", t) } }
        } catch {
            Log.event("activity_start_failed", detail: error.localizedDescription)
        }
    }

    static func update(with s: Surface) async {
        for a in Activity<AgentActivityAttributes>.activities {
            await a.update(ActivityContent(state: .init(surface: s, sentAt: ISO.string()), staleDate: nil))
            Log.event("activity_updated", rev: s.revision)
        }
    }

    static func observeTokens() {
        if #available(iOS 17.2, *) {
            Task { for await t in Activity<AgentActivityAttributes>.pushToStartTokenUpdates { Store.saveToken("activity-start", t) } }
        }
        Task {
            for await a in Activity<AgentActivityAttributes>.activityUpdates {
                Log.event("activity_seen", detail: a.id)
                Task { for await t in a.pushTokenUpdates { Store.saveToken("activity", t) } }
            }
        }
    }
}
