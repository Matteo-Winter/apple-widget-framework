import SwiftUI
import UIKit
import AppIntents

/// Where a tree is rendered; decides which App Intent buttons use.
enum RenderChannel { case widget, activity, preview }

/// The single, generic renderer. Maps schema node types onto a fixed vocabulary
/// of SwiftUI views. Unknown types render as EmptyView.
struct NodeView: View {
    let node: UINode
    let surface: Surface
    let channel: RenderChannel

    var body: some View { content.padding(node.padding.map { CGFloat($0) } ?? 0) }

    @ViewBuilder private var content: some View {
        switch node.type {
        case "vstack":
            VStack(alignment: hAlign, spacing: spacing) { kids }
                .frame(maxWidth: .infinity, alignment: Alignment(horizontal: hAlign, vertical: .center))
        case "hstack":
            HStack(alignment: .center, spacing: spacing) { kids }
        case "zstack":
            ZStack { kids }
        case "text":
            Text(node.text ?? "").font(font).fontWeight(weight).foregroundStyle(fg)
                .lineLimit(node.lineLimit ?? 3).minimumScaleFactor(0.8)
        case "symbol":
            Image(systemName: node.symbol ?? "circle").font(font).foregroundStyle(fg)
        case "image":
            if let b = node.imageData, let d = Data(base64Encoded: b), let ui = UIImage(data: d) {
                Image(uiImage: ui).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 6))
            }
        case "badge":
            Text(node.text ?? "").font(.system(size: 10, weight: .bold)).tracking(0.4).lineLimit(1).fixedSize()
                .padding(.horizontal, 6).padding(.vertical, 3)
                .foregroundStyle(node.background == nil ? Color.primary : fg)
                .background(Capsule().fill(Palette.color(node.background) ?? Color.primary.opacity(0.10)))
        case "progress":
            if let s = date(node.date), let e = date(node.endDate), e > s {
                // Advances with system time — no timeline updates needed.
                ProgressView(timerInterval: s...e, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .tint(Palette.color(node.color) ?? .primary)
            } else {
                ProgressView(value: min(1, max(0, node.value ?? 0))).tint(Palette.color(node.color) ?? .primary)
            }
        case "gauge":
            Gauge(value: min(1, max(0, node.value ?? 0))) { Text(node.text ?? "") }
                .gaugeStyle(.accessoryCircularCapacity)
        case "timer":
            if let e = date(node.endDate) {
                Text(timerInterval: (date(node.date) ?? .now)...max(e, .now), countsDown: true)
                    .font(font).fontWeight(weight).monospacedDigit().foregroundStyle(fg)
            }
        case "relative":
            if let d = date(node.date) {
                Text(d, style: .relative).font(font).foregroundStyle(fg).monospacedDigit()
            }
        case "spacer":
            Spacer(minLength: 0)
        case "divider":
            Divider()
        case "button":
            ActionButton(node: node, surface: surface, channel: channel)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var kids: some View {
        ForEach(Array((node.children ?? []).enumerated()), id: \.offset) { _, child in
            NodeView(node: child, surface: surface, channel: channel)
        }
    }

    private var spacing: CGFloat? { node.spacing.map { CGFloat($0) } }
    private var hAlign: HorizontalAlignment {
        switch node.alignment { case "center": return .center; case "trailing": return .trailing; default: return .leading }
    }
    private var font: Font {
        switch node.style {
        case "largeTitle": return .largeTitle
        case "title": return .title2
        case "headline": return .headline
        case "callout": return .callout
        case "caption": return .caption
        case "footnote": return .footnote
        case "mono": return .system(.caption, design: .monospaced)
        default: return .body
        }
    }
    private var weight: Font.Weight? {
        switch node.weight { case "medium": return .medium; case "semibold": return .semibold; case "bold": return .bold; default: return nil }
    }
    private var fg: Color { Palette.color(node.color) ?? .primary }
    private func date(_ s: String?) -> Date? { s.flatMap { ISO.parse($0) } }
}

struct ActionButton: View {
    let node: UINode
    let surface: Surface
    let channel: RenderChannel

    var body: some View {
        let answered = surface.answeredAction != nil
        Group {
            if let u = node.url, let url = URL(string: u) {
                Link(destination: url) { label }
            } else if node.action == "__pull" {
                Button(intent: PullIntent()) { label }
            } else if channel == .activity {
                #if canImport(ActivityKit)
                Button(intent: AgentActivityActionIntent(surfaceId: surface.id, actionId: node.action ?? "", revision: surface.revision)) { label }
                #endif
            } else {
                Button(intent: AgentActionIntent(surfaceId: surface.id, actionId: node.action ?? "", revision: surface.revision)) { label }
            }
        }
        .buttonStyle(.plain)
        .disabled(answered)
        .opacity(answered ? 0.4 : 1)
        .accessibilityIdentifier("action-\(node.action ?? "")")
    }

    private var prominent: Bool { node.prominent ?? false }

    private var label: some View {
        HStack(spacing: 4) {
            if let s = node.symbol { Image(systemName: s) }
            if let t = node.text, !t.isEmpty { Text(t).lineLimit(1).minimumScaleFactor(0.7) }
        }
        .font(.system(size: 13, weight: .semibold))
        .frame(maxWidth: .infinity, minHeight: 30)
        .padding(.horizontal, 6)
        .foregroundStyle(prominent ? Color(uiColor: .systemBackground) : Color.primary)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(prominent ? Color.primary : Color.primary.opacity(0.08))
        )
    }
}

enum Palette {
    static func color(_ name: String?) -> Color? {
        switch name {
        case "primary": return .primary
        case "secondary": return .secondary
        case "accent": return .accentColor
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        case "blue": return .blue
        case "white": return .white
        case "black": return .black
        default: return nil
        }
    }
}

/// Root wrapper: picks the per-family tree, shows a tiny revision stamp for
/// measurement (readable on screenshots / screen recordings).
struct SurfaceView: View {
    let surface: Surface
    let family: String
    let channel: RenderChannel
    var showStamp = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            NodeView(node: surface.tree(for: family), surface: surface, channel: channel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if showStamp {
                Text(verbatim: "r\(surface.revision)")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("revision-stamp")
            }
        }
    }
}
