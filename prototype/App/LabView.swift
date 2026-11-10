import SwiftUI
import WidgetKit

struct LabView: View {
    @State private var json = ""
    @State private var reload = true
    @State private var status = "Ready"
    @State private var surface = Store.loadSurface()
    @State private var config = Store.config()
    @State private var log: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SurfaceView(surface: surface, family: "systemMedium", channel: .preview)
                        .padding(16)
                        .frame(height: 170)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                } header: { Text("Current surface (same renderer as widget)") }

                Section("Presets — one widget, any layout") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Presets.cycle + ["scheduled"], id: \.self) { name in
                                Button(name) { publish(Presets.named(name)) }
                                    .buttonStyle(.bordered).accessibilityIdentifier("preset-\(name)")
                            }
                        }
                    }
                    Toggle("Request WidgetCenter reload", isOn: $reload)
                }

                Section("Raw schema JSON") {
                    TextEditor(text: $json)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(height: 180)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button("Publish JSON") {
                        switch Surface.decode(Data(json.utf8)) {
                        case .success(let s): publish(s)
                        case .failure(let e): status = "Rejected: \(e)"; Log.event("schema_rejected", detail: e.description)
                        }
                    }
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }

                Section("Bridge (agent return channel)") {
                    TextField("http://<mac>.local:8787", text: $config.bridgeURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Toggle("Widget pulls bridge on every reload", isOn: $config.pullOnReload)
                    Toggle("Post responses to bridge", isOn: $config.postResponses)
                    Button("Save config") { Store.saveConfig(config); status = "Config saved" }
                    Button("Pull surface from bridge now") {
                        Task { if let s = await Bridge.fetchSurface() { publish(s) } else { status = "Pull failed" } }
                    }
                }

                Section("Other surfaces") {
                    Button("Start Live Activity") { LiveActivities.start() }
                    Button("Update Live Activity") { Task { await LiveActivities.update(with: Store.loadSurface()) } }
                    Button("End Live Activities") { Task { await LiveActivities.handle("end") } }
                    Button("Allow notifications") { Task { _ = await Notifications.requestPermission() } }
                    Button("Choice notification in 5 s") { Notifications.schedule(kind: "choice", delay: 5) }
                    Button("Text-input notification in 5 s") { Notifications.schedule(kind: "text", delay: 5) }
                    Button("Schedule BG app refresh") { BackgroundRefresh.schedule() }
                }

                Section {
                    ForEach(log.prefix(80), id: \.self) { Text($0).font(.system(size: 10, design: .monospaced)) }
                } header: {
                    HStack {
                        Text("Event log (App Group)")
                        Spacer()
                        Button("Refresh") { refresh() }
                        Button("Clear") { Log.clear(); refresh() }
                        ShareLink(item: Log.tail(5000).reversed().joined(separator: "\n")) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            .navigationTitle("Agent Widget Lab")
            .onAppear(perform: refresh)
            .refreshable { refresh() }
        }
    }

    private func publish(_ s: Surface) {
        if Publisher.publish(s, reload: reload, source: "app") {
            status = "Published \(s.id) · reload=\(reload)"
        } else {
            status = "Save failed — App Group entitlement?"
        }
        refresh()
    }

    private func refresh() {
        surface = Store.loadSurface()
        json = {
            let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
            return (try? String(decoding: e.encode(surface), as: UTF8.self)) ?? "{}"
        }()
        config = Store.config()
        log = Log.tail(200)
    }
}
