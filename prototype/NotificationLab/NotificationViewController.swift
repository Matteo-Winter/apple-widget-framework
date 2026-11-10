import UIKit
import WebKit
import UserNotifications
import UserNotificationsUI

// Notification Content Extension: a full UIKit view controller shown when the user
// long-presses (expands) a notification of category SL_RICH. Measures the area it gets
// and which interactions work (buttons, scrolling, text input, web content).
final class NotificationViewController: UIViewController, UNNotificationContentExtension, UITextFieldDelegate, UIScrollViewDelegate {
    private var scrollLogged = false
    private let info = UILabel()
    private let scroll = UIScrollView()
    private let field = UITextField()
    private var web: WKWebView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.07, green: 0.09, blue: 0.16, alpha: 1)
        preferredContentSize = CGSize(width: view.bounds.width, height: 900)   // ask for far more than fits
        info.textColor = .white; info.font = .monospacedSystemFont(ofSize: 13, weight: .bold); info.numberOfLines = 0
        let button = UIButton(configuration: .filled())
        button.setTitle("Native UIKit button", for: .normal)
        button.accessibilityIdentifier = "sl-notif-button"
        button.addAction(UIAction { [weak self] _ in
            NLLog.event("sl_notif_button")
            self?.info.text = (self?.info.text ?? "") + "\nbutton tapped"
        }, for: .touchUpInside)
        field.placeholder = "Type here (UITextField)"; field.backgroundColor = .white; field.borderStyle = .roundedRect
        field.accessibilityIdentifier = "sl-notif-field"; field.delegate = self
        scroll.backgroundColor = UIColor.white.withAlphaComponent(0.08); scroll.accessibilityIdentifier = "sl-notif-scroll"; scroll.delegate = self
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 2
        for i in 1...60 {
            let l = UILabel(); l.text = "  scroll row \(i)"; l.textColor = .white; l.font = .systemFont(ofSize: 14)
            l.heightAnchor.constraint(equalToConstant: 28).isActive = true; stack.addArrangedSubview(l)
        }
        let wv = WKWebView(); web = wv
        wv.loadHTMLString("<html><body style='margin:0;background:linear-gradient(90deg,#ff7a18,#c77dff);font:700 18px -apple-system;color:#fff;display:flex;align-items:center;justify-content:center;height:100vh'>WKWebView inside notification</body></html>", baseURL: nil)
        for v in [info, button, field, wv, scroll] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            info.topAnchor.constraint(equalTo: view.topAnchor, constant: 12), info.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            info.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            button.topAnchor.constraint(equalTo: info.bottomAnchor, constant: 8), button.leadingAnchor.constraint(equalTo: info.leadingAnchor),
            field.topAnchor.constraint(equalTo: button.bottomAnchor, constant: 8), field.leadingAnchor.constraint(equalTo: info.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: info.trailingAnchor), field.heightAnchor.constraint(equalToConstant: 36),
            wv.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8), wv.leadingAnchor.constraint(equalTo: info.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: info.trailingAnchor), wv.heightAnchor.constraint(equalToConstant: 60),
            scroll.topAnchor.constraint(equalTo: wv.bottomAnchor, constant: 8), scroll.leadingAnchor.constraint(equalTo: info.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: info.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor), stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let s = view.bounds.size, scr = view.window?.screen.bounds.size ?? .zero
        info.text = "Notification content extension\nview \(Int(s.width))×\(Int(s.height)) pt (screen \(Int(scr.width))×\(Int(scr.height)))"
        NLLog.event("sl_notif_layout", detail: "size=\(Int(s.width))x\(Int(s.height)) screen=\(Int(scr.width))x\(Int(scr.height))")
    }

    func didReceive(_ notification: UNNotification) {
        NLLog.event("sl_notif_receive", detail: notification.request.identifier)
    }

    func scrollViewDidScroll(_ s: UIScrollView) {
        if !scrollLogged, s.contentOffset.y > 40 { scrollLogged = true; NLLog.event("sl_notif_scrolled", detail: "y=\(Int(s.contentOffset.y))") }
    }

    func textFieldDidBeginEditing(_ tf: UITextField) { NLLog.event("sl_notif_field_focus") }
    func textFieldShouldReturn(_ tf: UITextField) -> Bool { NLLog.event("sl_notif_field_text", detail: tf.text ?? ""); tf.resignFirstResponder(); return true }
}

/// Minimal App Group logger (same events.jsonl as the app/widget).
enum NLLog {
    static func event(_ name: String, detail: String = "") {
        var id = Bundle.main.bundleIdentifier ?? ""
        if id.hasSuffix(".NotificationLab") { id = String(id.dropLast(".NotificationLab".count)) }
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group." + id) else { return }
        let obj: [String: Any] = ["t": Int64(Date().timeIntervalSince1970 * 1000), "p": "notif", "e": name, "d": detail]
        guard var line = try? JSONSerialization.data(withJSONObject: obj) else { return }
        line.append(0x0a)
        let fd = open(dir.appendingPathComponent("events.jsonl").path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        _ = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }; close(fd)
    }
}
