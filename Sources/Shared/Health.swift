import Foundation

// Shared by the menu-bar app and the widget: file locations, the daily health file parser and the summary cache.

enum Paths {
    /// Real home directory (inside the widget sandbox NSHomeDirectory() points at the container).
    static let home: URL = {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }()
    static let base = home.appendingPathComponent("Library/Application Support/HealthWidget", isDirectory: true)
    static let summary = base.appendingPathComponent("summary.json")
    static let history = base.appendingPathComponent("history.json")
    static let config = base.appendingPathComponent("config.json")
    /// The summary the widget shows: a copy of the person chosen in the menu.
    static let display = base.appendingPathComponent("display.json")
    /// iCloud Drive › 快捷指令 › HealthWidget (written by your iPhone shortcut); iCloud Drive › HealthGlance (a folder
    /// you share with someone, so their shortcut can drop files in); a local folder for manual drops.
    static let inboxes = [
        home.appendingPathComponent("Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/HealthWidget", isDirectory: true),
        home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/HealthGlance", isDirectory: true),
        base.appendingPathComponent("inbox", isDirectory: true),
    ]
    static let localInbox = inboxes[2]

    /// Your own data stays at the top level; each other person gets people/<name>/.
    static func dir(_ person: String?) -> URL {
        person.map { base.appendingPathComponent("people/\($0)", isDirectory: true) } ?? base
    }
    static func summary(_ person: String?) -> URL { dir(person).appendingPathComponent("summary.json") }
    static func history(_ person: String?) -> URL { dir(person).appendingPathComponent("history.json") }
}

struct MetricDef {
    let key: String, name: String, unit: String, en: String, enUnit: String, aliases: [String]

    func name(_ lang: String) -> String { lang == "zh" ? name : en }
    func unit(_ lang: String) -> String { lang == "zh" ? unit : enUnit }
}

/// UI and summary language, "en" or "zh" (config.json → language).
enum L {
    static var lang = "en"
    static func t(_ en: String, _ zh: String) -> String { lang == "zh" ? zh : en }
}

enum Metrics {
    static let defs: [MetricDef] = [
        MetricDef(key: "steps", name: "步数", unit: "步", en: "Steps", enUnit: "steps", aliases: ["步数", "steps", "step count", "step_count"]),
        MetricDef(key: "distance_km", name: "步行跑步距离", unit: "公里", en: "Distance", enUnit: "km",
                  aliases: ["步行+跑步距离", "步行跑步距离", "步行与跑步距离", "距离", "walking running distance", "walking_running_distance", "distance"]),
        MetricDef(key: "active_kcal", name: "活动能量", unit: "千卡", en: "Active energy", enUnit: "kcal",
                  aliases: ["活动能量", "动态能量", "活动卡路里", "active energy", "active_energy", "active calories"]),
        MetricDef(key: "exercise_min", name: "锻炼", unit: "分钟", en: "Exercise", enUnit: "min",
                  aliases: ["锻炼分钟", "锻炼时间", "锻炼分钟数", "锻炼", "exercise minutes", "exercise", "apple_exercise_time"]),
        MetricDef(key: "stand_h", name: "站立", unit: "小时", en: "Stand", enUnit: "h", aliases: ["站立小时", "站立小时数", "站立", "stand hours", "apple_stand_hour"]),
        MetricDef(key: "sleep_h", name: "睡眠", unit: "小时", en: "Sleep", enUnit: "h", aliases: ["睡眠时长", "睡眠", "sleep", "sleep_analysis", "sleep hours"]),
        MetricDef(key: "resting_hr", name: "静息心率", unit: "次/分", en: "Resting HR", enUnit: "bpm", aliases: ["静息心率", "resting heart rate", "resting_heart_rate"]),
        MetricDef(key: "hrv", name: "心率变异性", unit: "毫秒", en: "HRV", enUnit: "ms", aliases: ["心率变异性", "hrv", "heart rate variability", "heart_rate_variability"]),
        MetricDef(key: "hr", name: "平均心率", unit: "次/分", en: "Heart rate", enUnit: "bpm", aliases: ["平均心率", "心率", "heart rate", "heart_rate"]),
        MetricDef(key: "spo2", name: "血氧", unit: "%", en: "SpO₂", enUnit: "%", aliases: ["血氧饱和度", "血氧", "oxygen saturation", "blood_oxygen_saturation", "spo2"]),
        MetricDef(key: "weight", name: "体重", unit: "公斤", en: "Weight", enUnit: "kg", aliases: ["体重", "weight", "body mass", "body_mass"]),
    ]
    static let byKey = Dictionary(uniqueKeysWithValues: defs.map { ($0.key, $0) })

    /// Which metric a line's key names: exact alias first, else the longest alias it contains ("昨日步数" → steps).
    static func match(_ rawKey: String) -> MetricDef? {
        let k = rawKey.lowercased().trimmingCharacters(in: .whitespaces)
        if let d = defs.first(where: { $0.aliases.contains(k) }) { return d }
        var best: (MetricDef, Int)?
        for d in defs {
            for a in d.aliases where k.contains(a) && a.count > (best?.1 ?? 0) { best = (d, a.count) }
        }
        return best?.0
    }

    static func format(_ key: String, _ v: Double) -> String {
        switch key {
        case "steps": return v.formatted(.number.precision(.fractionLength(0)))  // 6,120
        case "active_kcal", "exercise_min", "stand_h", "resting_hr", "hr", "hrv", "spo2": return String(format: "%.0f", v)
        default: return String(format: "%.1f", v)
        }
    }
}

/// One day of health data as read from the inbox.
struct DayRecord: Codable {
    var date: String  // yyyy-MM-dd, the day the shortcut ran
    var metrics: [String: Double]
    var raw: String
    var file: String
    var person: String? = nil  // nil = you; from the file name health-<name>.txt
    var plant: String? = nil  // garden plant named in the file ("植物: 番茄")
}

enum HealthParser {
    static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Every data file in the inboxes with its modification date (.txt / .json / .md; sources.txt is the test file).
    static func files() -> [(url: URL, modified: Date)] {
        let fm = FileManager.default
        var out: [(URL, Date)] = []
        for dir in Paths.inboxes {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for u in items where ["txt", "json", "md"].contains(u.pathExtension.lowercased()) && u.lastPathComponent.lowercased() != Sources.file {
                out.append((u, (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast))
            }
        }
        return out
    }

    /// health-妈妈.txt → "妈妈"; health.txt or a dated file → nil (you). The invite shortcut names files after the
    /// phone, so "health-小林的iPhone.txt" → "小林" and "health-Lin’s iPhone.txt" → "Lin".
    /// Names whose health-<name>.txt is your own file (your phone's name, your game name); set when the config loads.
    static var me: [String] = []

    static func person(of url: URL) -> String? {
        guard let p = rawPerson(of: url) else { return nil }
        return me.contains { $0.caseInsensitiveCompare(p) == .orderedSame } ? nil : p
    }

    private static func rawPerson(of url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let m = name.firstMatch(#"(?i)^health[-_ ](.+)$"#) else { return nil }
        let p = m[1].replacingOccurrences(of: "/", with: "_").trimmingCharacters(in: .whitespaces)
        let short = p.replacingOccurrences(of: #"(?i)\s*(的|’s|'s)?\s*(iphone|ipad)(\s*\(\d+\))?\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return p.isEmpty ? nil : (short.isEmpty ? p : short)
    }

    /// Newest data file of one person (nil = you).
    static func latestFile(person: String? = nil) -> URL? {
        files().filter { self.person(of: $0.url) == person }.max { $0.modified < $1.modified }?.url
    }

    /// Other people who have a data file, sorted by name.
    static func people() -> [String] {
        Array(Set(files().compactMap { person(of: $0.url) })).sorted()
    }

    static func read(_ url: URL) -> DayRecord? {
        guard let data = try? Data(contentsOf: url), let raw = String(data: data, encoding: .utf8) else { return nil }
        let text = plainText(raw)
        var metrics: [String: Double] = [:]
        var date = fileDate(url) ?? dateFmt.string(from: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date())
        var pairs: [(String, String)] = []
        var plant: String?
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in obj { pairs.append((k, "\(v)")) }
        } else {
            for line in text.components(separatedBy: .newlines) {
                guard let r = line.range(of: "[:：=]", options: .regularExpression) else { continue }
                pairs.append((String(line[..<r.lowerBound]), String(line[r.upperBound...])))
            }
        }
        for (k, v) in pairs {
            let key = k.trimmingCharacters(in: .whitespaces)
            if ["日期", "date"].contains(key.lowercased()), let d = firstDate(v) { date = d; continue }
            if ["植物", "plant", "作物", "crop"].contains(key.lowercased()) { plant = v.trimmingCharacters(in: .whitespaces); continue }
            guard let def = Metrics.match(key), metrics[def.key] == nil, let x = value(def.key, v) else { continue }
            metrics[def.key] = x
        }
        return DayRecord(date: date, metrics: metrics, raw: String(text.prefix(4000)), file: url.lastPathComponent, person: person(of: url), plant: plant)
    }

    static func fileDate(_ url: URL) -> String? { firstDate(url.lastPathComponent) }

    /// Shortcuts sometimes saves rich text; keep only the visible text of an RTF file (an empty Text becomes an RTF
    /// skeleton with no text at all).
    static func plainText(_ s: String) -> String {
        guard s.hasPrefix("{\\rtf") else { return s }
        var t = s.replacingOccurrences(of: #"\{\\\*[^{}]*\}"#, with: "", options: .regularExpression)  // {\*\expandedcolortbl;;}
        t = t.replacingOccurrences(of: #"\{\\(fonttbl|colortbl)[^{}]*(\{[^{}]*\}[^{}]*)*\}"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\\(par|line)\b ?"#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\\'([0-9a-f]{2})"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\\[a-z]+-?\d* ?"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\\n", with: "\n")
        return t.replacingOccurrences(of: "[{}]", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func firstDate(_ s: String) -> String? {
        guard let r = s.range(of: #"\d{4}-\d{1,2}-\d{1,2}"#, options: .regularExpression) else { return nil }
        let p = s[r].split(separator: "-").compactMap { Int($0) }
        return String(format: "%04d-%02d-%02d", p[0], p[1], p[2])
    }

    /// Numbers as the Shortcuts app writes them ("8,234"、"7 小时 12 分钟"、"512 千卡"、"68.5 kg"), converted to the metric's unit.
    static func value(_ key: String, _ s: String) -> Double? {
        let t = s.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "\u{00a0}", with: " ").lowercased()
        let nums = t.matches(#"-?\d+(\.\d+)?"#).compactMap(Double.init)
        guard let first = nums.first else { return nil }
        switch key {
        case "sleep_h":
            if let hm = t.firstMatch(#"(\d+):(\d{2})"#) { return Double(hm[1])! + Double(hm[2])! / 60 }
            let h = t.firstMatch(#"(\d+(\.\d+)?)\s*(小时|时|h|hr|hours?)"#).flatMap { Double($0[1]) }
            let m = t.firstMatch(#"(\d+(\.\d+)?)\s*(分钟|分|m|min|minutes?)\b"#).flatMap { Double($0[1]) }
            if h != nil || m != nil { return (h ?? 0) + (m ?? 0) / 60 }
            if t.contains("秒") || first > 1440 { return first / 3600 }  // seconds
            if first > 24 { return first / 60 }  // minutes
            return first
        case "exercise_min":
            if let h = t.firstMatch(#"(\d+(\.\d+)?)\s*(小时|h)"#).flatMap({ Double($0[1]) }) {
                let m = t.firstMatch(#"(\d+)\s*(分钟|分|min)"#).flatMap { Double($0[1]) } ?? 0
                return h * 60 + m
            }
            return first
        case "active_kcal":
            return t.contains("kj") || t.contains("千焦") ? first / 4.184 : first
        case "distance_km":
            return t.contains("km") || t.contains("公里") || t.contains("千米") ? first : (t.contains("mi") ? first * 1.609 : (first > 200 ? first / 1000 : first))
        case "weight":
            if t.contains("斤") && !t.contains("公斤") { return first / 2 }
            if t.contains("lb") || t.contains("磅") { return first * 0.4536 }
            return first
        case "spo2":
            return first <= 1 ? first * 100 : first
        default:
            return first
        }
    }
}

extension String {
    func matches(_ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: self, range: NSRange(startIndex..., in: self)).compactMap { Range($0.range, in: self).map { String(self[$0]) } }
    }

    /// Capture groups of the first match (index 0 = whole match).
    func firstMatch(_ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: self).map { String(self[$0]) } ?? "" }
    }
}

/// What the widget shows; written by the app after each generation.
struct Summary: Codable {
    var date: String
    var generatedAt: Date
    var model: String
    var headline: String
    var summary: String
    var tips: [String]
    var metrics: [String: Double]
    var weekAvg: [String: Double]
    var error: String?
    var lang: String?  // language the text was written in; nil = before languages existed (Chinese)
    var person: String? = nil  // nil = you

    static func load(_ person: String? = nil) -> Summary? { read(Paths.summary(person)) }

    /// What the widget shows (the person chosen in the menu), falling back to your own summary.
    static func loadDisplay() -> Summary? { read(Paths.display) ?? load() }

    static func read(_ url: URL) -> Summary? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Summary.self, from: d)
    }

    func save(to url: URL? = nil) throws {
        let url = url ?? Paths.summary(person)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }

    /// Made-up numbers for the widget gallery preview and the README screenshots.
    static func placeholder(_ lang: String) -> Summary {
        let m: [String: Double] = ["steps": 6120, "sleep_h": 7.4, "resting_hr": 58, "active_kcal": 410, "exercise_min": 22, "hrv": 46]
        let avg: [String: Double] = ["steps": 8300, "sleep_h": 6.8, "resting_hr": 59, "active_kcal": 480, "exercise_min": 30, "hrv": 44]
        if lang == "zh" {
            return Summary(date: "2026-10-31", generatedAt: Date(), model: "MiniMax-M3.1-Flash", headline: "睡得不错，活动略少",
                           summary: "昨晚睡了 7.4 小时，比近 7 天平均多 0.6 小时；步数 6,120，低于平均的 8,300。静息心率 58，平稳。",
                           tips: ["午饭后走 15 分钟", "今晚 23:30 前上床"], metrics: m, weekAvg: avg, error: nil, lang: "zh")
        }
        return Summary(date: "2026-10-31", generatedAt: Date(), model: "MiniMax-M3.1-Flash", headline: "Slept well, moved less",
                       summary: "You slept 7.4 h, 0.6 h more than your 7-day average. Steps are at 6,120, below your usual 8,300. Resting HR is steady at 58.",
                       tips: ["Take a 15-minute walk after lunch", "Aim for bed by 11:30 pm"], metrics: m, weekAvg: avg, error: nil, lang: "en")
    }
}

/// Past days, one record per date, newest last; kept to 30 days.
enum History {
    static func load(_ person: String? = nil) -> [DayRecord] {
        guard let d = try? Data(contentsOf: Paths.history(person)) else { return [] }
        return (try? JSONDecoder().decode([DayRecord].self, from: d)) ?? []
    }

    static func upsert(_ r: DayRecord) throws -> [DayRecord] {
        var all = load(r.person).filter { $0.date != r.date }
        all.append(r)
        all.sort { $0.date < $1.date }
        all = Array(all.suffix(30))
        try FileManager.default.createDirectory(at: Paths.dir(r.person), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(all).write(to: Paths.history(r.person), options: .atomic)
        return all
    }

    /// Mean of each metric over the 7 days before `date`.
    static func weekAverage(_ all: [DayRecord], before date: String) -> [String: Double] {
        let prev = all.filter { $0.date < date }.suffix(7)
        var out: [String: Double] = [:]
        for def in Metrics.defs {
            let xs = prev.compactMap { $0.metrics[def.key] }
            if !xs.isEmpty { out[def.key] = xs.reduce(0, +) / Double(xs.count) }
        }
        return out
    }
}

/// The source test: a shortcut writes the source (device or app) of every recent Health sample to sources.txt,
/// one per line. Seeing another person's device here would mean the iPhone can read their shared data.
enum Sources {
    static let file = "sources.txt"

    static func latest() -> (modified: Date, counts: [(name: String, n: Int)])? {
        let found = Paths.inboxes.map { $0.appendingPathComponent(file) }.compactMap { u -> (URL, Date)? in
            guard let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
            return (u, d)
        }
        guard let (url, modified) = found.max(by: { $0.1 < $1.1 }), let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var n: [String: Int] = [:]
        for line in HealthParser.plainText(raw).components(separatedBy: .newlines) {
            let name = line.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { n[name, default: 0] += 1 }
        }
        return (modified, n.map { ($0.key, $0.value) }.sorted { $0.n > $1.n })
    }
}
