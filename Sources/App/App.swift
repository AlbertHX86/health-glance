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
        willSet { if newValue != selected { answer = nil } }
        didSet { UserDefaults.standard.set(selected, forKey: "person"); publishDisplay(); reloadHistory() }
    }
    /// The history of the person shown, for the trend chart.
    @Published var history: [DayRecord] = []
    @Published var trendMetric = UserDefaults.standard.string(forKey: "trendMetric") ?? "steps" {
        didSet { UserDefaults.standard.set(trendMetric, forKey: "trendMetric") }
    }
    @Published var trendDays = UserDefaults.standard.object(forKey: "trendDays") as? Int ?? 30 {
        didSet { UserDefaults.standard.set(trendDays, forKey: "trendDays") }
    }
    @Published var showTrends = UserDefaults.standard.object(forKey: "showTrends") as? Bool ?? false {  // the island always shows it; the menu keeps it folded so it fits small screens
        didSet { UserDefaults.standard.set(showTrends, forKey: "showTrends") }
    }
    @Published var sources = Sources.latest()
    @Published var status = ""
    @Published var busy = false
    @Published var apiKey = Config.load().apiKey
    @Published var lang = Config.load().language == "zh" ? "zh" : "en"
    /// What sits on the desktop besides the system widget: "card" (the pinned card), "island" (Dynamic Island) or "off".
    @Published var display = UserDefaults.standard.string(forKey: "display") ?? (UserDefaults.standard.bool(forKey: "panel") ? "card" : "off") {
        didSet { UserDefaults.standard.set(display, forKey: "display"); showDisplay() }
    }
    @Published var atLogin = SMAppService.mainApp.status == .enabled
    @Published var gardenHost = Config.load().gardenHost
    @Published var gardenName = Config.load().gardenName
    @Published var gardenPlant = Config.load().gardenPlant
    @Published var gameMode = Config.load().gameMode
    @Published var folderLink = Config.load().inviteFolderLink
    @Published var shortcutLink = Config.load().inviteShortcutLink
    @Published var myDevice = Config.load().myDevice
    @Published var question = ""
    @Published var answer: QA?
    @Published var asking = false

    struct QA: Identifiable {
        let id = UUID()
        let q: String
        var a: String
    }
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
            self.showDisplay()
            self.publishDisplay()  // also reloads the widget; summary.json may have been written by healthwidget-cli
            self.check()
        }
    }

    /// For you and each person with a file, generate when the newest numbers (or the chosen language) differ from the
    /// summary's. The shortcut rewrites the file on every app open, so automatic runs per person are at least 30 min
    /// apart; a manual run does not count. One generation at a time: each one ends by checking again.
    func reloadHistory() { history = History.load(Self.person(selected)) }

    /// Pick the Health app's export (export.zip, or the export.xml in it) and add its days to your history.
    func importExport() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip, .xml]
        panel.message = L.t("Choose the Health export: on the iPhone, Health › your picture › Export All Health Data, then AirDrop or save export.zip to this Mac.",
                            "选择健康导出文件：在 iPhone 上打开「健康」› 右上角头像 › 导出所有健康数据，再用隔空投送或存到这台 Mac。")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        status = L.t("Importing…", "正在导入…")
        Task.detached {
            let result: String
            do {
                let r = try HealthImport.run(url) { n in
                    Task { @MainActor in self.status = L.t("Importing… \(n.formatted()) records", "正在导入… 已读 \(n.formatted()) 条记录") }
                }
                result = L.t("Imported \(r.days) days (\(r.first) – \(r.last))", "已导入 \(r.days) 天（\(r.first) 至 \(r.last)）")
            } catch {
                result = L.t("Import failed: ", "导入失败：") + error.localizedDescription
            }
            await MainActor.run {
                self.status = result
                self.reloadHistory()
            }
        }
    }

    func check() {
        Self.downloadPlaceholders()
        people = HealthParser.people()
        reloadHistory()
        sources = Sources.latest()
        updateGarden()
        guard !busy else { return }
        for key in [""] + people {
            let p = Self.person(key)
            guard let f = HealthParser.latestFile(person: p), let day = HealthParser.read(f) else { continue }
            if let s = summaries[key] ?? Summary.load(p), s.error == nil, s.date == day.date, s.metrics == day.metrics, (s.lang ?? "zh") == lang,
               s.version == Summary.current {
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
        DispatchQueue.main.async { DesktopPanel.shared.fit(); Island.shared.place() }
    }

    func showDisplay() {
        DesktopPanel.shared.show(display == "card", model: self)
        Island.shared.show(display == "island", model: self)
    }

    /// Put tasks from a question on that person's checklist; returns how many were new.
    func addTasks(_ tasks: [String], person: String?) -> Int {
        let key = person ?? ""
        guard !tasks.isEmpty, var s = summaries[key] ?? Summary.load(person) else { return 0 }
        let new = tasks.filter { !s.tips.contains($0) }
        guard !new.isEmpty else { return 0 }
        withAnimation(.easeOut(duration: 0.3)) {
            s.tips += new
            s.added = (s.added ?? []) + new
            summaries[key] = s
        }
        try? s.save()
        publishDisplay()
        return new.count
    }

    /// Tick a tip of the summary shown, or untick it.
    func toggleTip(_ tip: String) {
        guard var s = summaries[selected] else { return }
        var done = Set(s.done ?? [])
        if !done.insert(tip).inserted { done.remove(tip) }
        s.done = s.tips.filter { done.contains($0) }
        summaries[selected] = s
        try? s.save()
        publishDisplay()
    }

    /// Ask about the data of the person shown. Each question stands alone: the answer replaces the last one.
    func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !asking else { return }
        let person = Self.person(selected)
        question = ""
        asking = true
        answer = QA(q: q, a: "…")
        Task { @MainActor in
            var a: String
            do {
                let r = try await Engine.ask(q, person: person)
                a = r.answer
                let n = addTasks(r.tasks, person: person)
                if n > 0 { a += "\n\n" + L.t("＋ Added \(n) to Suggestions", "＋ 已加入建议清单 \(n) 条") }
                if let c = r.chart {
                    trendMetric = c.metric
                    trendDays = c.days
                    showTrends = true
                }
            } catch { a = error.localizedDescription }
            if answer?.q == q { answer?.a = a }
            asking = false
        }
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
            WidgetFrame(size: .large, grows: true) {
                CardView(summary: model.summary, size: .large, lang: model.summary?.lang ?? model.lang) { model.toggleTip($0) }
            }
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            AskView(model: model)
            DisclosureGroup(t("Trends", "趋势"), isExpanded: $model.showTrends) {
                TrendsView(model: model).padding(.top, 6)
            }
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
                Picker(t("On the desktop", "桌面显示"), selection: $model.display) {
                    Text(t("Card", "卡片")).tag("card")
                    Text(t("Dynamic Island", "灵动岛")).tag("island")
                    Text(t("Off", "不显示")).tag("off")
                }
                .pickerStyle(.segmented)
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
            w.contentView = FirstClickHostingView(rootView: PanelView(model: model))
            w.setFrameAutosaveName("HealthWidgetPanel")
            if !w.setFrameUsingName("HealthWidgetPanel"), let screen = NSScreen.main {
                w.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.maxX - size.width - 20, y: screen.visibleFrame.maxY - 20))
            }
            window = w
        }
        window?.orderFront(nil)
        fit()
    }

    /// Resize to the card (it grows with the number of tips), keeping the top edge where it is.
    func fit() {
        guard let w = window, let v = w.contentView else { return }
        let size = v.fittingSize
        guard size.height > 0, abs(size.height - w.frame.height) > 0.5 || abs(size.width - w.frame.width) > 0.5 else { return }
        let top = w.frame.maxY
        w.setFrame(NSRect(x: w.frame.minX, y: top - size.height, width: size.width, height: size.height), display: true)
    }
}

/// Ticks a tip on the first click, without the click first activating the app.
final class FirstClickHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct PanelView: View {
    @ObservedObject var model: Model
    var body: some View {
        WidgetFrame(size: .large, grows: true) {
            CardView(summary: model.summary, size: .large, lang: model.summary?.lang ?? model.lang) { model.toggleTip($0) }
        }
        .background(GeometryReader { g in Color.clear.onChange(of: g.size) { _, _ in DesktopPanel.shared.fit() } })
    }
}

/// Questions about the data shown, answered by the model from the recent days, the summary and the checklist.
struct AskView: View {
    @ObservedObject var model: Model
    func t(_ en: String, _ zh: String) -> String { model.lang == "zh" ? zh : en }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let qa = model.answer {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(qa.q).font(.callout.weight(.semibold))
                        Text((try? AttributedString(markdown: qa.a, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(qa.a))
                            .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                TextField(t("Ask about your health…", "问问你的健康数据…"), text: $model.question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.ask() }
                    .disabled(model.asking)
                if model.asking { ProgressView().controlSize(.small) }
                if model.answer != nil && !model.asking {
                    Button { model.answer = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help(t("Clear", "清空"))
                }
            }
        }
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
