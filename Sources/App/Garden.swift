import Foundation

// Garden PK. Every player's daily Health numbers become four growth elements for the plant they picked. The host's
// Mac keeps a ledger of each player's last snapshot per day and writes garden.html into the shared HealthGlance
// folder: HTML + CSS + inline SVG and no JavaScript, so it also opens in the iPhone's Files preview.
// The rules are fixed formulas; nothing here goes to MiniMax.

struct Plant {
    let id: String, zh: String, en: String, emoji: String
    let weights: [Double]  // sun, water, nutrients, calm; sums to 1
    let zhNote: String, enNote: String

    func name(_ lang: String) -> String { lang == "zh" ? zh : en }
    func note(_ lang: String) -> String { lang == "zh" ? zhNote : enNote }

    static let all: [Plant] = [
        Plant(id: "tomato", zh: "番茄", en: "Tomato", emoji: "🍅", weights: [0.45, 0.2, 0.2, 0.15],
              zhNote: "喜阳：步数最重要", enNote: "Loves sun: steps count most"),
        Plant(id: "watermelon", zh: "西瓜", en: "Watermelon", emoji: "🍉", weights: [0.15, 0.5, 0.15, 0.2],
              zhNote: "喝水多：睡眠最重要", enNote: "Thirsty: sleep counts most"),
        Plant(id: "sunflower", zh: "向日葵", en: "Sunflower", emoji: "🌻", weights: [0.3, 0.15, 0.45, 0.1],
              zhNote: "爱运动：活动能量和锻炼最重要", enNote: "Energetic: active energy and exercise count most"),
        Plant(id: "carrot", zh: "胡萝卜", en: "Carrot", emoji: "🥕", weights: [0.15, 0.25, 0.15, 0.45],
              zhNote: "根扎得深：心率平稳最重要", enNote: "Deep roots: a calm heart counts most"),
        Plant(id: "strawberry", zh: "草莓", en: "Strawberry", emoji: "🍓", weights: [0.25, 0.25, 0.25, 0.25],
              zhNote: "均衡：四项一样重，连胜加成翻倍", enNote: "Balanced: all four equal, double streak bonus"),
        Plant(id: "pumpkin", zh: "南瓜", en: "Pumpkin", emoji: "🎃", weights: [0.25, 0.3, 0.25, 0.2],
              zhNote: "大器晚成：前 7 天生长 ×0.8，之后 ×1.3", enNote: "Late bloomer: ×0.8 for the first 7 days, ×1.3 after"),
    ]
    static let fallback = all[4]

    /// "番茄"、"tomato"、"🍅" → tomato
    static func match(_ s: String?) -> Plant? {
        guard let t = s?.trimmingCharacters(in: .whitespaces).lowercased(), !t.isEmpty else { return nil }
        return all.first { t.contains($0.id) || t.contains($0.zh) || t.contains($0.en.lowercased()) || t.contains($0.emoji) }
    }
}

enum Element: Int, CaseIterable {
    case sun, water, nutrients, calm

    var emoji: String { ["☀️", "💧", "🌱", "🍃"][rawValue] }
    func name(_ lang: String) -> String { (lang == "zh" ? ["阳光", "水分", "养分", "平稳"] : ["Sun", "Water", "Nutrients", "Calm"])[rawValue] }
    func source(_ lang: String) -> String {
        (lang == "zh"
            ? ["步数：1 万步满分", "睡眠：7–9 小时满分，过少或过多都减分", "活动能量 500 千卡或锻炼 30 分钟满分，取较高的一项", "静息心率：不高于自己前 7 天平均就满分，每高 1 次/分减一点"]
            : ["Steps: full at 10,000", "Sleep: full at 7–9 h, less for too little or too much", "Active energy 500 kcal or exercise 30 min, whichever is higher", "Resting HR: full at or below your own 7-day average, a little less per bpm above"])[rawValue]
    }
}

/// One player's last snapshot of one day.
struct GardenDay: Codable, Equatable {
    var metrics: [String: Double]
    var plant: String?
}

/// player → date (yyyy-MM-dd) → snapshot
struct Ledger: Codable, Equatable {
    var players: [String: [String: GardenDay]] = [:]
}

struct PlayerResult {
    let name: String
    let plant: Plant
    let chosen: Bool  // false = no plant line yet, got the default
    let points: Double
    let daily: [Double?]  // per season day; nil = no data that day (or not yet)
    let today: [Double?]  // element values today; nil = not measured
    let metrics: [String: Double]  // today's numbers
    let baselineHR: Double?
    let streak: Int
    let hasToday: Bool

    var stage: Int { Garden.stages.lastIndex { points >= $0 } ?? 0 }
    var wilting: Bool { hasToday && (today[Element.water.rawValue] ?? 1) < 0.3 }
}

enum Garden {
    static let stages: [Double] = [0, 8, 25, 45, 70, 100, 130]
    static func stageName(_ i: Int, _ lang: String) -> String {
        (lang == "zh" ? ["种子", "发芽", "幼苗", "长叶", "开花", "结果", "丰收"] : ["Seed", "Sprout", "Seedling", "Leafy", "Blooming", "Fruiting", "Harvest"])[i]
    }

    static let dir = Paths.base.appendingPathComponent("garden", isDirectory: true)
    static let ledgerURL = dir.appendingPathComponent("ledger.json")
    static let lastInputURL = dir.appendingPathComponent("last-input.json")
    static var sharedFolder: URL { Paths.inboxes[1] }

    /// Where the page goes: the shared folder when it exists, else a local copy.
    static var pageURL: URL {
        FileManager.default.fileExists(atPath: sharedFolder.path) ? sharedFolder.appendingPathComponent("garden.html") : dir.appendingPathComponent("garden.html")
    }

    // MARK: rules

    static func sleepScore(_ h: Double) -> Double {
        if h < 4 { return 0.1 }
        if h < 7 { return 0.1 + (h - 4) / 3 * 0.9 }
        if h <= 9 { return 1 }
        if h <= 11 { return 1 - (h - 9) / 2 * 0.4 }
        return 0.5
    }

    /// The four elements, each 0–1; nil when the metric was not measured (people without a Watch).
    static func elements(_ m: [String: Double], baselineHR: Double?) -> [Double?] {
        let sun = m["steps"].map { min($0 / 10000, 1) }
        let water = m["sleep_h"].map(sleepScore)
        let food = [m["active_kcal"].map { $0 / 500 }, m["exercise_min"].map { $0 / 30 }].compactMap { $0 }.max().map { min($0, 1) }
        let calm = m["resting_hr"].map { hr -> Double in
            guard let b = baselineHR else { return 0.8 }
            let d = hr - b
            return d <= 0 ? 1 : max(0.3, 1 - d * 0.7 / 8)
        }
        return [sun, water, food, calm]
    }

    /// Growth points for one day, 0–10 before bonuses; an element that was not measured counts as 0.5.
    static func basePoints(_ e: [Double?], _ p: Plant) -> Double {
        10 * zip(e, p.weights).map { ($0 ?? 0.5) * $1 }.reduce(0, +)
    }

    static func days(from a: String, to b: String) -> Int {
        guard let x = HealthParser.dateFmt.date(from: a), let y = HealthParser.dateFmt.date(from: b) else { return 0 }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: x, to: y).day ?? 0
    }

    static func add(_ d: String, _ n: Int) -> String {
        let x = HealthParser.dateFmt.date(from: d) ?? Date()
        return HealthParser.dateFmt.string(from: Calendar(identifier: .gregorian).date(byAdding: .day, value: n, to: x)!)
    }

    /// Season dates containing `today`. Seasons are `length` days long and start at `start`
    /// (default: the first day anyone has data).
    static func season(_ ledger: Ledger, start: String?, length: Int, today: String) -> (index: Int, dates: [String]) {
        let first = start ?? ledger.players.values.flatMap { $0.keys }.min() ?? today
        let n = max(0, days(from: first, to: today)) / length
        let s = add(first, n * length)
        return (n + 1, (0..<length).map { add(s, $0) })
    }

    static func results(_ ledger: Ledger, dates: [String], today: String) -> [PlayerResult] {
        ledger.players.map { name, byDate in
            // the plant is locked for the season: the first one named in it
            let named = dates.compactMap { byDate[$0]?.plant }.compactMap { Plant.match($0) }.first
            let plant = named ?? Plant.fallback
            var points = 0.0, streak = 0
            var daily: [Double?] = []
            var todayE: [Double?] = [nil, nil, nil, nil], base: Double?
            for (i, d) in dates.enumerated() {
                guard d <= today, let day = byDate[d] else { daily.append(nil); if d <= today { streak = 0 }; continue }
                let prev = (1...7).compactMap { byDate[add(d, -$0)]?.metrics["resting_hr"] }
                let b = prev.count >= 2 ? prev.reduce(0, +) / Double(prev.count) : nil
                let e = elements(day.metrics, baselineHR: b)
                var p = basePoints(e, plant)
                streak = p >= 7 ? streak + 1 : 0
                if plant.id == "pumpkin" { p *= i < 7 ? 0.8 : 1.3 }
                if streak >= 3 { p += plant.id == "strawberry" ? 2 : 1 }
                points += p
                daily.append(p)
                if d == today { todayE = e; base = b }
            }
            let has = byDate[today] != nil
            return PlayerResult(name: name, plant: plant, chosen: named != nil, points: points, daily: daily, today: todayE,
                                metrics: byDate[today]?.metrics ?? [:], baselineHR: base, streak: has ? streak : 0, hasToday: has)
        }
        .sorted { $0.points != $1.points ? $0.points > $1.points : $0.name < $1.name }
    }

    // MARK: ledger

    static func loadLedger() -> Ledger {
        (try? Data(contentsOf: ledgerURL)).flatMap { try? JSONDecoder().decode(Ledger.self, from: $0) } ?? Ledger()
    }

    /// Record the latest numbers of you (under your garden name) and of everyone with a file in the shared folder,
    /// then rewrite the page if anything that shows on it changed. Returns the page when it was written.
    @discardableResult
    static func update(cfg: Config, today: String = HealthParser.dateFmt.string(from: Date())) -> URL? {
        var cfg = cfg
        var ledger = loadLedger()
        var records: [(String, DayRecord)] = HealthParser.people().compactMap { p in
            HealthParser.latestFile(person: p).flatMap(HealthParser.read).map { (p, $0) }
        }
        if !records.contains(where: { $0.0 == cfg.gardenName }), let f = HealthParser.latestFile(), var me = HealthParser.read(f) {
            me.plant = me.plant ?? cfg.gardenPlant
            records.append((cfg.gardenName, me))
        }
        for (name, r) in records {
            ledger.players[name, default: [:]][r.date] = GardenDay(metrics: r.metrics, plant: r.plant)
        }
        // fix season 1's first day once: deriving it from the ledger would drift after old days are pruned
        if cfg.gardenStart == nil {
            cfg.gardenStart = ledger.players.values.flatMap { $0.keys }.min() ?? today
            var c = Config.loadFile()
            c.gardenStart = cfg.gardenStart
            try? c.save()
        }
        let cutoff = add(today, -120)
        for k in ledger.players.keys { ledger.players[k] = ledger.players[k]!.filter { $0.key >= cutoff } }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(ledger) { try? d.write(to: ledgerURL, options: .atomic) }

        // rewrite only when the page's inputs changed, so the shared folder is not touched every minute
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys  // dictionary order differs between runs; the comparison must not
        let input = "\(today)|\(cfg.language)|\(cfg.gardenDays)|\(cfg.gardenStart ?? "")|\(cfg.gardenName)|" + (String(data: (try? enc.encode(ledger)) ?? Data(), encoding: .utf8) ?? "")
        let page = pageURL
        if (try? String(contentsOf: lastInputURL, encoding: .utf8)) == input, FileManager.default.fileExists(atPath: page.path) { return nil }
        let html = render(ledger, cfg: cfg, today: today, now: Date())
        do {
            try html.write(to: page, atomically: true, encoding: .utf8)
            try input.write(to: lastInputURL, atomically: true, encoding: .utf8)
            return page
        } catch { return nil }
    }

    /// Keep a player's history when they change their garden name.
    static func rename(from old: String, to new: String) {
        var l = loadLedger()
        guard old != new, let days = l.players.removeValue(forKey: old) else { return }
        l.players[new] = (l.players[new] ?? [:]).merging(days) { a, _ in a }
        if let d = try? JSONEncoder().encode(l) { try? d.write(to: ledgerURL, options: .atomic) }
    }

    // MARK: page

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func plantSVG(_ p: PlayerResult) -> String {
        let st = p.stage
        let stem = p.wilting ? "#a89a4a" : "#3f9b4b", leaf = p.wilting ? "#b8ad5c" : "#5cb85c"
        var s = #"<svg viewBox="0 0 120 150" class="plant" aria-hidden="true">"#
        s += #"<ellipse cx="60" cy="136" rx="48" ry="10" class="soil"/>"#
        if st == 0 {
            s += ##"<ellipse cx="60" cy="130" rx="7" ry="5" fill="#8d6e4a"/><path d="M57 128 q3 -4 6 0" stroke="#5d4630" stroke-width="1.2" fill="none"/>"##
            return s + "</svg>"
        }
        let h = 16.0 + Double(st) * 15
        let top = 132 - h
        s += #"<path d="M60 132 Q\#(p.wilting ? 70 : 56) \#(132 - h / 2) \#(p.wilting ? 68 : 60) \#(top)" stroke="\#(stem)" stroke-width="3.2" fill="none" stroke-linecap="round"/>"#
        for i in 0..<min(st + 1, 6) {
            let y = 128 - Double(i + 1) * (h / Double(min(st + 1, 6) + 1))
            let left = i % 2 == 0
            let a = p.wilting ? (left ? 30.0 : -30) : (left ? -35.0 : 35)  // drooping vs reaching up
            let x = left ? 50.0 : 70
            s += #"<ellipse cx="\#(x)" cy="\#(y)" rx="11" ry="4.6" fill="\#(leaf)" transform="rotate(\#(a) \#(left ? x + 8 : x - 8) \#(y))"/>"#
        }
        if st >= 4 { s += #"<text x="\#(p.wilting ? 68 : 60)" y="\#(top + 6)" font-size="20" text-anchor="middle">\#(p.plant.id == "sunflower" ? "🌻" : "🌼")</text>"# }
        if st >= 5 {
            let spots: [(Double, Double)] = st >= 6 ? [(40, top + 34), (82, top + 44), (58, top + 64)] : [(80, top + 36)]
            for (x, y) in spots { s += #"<text x="\#(x)" y="\#(y)" font-size="22" text-anchor="middle">\#(p.plant.emoji)</text>"# }
        }
        if st >= 6 { s += #"<text x="98" y="\#(top + 10)" font-size="14">✨</text>"# }
        return s + "</svg>"
    }

    static func metricText(_ e: Element, _ p: PlayerResult, _ lang: String) -> String {
        let m = p.metrics
        func f(_ k: String) -> String? { m[k].map { Metrics.format(k, $0) + " " + Metrics.byKey[k]!.unit(lang) } }
        switch e {
        case .sun: return f("steps") ?? "—"
        case .water: return f("sleep_h") ?? "—"
        case .nutrients: return [f("active_kcal"), f("exercise_min")].compactMap { $0 }.joined(separator: " · ").ifEmpty("—")
        case .calm:
            guard let hr = f("resting_hr") else { return "—" }
            return p.baselineHR.map { hr + (lang == "zh" ? "（基线 \(Int($0.rounded()))）" : " (base \(Int($0.rounded())))") } ?? hr
        }
    }

    static func render(_ ledger: Ledger, cfg: Config, today: String, now: Date) -> String {
        let lang = cfg.language == "zh" ? "zh" : "en"
        func t(_ en: String, _ zh: String) -> String { lang == "zh" ? zh : en }
        let (index, dates) = season(ledger, start: cfg.gardenStart, length: cfg.gardenDays, today: today)
        let day = (dates.firstIndex(of: today) ?? 0) + 1
        let players = results(ledger, dates: dates, today: today)
        let medals = ["🥇", "🥈", "🥉"]
        let time = now.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: lang == "zh" ? "zh_CN" : "en_US")))

        var h = """
        <!doctype html>
        <html lang="\(lang == "zh" ? "zh-CN" : "en")"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(t("HealthGlance Garden", "HealthGlance 菜园"))</title>
        <style>\(css)</style></head><body><main>
        <header><h1>🌱 \(t("HealthGlance Garden", "HealthGlance 菜园"))</h1>
        <p class="sub">\(t("Season \(index) · day \(day) of \(dates.count)", "第 \(index) 季 · 第 \(day) / \(dates.count) 天")) · \(t("updated", "更新于")) \(esc(time))</p></header>
        """
        if players.isEmpty {
            h += "<p class=\"empty\">\(t("No one has data yet. Files named health-<name>.txt in the shared HealthGlance folder join the garden.", "还没有人有数据。共享文件夹 HealthGlance 里的 health-名字.txt 会自动加入菜园。"))</p>"
        }
        // leaderboard
        h += "<section class=\"board\">"
        for (i, p) in players.enumerated() {
            h += """
            <div class="rank"><span class="medal">\(i < 3 ? medals[i] : "\(i + 1)")</span><span class="who">\(esc(p.name))</span>\
            <span class="pe">\(p.plant.emoji)</span><span class="pts">\(Int(p.points.rounded()))<small> \(t("pts", "分"))</small></span>\
            <span class="stg">\(stageName(p.stage, lang))</span></div>
            """
        }
        h += "</section><section class=\"field\">"
        // plots
        for p in players {
            let next = p.stage + 1 < stages.count ? stages[p.stage + 1] : nil
            let cur = stages[p.stage]
            let prog = next.map { min(1, (p.points - cur) / ($0 - cur)) } ?? 1
            var tags: [String] = []
            if !p.hasToday { tags.append("🏜️ " + t("No data yet today", "今天还没有数据")) }
            if p.wilting { tags.append("🥀 " + t("Thirsty: short sleep", "缺水：睡得太少")) }
            if p.streak >= 3 { tags.append("🔥 " + t("\(p.streak)-day streak", "连续 \(p.streak) 天高质量生长")) }
            if !p.chosen { tags.append("🎲 " + t("No plant chosen, using \(p.plant.name(lang))", "还没选植物，暂用\(p.plant.name(lang))")) }
            h += """
            <article class="plot"><div class="ph"><b>\(esc(p.name))</b><span>\(p.plant.emoji) \(p.plant.name(lang))</span></div>
            \(plantSVG(p))
            <div class="stage"><b>\(stageName(p.stage, lang))</b><span>\(Int(p.points.rounded())) \(t("pts", "分"))\(next.map { " · " + t("next at \(Int($0))", "下一阶段 \(Int($0))") } ?? "")</span></div>
            <div class="bar"><i style="width:\(Int(prog * 100))%"></i></div>
            <ul class="el">
            """
            for e in Element.allCases {
                let v = p.today[e.rawValue]
                h += """
                <li><span class="en">\(e.emoji) \(e.name(lang))</span><span class="eb"><i class="\(v == nil ? "na" : "")" style="width:\(Int(((v ?? (p.hasToday ? 0.5 : 0)) * 100).rounded()))%"></i></span>\
                <span class="ev">\(p.hasToday ? esc(metricText(e, p, lang)) : "—")\(v == nil && p.hasToday ? " ?" : "")</span></li>
                """
            }
            h += "</ul><div class=\"days\">"
            for (i, d) in p.daily.enumerated() {
                let isToday = dates[i] == today
                h += "<i class=\"\(d == nil ? "nd" : "")\(isToday ? " td" : "")\" style=\"height:\(Int(min(100, max(6, (d ?? 0) / 12 * 100))))%\" title=\"\(dates[i])\"></i>"
            }
            h += "</div>"
            if !tags.isEmpty { h += "<p class=\"tags\">" + tags.map { "<span>\(esc($0))</span>" }.joined() + "</p>" }
            h += "</article>"
        }
        h += "</section>"
        // today's report
        let withData = players.filter(\.hasToday)
        var lines: [String] = []
        func best(_ k: String, _ higher: Bool = true) -> PlayerResult? {
            withData.filter { $0.metrics[k] != nil }.max { higher ? $0.metrics[k]! < $1.metrics[k]! : $0.metrics[k]! > $1.metrics[k]! }
        }
        if let b = best("steps") { lines.append("☀️ " + t("Most sun: \(esc(b.name)) with \(Metrics.format("steps", b.metrics["steps"]!)) steps", "阳光最足：\(esc(b.name))，\(Metrics.format("steps", b.metrics["steps"]!)) 步")) }
        if let b = withData.filter({ $0.metrics["sleep_h"] != nil }).max(by: { sleepScore($0.metrics["sleep_h"]!) < sleepScore($1.metrics["sleep_h"]!) }) {
            lines.append("💧 " + t("Best watered: \(esc(b.name)), \(Metrics.format("sleep_h", b.metrics["sleep_h"]!)) h of sleep", "水分最好：\(esc(b.name))，睡了 \(Metrics.format("sleep_h", b.metrics["sleep_h"]!)) 小时"))
        }
        if let top = withData.max(by: { ($0.daily.compactMap { $0 }.last ?? 0) < ($1.daily.compactMap { $0 }.last ?? 0) }), let pts = top.daily.compactMap({ $0 }).last {
            lines.append("🌟 " + t("Fastest growth today: \(esc(top.name)), +\(String(format: "%.1f", pts))", "今天长得最快：\(esc(top.name))，+\(String(format: "%.1f", pts)) 分"))
        }
        for p in players where !p.hasToday { lines.append("🏜️ " + t("\(esc(p.name)) has not watered today", "\(esc(p.name)) 今天还没浇水")) }
        if !lines.isEmpty { h += "<section class=\"report\"><h2>\(t("Today", "今日播报"))</h2><ul>" + lines.map { "<li>\($0)</li>" }.joined() + "</ul></section>" }
        // rules
        h += "<details><summary>\(t("How it works", "规则"))</summary><div class=\"rules\">"
        h += "<p>\(t("Each day, your Health numbers become four growth elements, each from 0 to 1:", "每天，你的健康数据会变成四种成长要素，每种 0 到 1："))</p><ul>"
        for e in Element.allCases { h += "<li>\(e.emoji) <b>\(e.name(lang))</b>\(t(": ", "："))\(e.source(lang))</li>" }
        h += "</ul><p>\(t("Daily growth = 10 × the elements weighted by your plant (at most 10 points). An element your devices do not measure counts as 0.5, so having no Watch is not a penalty. A day without data adds nothing. Three or more days in a row with at least 7 points add 1 bonus point a day.", "每日生长 = 10 × 按植物权重加权的四项要素，最多 10 分。设备测不到的要素按 0.5 计，没有手表也不吃亏。没有数据的那天不生长。连续 3 天以上每天至少 7 分，每天额外加 1 分。"))</p>"
        h += "<table><tr><th>\(t("Plant", "植物"))</th><th>☀️</th><th>💧</th><th>🌱</th><th>🍃</th><th>\(t("Trait", "特点"))</th></tr>"
        for pl in Plant.all {
            h += "<tr><td>\(pl.emoji) \(pl.name(lang))</td>" + pl.weights.map { "<td>\(Int($0 * 100))%</td>" }.joined() + "<td>\(pl.note(lang))</td></tr>"
        }
        h += "</table><p>\(t("Stages", "阶段")): " + stages.enumerated().map { "\(stageName($0.offset, lang)) \(Int($0.element))" }.joined(separator: " → ") + "</p>"
        h += "<p>\(t("To choose a plant, add a line such as “plant: tomato” to the file your shortcut writes. The first plant named in a season is kept for that season. Seasons last \(cfg.gardenDays) days.", "选植物：在快捷指令写的文件里加一行，例如「植物: 番茄」。每一季以第一次写的植物为准，中途不能换。每季 \(cfg.gardenDays) 天。"))</p></div></details>"
        h += "<footer>\(t("Numbers come from each player's own Health app. Page made by \(esc(cfg.gardenName))'s Mac with HealthGlance. Not medical advice.", "数据来自每个人自己的「健康」App。页面由 \(esc(cfg.gardenName)) 的 Mac 用 HealthGlance 生成。不构成医疗建议。"))</footer>"
        return h + "</main></body></html>\n"
    }

    static let css = """
    :root{--bg:#f6f1e7;--card:#fffdf8;--ink:#2d2a26;--sub:#7a7166;--line:#e7dfd1;--soil:#b48a5f;--accent:#3f9b4b;--bar:#ece5d8;--gold:#e2a93b}
    @media (prefers-color-scheme:dark){:root{--bg:#1c1b19;--card:#262421;--ink:#efe9df;--sub:#a59c90;--line:#3a3631;--soil:#6e5538;--accent:#6cc36f;--bar:#3a3631}}
    *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.45 -apple-system,BlinkMacSystemFont,"PingFang SC","Helvetica Neue",sans-serif}
    main{max-width:980px;margin:0 auto;padding:20px 16px 40px}h1{font-size:26px;margin:0}h2{font-size:17px;margin:0 0 8px}
    .sub{color:var(--sub);margin:4px 0 18px}.empty{color:var(--sub)}
    .board{display:flex;flex-direction:column;gap:6px;margin-bottom:18px}
    .rank{display:grid;grid-template-columns:34px 1fr auto auto auto;align-items:center;gap:10px;background:var(--card);border:1px solid var(--line);border-radius:14px;padding:8px 14px}
    .medal{font-size:20px;text-align:center}.who{font-weight:600}.pe{font-size:20px}.pts{font-weight:700;font-variant-numeric:tabular-nums}.pts small{color:var(--sub);font-weight:500}.stg{color:var(--sub);font-size:13px;min-width:56px;text-align:right}
    .field{display:grid;grid-template-columns:repeat(auto-fill,minmax(270px,1fr));gap:14px}
    .plot{background:var(--card);border:1px solid var(--line);border-radius:20px;padding:14px 16px 12px}
    .ph{display:flex;justify-content:space-between;align-items:baseline}.ph span{color:var(--sub)}
    .plant{display:block;width:100%;height:150px;margin:4px 0}.soil{fill:var(--soil)}
    .stage{display:flex;justify-content:space-between;align-items:baseline;font-size:14px}.stage span{color:var(--sub);font-size:13px}
    .bar{height:8px;background:var(--bar);border-radius:4px;margin:6px 0 10px;overflow:hidden}.bar i{display:block;height:100%;background:var(--accent);border-radius:4px}
    .el{list-style:none;margin:0;padding:0;display:grid;grid-template-columns:auto 1fr auto;align-items:center;gap:5px 10px;font-size:13px}.el li{display:contents}
    .eb{height:6px;background:var(--bar);border-radius:3px;overflow:hidden}.eb i{display:block;height:100%;background:var(--gold);border-radius:3px}.eb i.na{background:repeating-linear-gradient(90deg,var(--gold) 0 4px,transparent 4px 7px)}
    .ev{color:var(--sub);text-align:right;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
    .days{display:flex;align-items:flex-end;gap:3px;height:34px;margin-top:10px;border-bottom:1px solid var(--line)}.days i{flex:1;background:var(--accent);opacity:.75;border-radius:2px 2px 0 0}.days i.nd{background:var(--line);opacity:1}.days i.td{opacity:1;outline:1.5px solid var(--ink)}
    .tags{margin:10px 0 0;display:flex;flex-wrap:wrap;gap:6px}.tags span{font-size:12px;background:var(--bar);border-radius:10px;padding:2px 8px}
    .report{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:14px 16px;margin-top:16px}.report ul{margin:0;padding-left:4px;list-style:none;display:grid;gap:4px}
    details{margin-top:16px;background:var(--card);border:1px solid var(--line);border-radius:16px;padding:12px 16px}summary{font-weight:600;cursor:pointer}
    .rules{font-size:14px}.rules table{border-collapse:collapse;width:100%;font-size:13px}.rules td,.rules th{border-bottom:1px solid var(--line);padding:5px 6px;text-align:left}
    footer{color:var(--sub);font-size:12px;margin-top:20px}
    """

    /// Made-up players for `healthwidget-cli --garden-demo`: 9 days of three people.
    static func demoLedger(today: String) -> Ledger {
        var l = Ledger()
        let people: [(String, String, (Int) -> [String: Double])] = [
            ("小林", "番茄", { i in ["steps": [11200, 9800, 12500, 8000, 13100, 10400, 9100, 12000, 11800][i], "sleep_h": [6.4, 7.1, 6.0, 6.8, 7.2, 6.5, 7.0, 6.2, 6.9][i], "active_kcal": [520, 430, 610, 380, 640, 500, 420, 560, 540][i], "resting_hr": [61, 60, 62, 61, 60, 59, 61, 60, 60][i]] }),
            ("阿杰", "西瓜", { i in ["steps": [5200, 6100, 4800, 7000, 5600, 6400, 5900, 6600, 5100][i], "sleep_h": [8.1, 7.9, 8.4, 7.6, 8.0, 8.2, 7.8, 8.3, 4.6][i], "active_kcal": [300, 340, 280, 360, 310, 330, 320, 350, 290][i], "resting_hr": [57, 56, 57, 55, 56, 56, 55, 56, 58][i]] }),
            ("小雨", "草莓", { i in ["steps": [8400, 9100, 7600, 8800, 9500, 8100, 9300, 8700, 6400][i], "sleep_h": [7.3, 7.6, 7.1, 7.4, 7.8, 7.0, 7.5, 7.2, 7.2][i], "active_kcal": [450, 480, 410, 470, 500, 430, 490, 460, 330][i], "resting_hr": [60, 59, 60, 59, 58, 60, 59, 59, 60][i]] }),
        ]
        for (name, plant, f) in people {
            for i in 0..<9 {
                if name == "阿杰" && i == 3 { continue }  // a day without data
                l.players[name, default: [:]][add(today, i - 8)] = GardenDay(metrics: f(i), plant: plant)
            }
        }
        l.players["小林"]![today] = nil  // has not synced today yet
        return l
    }
}

extension String {
    func ifEmpty(_ s: String) -> String { isEmpty ? s : self }
}
