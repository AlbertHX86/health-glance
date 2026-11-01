import AppKit
import ServiceManagement
import SwiftUI
import WidgetKit

// Menu-bar app: watches the inbox, generates the daily summary with MiniMax, refreshes the widget,
// and can also pin the card to the desktop as a plain window.

@MainActor
final class Model: ObservableObject {
    /// Summaries by person; "" is you.
    @Published var summaries: [String: Summary] = [:]
    @Published var people: [String] = []
    @Published var selected = UserDefaults.standard.string(forKey: "person") ?? "" {
        didSet { UserDefaults.standard.set(selected, forKey: "person"); publishDisplay() }
    }
    @Published var sources = Sources.latest()
    @Published var status = ""
    @Published var busy = false
    @Published var apiKey = Config.load().apiKey
    @Published var lang = Config.load().language == "zh" ? "zh" : "en"
    @Published var panel = UserDefaults.standard.bool(forKey: "panel") { didSet { UserDefaults.standard.set(panel, forKey: "panel"); DesktopPanel.shared.show(panel, model: self) } }
    @Published var atLogin = SMAppService.mainApp.status == .enabled
    private var lastAuto: [String: Date] = [:]
    private var timer: Timer?

    var summary: Summary? { summaries[selected] }

    static func person(_ key: String) -> String? { key.isEmpty ? nil : key }

    init() {
        L.lang = lang
        people = HealthParser.people()
        summaries[""] = Summary.load()
        for p in people { summaries[p] = Summary.load(p) }
        if !selected.isEmpty && !people.contains(selected) { selected = "" }
        // iCloud delivers the iPhone's file some seconds to minutes after the shortcut runs; poll for it
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in Task { @MainActor in self.check() } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in self.check() }
        }
        Task { @MainActor in
            DesktopPanel.shared.show(self.panel, model: self)
            self.publishDisplay()  // also reloads the widget; summary.json may have been written by healthwidget-cli
            self.check()
        }
    }

    /// For you and each person with a file, generate when the newest numbers (or the chosen language) differ from the
    /// summary's. The shortcut rewrites the file on every app open, so automatic runs per person are at least 30 min
    /// apart; a manual run does not count. One generation at a time: each one ends by checking again.
    func check() {
        Self.downloadPlaceholders()
        people = HealthParser.people()
        sources = Sources.latest()
        guard !busy else { return }
        for key in [""] + people {
            let p = Self.person(key)
            guard let f = HealthParser.latestFile(person: p), let day = HealthParser.read(f) else { continue }
            if let s = summaries[key] ?? Summary.load(p), s.error == nil, s.date == day.date, s.metrics == day.metrics, (s.lang ?? "zh") == lang {
                summaries[key] = s
                continue
            }
            if Date().timeIntervalSince(lastAuto[key] ?? .distantPast) < 30 * 60 { continue }
            generate(key, auto: true)
            return
        }
    }

    func generate(_ key: String? = nil, auto: Bool = false) {
        let key = key ?? selected
        busy = true
        if auto { lastAuto[key] = Date() }
        status = L.t("Generating…", "正在生成…") + (key.isEmpty ? "" : " (\(key))")
        Task { @MainActor in
            do {
                summaries[key] = try await Engine.run(person: Self.person(key))
                status = L.t("Updated ", "已更新 ") + Date().formatted(date: .omitted, time: .shortened)
            } catch {
                status = error.localizedDescription
            }
            busy = false
            publishDisplay()
            check()
        }
    }

    /// Copy the chosen person's summary to display.json, which the widget reads.
    func publishDisplay() {
        if let s = summaries[selected] ?? summaries[""] { try? s.save(to: Paths.display) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func saveKey() {
        var c = Config.load()
        c.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do { try c.save(); status = L.t("API key saved", "API Key 已保存") } catch { status = L.t("Could not save: ", "保存失败：") + error.localizedDescription; return }
        lastAuto = [:]
        check()
    }

    /// Switching language rewrites the summaries in that language (the one shown first).
    func setLanguage(_ l: String) {
        guard l != lang else { return }
        lang = l
        L.lang = l
        var c = Config.load()
        c.language = l
        try? c.save()
        lastAuto = [:]
        if summary != nil, !busy { generate() }
    }

    func toggleLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { status = L.t("Launch at login failed: ", "开机启动设置失败：") + error.localizedDescription }
        atLogin = SMAppService.mainApp.status == .enabled
    }

    /// iCloud may keep only placeholders (".name.txt.icloud") on a Mac short of space; ask for the real files.
    static func downloadPlaceholders() {
        for dir in Paths.inboxes {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for n in items where n.hasPrefix(".") && n.hasSuffix(".icloud") {
                let real = dir.appendingPathComponent(String(n.dropFirst().dropLast(".icloud".count)))
                try? FileManager.default.startDownloadingUbiquitousItem(at: real)
            }
        }
    }
}

struct MainView: View {
    @ObservedObject var model: Model

    func t(_ en: String, _ zh: String) -> String { model.lang == "zh" ? zh : en }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WidgetFrame(size: .large) { CardView(summary: model.summary, size: .large, lang: model.summary?.lang ?? model.lang) }
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            HStack(spacing: 8) {
                Button {
                    model.generate()
                } label: {
                    Label(model.busy ? t("Generating…", "生成中…") : t("Generate Now", "立即生成"), systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .disabled(model.busy)
                Button {
                    let dir = FileManager.default.fileExists(atPath: Paths.inboxes[0].path) ? Paths.inboxes[0] : Paths.localInbox
                    try? FileManager.default.createDirectory(at: Paths.localInbox, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                } label: {
                    Label(t("Data Folder", "数据文件夹"), systemImage: "folder")
                }
                Spacer()
                Button(t("Quit", "退出")) { NSApp.terminate(nil) }
            }
            .controlSize(.regular)
            if !model.status.isEmpty {
                Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            if !model.people.isEmpty {
                Picker(t("Showing", "显示"), selection: $model.selected) {
                    Text(t("Me", "我")).tag("")
                    ForEach(model.people, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if let src = model.sources {
                DisclosureGroup(t("Source test", "来源测试") + " · " + src.modified.formatted(date: .abbreviated, time: .shortened)) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(src.counts.prefix(10).enumerated()), id: \.offset) { _, c in
                            HStack { Text(c.name).lineLimit(1); Spacer(); Text("\(c.n)").monospacedDigit().foregroundStyle(.secondary) }
                        }
                        Text(t("If someone else's device is listed, your iPhone can read their shared data.",
                               "列表里出现别人的设备，就说明 iPhone 能读到对方共享的数据。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .padding(.top, 4)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    SecureField("MiniMax API Key", text: $model.apiKey).textFieldStyle(.roundedBorder)
                    Button(t("Save", "保存")) { model.saveKey() }
                }
                Picker(t("Language", "语言"), selection: Binding(get: { model.lang }, set: { model.setLanguage($0) })) {
                    Text("English").tag("en")
                    Text("中文").tag("zh")
                }
                .pickerStyle(.segmented)
                Toggle(t("Pin card to desktop", "在桌面固定卡片"), isOn: $model.panel)
                Toggle(t("Launch at login", "开机启动"), isOn: Binding(get: { model.atLogin }, set: { model.toggleLogin($0) }))
            }
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .frame(width: CardSize.large.frame.width + 32)
    }
}

/// The card as a borderless window just above the desktop icons, on every Space; drag to move.
@MainActor
final class DesktopPanel {
    static let shared = DesktopPanel()
    private var window: NSWindow?

    func show(_ on: Bool, model: Model) {
        guard on else { window?.orderOut(nil); return }
        if window == nil {
            let size = CardSize.large.frame
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true  // macOS traces the shadow from the card's rounded shape
            w.isMovableByWindowBackground = true
            w.contentView = NSHostingView(rootView: PanelView(model: model))
            w.setFrameAutosaveName("HealthWidgetPanel")
            if !w.setFrameUsingName("HealthWidgetPanel"), let screen = NSScreen.main {
                w.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.maxX - size.width - 20, y: screen.visibleFrame.maxY - 20))
            }
            window = w
        }
        window?.orderFront(nil)
    }
}

struct PanelView: View {
    @ObservedObject var model: Model
    var body: some View {
        WidgetFrame(size: .large) { CardView(summary: model.summary, size: .large, lang: model.summary?.lang ?? model.lang) }
    }
}

@main
struct HealthWidgetApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        MenuBarExtra("HealthGlance", systemImage: "heart.text.square") {
            MainView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
