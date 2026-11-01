import AppKit
import ServiceManagement
import SwiftUI
import WidgetKit

// Menu-bar app: watches the inbox, generates the daily summary with MiniMax, refreshes the widget,
// and can also pin the card to the desktop as a plain window.

@MainActor
final class Model: ObservableObject {
    @Published var summary = Summary.load()
    @Published var status = ""
    @Published var busy = false
    @Published var apiKey = Config.load().apiKey
    @Published var lang = Config.load().language == "zh" ? "zh" : "en"
    @Published var panel = UserDefaults.standard.bool(forKey: "panel") { didSet { UserDefaults.standard.set(panel, forKey: "panel"); DesktopPanel.shared.show(panel, model: self) } }
    @Published var atLogin = SMAppService.mainApp.status == .enabled
    private var lastAuto = Date.distantPast
    private var timer: Timer?

    init() {
        L.lang = lang
        // iCloud delivers the iPhone's file some seconds to minutes after the shortcut runs; poll for it
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in Task { @MainActor in self.check() } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in self.check() }
        }
        Task { @MainActor in
            DesktopPanel.shared.show(self.panel, model: self)
            WidgetCenter.shared.reloadAllTimelines()  // summary.json may have been written by healthwidget-cli
            self.check()
        }
    }

    /// Generate whenever the newest file's numbers (or the chosen language) differ from the summary's. The shortcut
    /// rewrites the file on every app open, so automatic runs are spaced at least 30 min apart; a manual run does not count.
    func check() {
        Self.downloadPlaceholders()
        guard !busy, let f = HealthParser.latestFile(), let day = HealthParser.read(f) else { return }
        if let s = summary, s.error == nil, s.date == day.date, s.metrics == day.metrics, (s.lang ?? "zh") == lang { return }
        if Date().timeIntervalSince(lastAuto) < 30 * 60 { return }
        generate(auto: true)
    }

    func generate(auto: Bool = false) {
        busy = true
        if auto { lastAuto = Date() }
        status = L.t("Generating…", "正在生成…")
        Task { @MainActor in
            do {
                summary = try await Engine.run()
                status = L.t("Updated ", "已更新 ") + Date().formatted(date: .omitted, time: .shortened)
            } catch {
                status = error.localizedDescription
            }
            busy = false
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func saveKey() {
        var c = Config.load()
        c.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do { try c.save(); status = L.t("API key saved", "API Key 已保存") } catch { status = L.t("Could not save: ", "保存失败：") + error.localizedDescription; return }
        lastAuto = .distantPast
        check()
    }

    /// Switching language rewrites today's summary in that language.
    func setLanguage(_ l: String) {
        guard l != lang else { return }
        lang = l
        L.lang = l
        var c = Config.load()
        c.language = l
        try? c.save()
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
                    let dir = FileManager.default.fileExists(atPath: Paths.inboxes[0].path) ? Paths.inboxes[0] : Paths.inboxes[1]
                    try? FileManager.default.createDirectory(at: Paths.inboxes[1], withIntermediateDirectories: true)
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
