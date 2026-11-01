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
    @Published var gardenHost = Config.load().gardenHost
    @Published var gardenName = Config.load().gardenName
    @Published var gardenPlant = Config.load().gardenPlant
    @Published var gameMode = Config.load().gameMode
    @Published var folderLink = Config.load().inviteFolderLink
    @Published var shortcutLink = Config.load().inviteShortcutLink
    @Published var myDevice = Config.load().myDevice
    @Published var gardenPage: URL? = FileManager.default.fileExists(atPath: Garden.pageURL().path) ? Garden.pageURL() : nil
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
        updateGarden()
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

    func updateGarden() {
        let cfg = Config.load()
        guard cfg.gardenHost else { return }
        Garden.update(cfg: cfg)
        gardenPage = FileManager.default.fileExists(atPath: Garden.pageURL(cfg).path) ? Garden.pageURL(cfg) : nil
    }

    /// Treat health-<device>.txt as your own file: its history joins yours in the game and its separate summary goes.
    func setMyDevice(_ d: String) {
        var c = Config.loadFile()
        c.myDevice = d
        try? c.save()
        _ = Config.loadFile()
        myDevice = d
        if !d.isEmpty {
            Garden.rename(from: d, to: c.gardenName)
            try? FileManager.default.removeItem(at: Paths.dir(d))
            summaries[d] = nil
            if selected == d { selected = "" }
        }
        people = HealthParser.people()
        check()
    }

    /// Confirm, then start the game over for everyone.
    func newGame() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L.t("Start a new game?", "开始新游戏？")
        alert.informativeText = L.t("Season 1 starts today and everyone gets a new egg. All progress so far is cleared (a copy of the old record is kept in the garden folder).",
                                    "今天开始第 1 季，每个人都拿到一颗新蛋。之前所有人的进度清零（旧记录会备份在 garden 文件夹里）。")
        alert.addButton(withTitle: L.t("New game", "新游戏"))
        alert.addButton(withTitle: L.t("Cancel", "取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Garden.newGame()
        updateGarden()
        status = L.t("New game started: season 1, day 1", "新游戏已开始：第 1 季第 1 天")
    }

    func saveGarden() {
        var c = Config.loadFile()
        let name = gardenName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty, name != c.gardenName { Garden.rename(from: c.gardenName, to: name); c.gardenName = name }
        c.gardenHost = gardenHost
        c.gardenPlant = gardenPlant
        c.gameMode = gameMode
        c.inviteFolderLink = folderLink.trimmingCharacters(in: .whitespacesAndNewlines)
        c.inviteShortcutLink = shortcutLink.trimmingCharacters(in: .whitespacesAndNewlines)
        try? c.save()
        updateGarden()
    }

    /// Copy the chosen person's summary to display.json, which the widget reads.
    func publishDisplay() {
        if let s = summaries[selected] ?? summaries[""] { try? s.save(to: Paths.display) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func saveKey() {
        var c = Config.loadFile()
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
        var c = Config.loadFile()
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
    @State private var showSettings = Config.load().apiKey.isEmpty  // open until a key is saved

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
                    // the shared HealthGlance folder once it exists, else the Shortcuts one; the app reads all of them
                    try? FileManager.default.createDirectory(at: Paths.localInbox, withIntermediateDirectories: true)
                    let dir = [Paths.inboxes[1], Paths.inboxes[0]].first { FileManager.default.fileExists(atPath: $0.path) } ?? Paths.localInbox
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
                        if src.counts.isEmpty {
                            Text(t("No samples matched.", "没有符合条件的记录。")).foregroundStyle(.secondary)
                        }
                        Text(t("If someone else's device is listed, your iPhone can read their shared data.",
                               "列表里出现别人的设备，就说明 iPhone 能读到对方共享的数据。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .padding(.top, 4)
                }
            }
            DisclosureGroup(t("Game", "游戏")) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker(t("Game", "游戏"), selection: Binding(get: { model.gameMode }, set: { model.gameMode = $0; model.saveGarden() })) {
                        Text(t("🥚 Puff battles", "🥚 团团对战")).tag("pets")
                        Text(t("🌱 Garden", "🌱 菜园")).tag("garden")
                    }
                    .pickerStyle(.segmented)
                    Toggle(t("Make the game page on this Mac", "由这台 Mac 生成游戏页面"),
                           isOn: Binding(get: { model.gardenHost }, set: { model.gardenHost = $0; model.saveGarden() }))
                    HStack {
                        Text(t("Your name", "你的名字"))
                        TextField("", text: $model.gardenName).textFieldStyle(.roundedBorder).onSubmit { model.saveGarden() }
                    }
                    if model.gameMode == "garden" {
                    Picker(t("Your plant", "你的植物"), selection: Binding(get: { model.gardenPlant }, set: { model.gardenPlant = $0; model.saveGarden() })) {
                        ForEach(Plant.all, id: \.id) { Text("\($0.emoji) \($0.name(model.lang))").tag($0.id) }
                    }
                    }
                    HStack {
                        Button(t("Open Page", "打开页面")) { if let u = model.gardenPage { NSWorkspace.shared.open(u) } }
                            .disabled(model.gardenPage == nil)
                        Button(t("New game", "新游戏")) { model.newGame() }
                            .disabled(!model.gardenHost)
                        Spacer()
                    }
                    Divider()
                    Text(t("Invite players", "邀请玩家")).font(.subheadline.weight(.semibold))
                    Button(t("Create & show the shared folder", "创建并显示共享文件夹")) { Invite.revealFolder() }
                    Text(t("In Finder, right-click HealthGlance › Share › Share Folder. Choose “Anyone with the link” and “Can make changes”, copy the link and paste it here.",
                           "在访达里右键点 HealthGlance › 共享 › 共享文件夹，选「任何拥有链接的人」和「可以更改」，拷贝链接后粘贴到这里。"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    TextField(t("Folder link (icloud.com/…)", "文件夹链接（icloud.com/…）"), text: $model.folderLink)
                        .textFieldStyle(.roundedBorder).onSubmit { model.saveGarden() }
                    TextField(t("Shortcut link (optional)", "快捷指令链接（可选）"), text: $model.shortcutLink)
                        .textFieldStyle(.roundedBorder).onSubmit { model.saveGarden() }
                    HStack {
                        ForEach([("zh", "拷贝邀请（中文）"), ("en", "Copy invite (English)")], id: \.0) { l, label in
                            Button(label) {
                                model.saveGarden()
                                Invite.copy(Invite.message(Config.load(), lang: l))
                                model.status = t("Invite copied: paste it into WeChat or Messages", "邀请消息已拷贝，粘贴到微信或信息里发出去")
                            }
                        }
                    }
                    Text(FileManager.default.fileExists(atPath: Garden.sharedFolder.path)
                         ? t("The page is saved in iCloud Drive › HealthGlance, so everyone sharing the folder can open it.", "页面存在 iCloud 云盘 › HealthGlance，共享这个文件夹的人都能打开。")
                         : t("Create a HealthGlance folder in iCloud Drive and share it; until then the page stays on this Mac.", "在 iCloud 云盘里建一个 HealthGlance 文件夹并共享；建好之前，页面只存在这台 Mac 上。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            DisclosureGroup(t("Settings", "设置"), isExpanded: $showSettings) {
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
                let phones = Array(Set(model.people + [model.myDevice].filter { !$0.isEmpty })).sorted()
                if !phones.isEmpty {
                    Picker(t("My iPhone", "我的 iPhone"), selection: Binding(get: { model.myDevice }, set: { model.setMyDevice($0) })) {
                        Text("health.txt").tag("")
                        ForEach(phones, id: \.self) { Text($0).tag($0) }
                    }
                    Text(t("Using the players' shortcut yourself? Pick your phone so its file counts as you.", "你自己也用玩家的快捷指令？选上你的手机，它的文件就算作你的数据。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle(t("Pin card to desktop", "在桌面固定卡片"), isOn: $model.panel)
                Toggle(t("Launch at login", "开机启动"), isOn: Binding(get: { model.atLogin }, set: { model.toggleLogin($0) }))
            }
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 4)
            }
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
