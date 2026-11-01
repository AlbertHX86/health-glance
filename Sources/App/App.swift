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
    @Published var panel = UserDefaults.standard.bool(forKey: "panel") { didSet { UserDefaults.standard.set(panel, forKey: "panel"); DesktopPanel.shared.show(panel, model: self) } }
    @Published var atLogin = SMAppService.mainApp.status == .enabled
    private var lastAuto = Date.distantPast
    private var timer: Timer?

    init() {
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

    /// Generate whenever the newest file's numbers differ from the summary's. The shortcut rewrites the file on every
    /// app open, so automatic runs are spaced at least 30 min apart; a manual run does not count towards that.
    func check() {
        Self.downloadPlaceholders()
        guard !busy, let f = HealthParser.latestFile(), let day = HealthParser.read(f) else { return }
        if let s = summary, s.error == nil, s.date == day.date, s.metrics == day.metrics { return }
        if Date().timeIntervalSince(lastAuto) < 30 * 60 { return }
        generate(auto: true)
    }

    func generate(auto: Bool = false) {
        busy = true
        if auto { lastAuto = Date() }
        status = "正在生成…"
        Task { @MainActor in
            do {
                summary = try await Engine.run()
                status = "已更新 \(Date().formatted(date: .omitted, time: .shortened))"
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
        do { try c.save(); status = "API Key 已保存" } catch { status = "保存失败：\(error.localizedDescription)"; return }
        lastAuto = .distantPast
        check()
    }

    func toggleLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { status = "开机启动设置失败：\(error.localizedDescription)" }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardView(summary: model.summary, size: .large)
                .padding(14)
                .frame(width: 330, height: 345)
                .background(RoundedRectangle(cornerRadius: 18).fill(.background))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))
            HStack {
                Button(model.busy ? "生成中…" : "立即生成") { model.generate() }.disabled(model.busy)
                Button("数据文件夹") {
                    let dir = FileManager.default.fileExists(atPath: Paths.inboxes[0].path) ? Paths.inboxes[0] : Paths.inboxes[1]
                    try? FileManager.default.createDirectory(at: Paths.inboxes[1], withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dir)
                }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
            if !model.status.isEmpty { Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
            Divider()
            HStack {
                SecureField("MiniMax API Key", text: $model.apiKey).textFieldStyle(.roundedBorder)
                Button("保存") { model.saveKey() }
            }
            Toggle("在桌面固定卡片", isOn: $model.panel)
            Toggle("开机启动", isOn: Binding(get: { model.atLogin }, set: { model.toggleLogin($0) }))
        }
        .padding(16)
        .frame(width: 362)
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
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 330, height: 345), styleMask: [.borderless], backing: .buffered, defer: false)
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
            w.isMovableByWindowBackground = true
            w.contentView = NSHostingView(rootView: PanelView(model: model))
            w.setFrameAutosaveName("HealthWidgetPanel")
            if !w.setFrameUsingName("HealthWidgetPanel"), let screen = NSScreen.main {
                w.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.maxX - 350, y: screen.visibleFrame.maxY - 20))
            }
            window = w
        }
        window?.orderFront(nil)
    }
}

struct PanelView: View {
    @ObservedObject var model: Model
    var body: some View {
        CardView(summary: model.summary, size: .large)
            .padding(14)
            .frame(width: 330, height: 345)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

@main
struct HealthWidgetApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        MenuBarExtra("健康小结", systemImage: "heart.text.square") {
            MainView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
