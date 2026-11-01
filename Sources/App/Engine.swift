import Foundation

/// Settings in ~/Library/Application Support/HealthWidget/config.json (mode 600); MINIMAX_API_KEY in the environment wins.
struct Config: Codable {
    var apiKey = ""
    var baseURL = "https://api.minimaxi.com/v1"
    var model = "MiniMax-M3.1-Flash"
    var reasoningEffort = "low"  // the model always thinks; a daily note needs little of it
    var language = "en"  // "en" or "zh": the app, the widget, the summary and the garden page
    // garden: only one Mac should host (write garden.html into the shared folder)
    var gardenHost = false
    var gameMode = "pets"  // "pets" (Puff battles) or "garden"
    var gardenName = NSFullUserName().isEmpty ? "Me" : NSFullUserName()
    var gardenPlant = "strawberry"
    var gardenDays = 14
    var gardenStart: String? = nil  // yyyy-MM-dd; default: the first day anyone has data
    var gameID = 0  // raised by New game, so the eggs roll again
    var inviteFolderLink = ""  // iCloud share link of the HealthGlance folder
    var inviteShortcutLink = ""  // iCloud link of the players' shortcut

    init() {}

    /// Missing keys keep their defaults, so a config written by an older version still loads (and keeps its key).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? d.apiKey
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? d.baseURL
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        reasoningEffort = try c.decodeIfPresent(String.self, forKey: .reasoningEffort) ?? d.reasoningEffort
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? d.language
        gardenHost = try c.decodeIfPresent(Bool.self, forKey: .gardenHost) ?? d.gardenHost
        gameMode = try c.decodeIfPresent(String.self, forKey: .gameMode) ?? d.gameMode
        gardenName = try c.decodeIfPresent(String.self, forKey: .gardenName) ?? d.gardenName
        gardenPlant = try c.decodeIfPresent(String.self, forKey: .gardenPlant) ?? d.gardenPlant
        gardenDays = max(3, try c.decodeIfPresent(Int.self, forKey: .gardenDays) ?? d.gardenDays)
        gardenStart = try c.decodeIfPresent(String.self, forKey: .gardenStart) ?? d.gardenStart
        gameID = try c.decodeIfPresent(Int.self, forKey: .gameID) ?? d.gameID
        inviteFolderLink = try c.decodeIfPresent(String.self, forKey: .inviteFolderLink) ?? d.inviteFolderLink
        inviteShortcutLink = try c.decodeIfPresent(String.self, forKey: .inviteShortcutLink) ?? d.inviteShortcutLink
    }

    static func load() -> Config {
        var c = loadFile()
        if let k = ProcessInfo.processInfo.environment["MINIMAX_API_KEY"], !k.isEmpty { c.apiKey = k }
        return c
    }

    /// The file alone, without the environment override; start from this when changing and saving settings.
    static func loadFile() -> Config {
        (try? Data(contentsOf: Paths.config)).flatMap { try? JSONDecoder().decode(Config.self, from: $0) } ?? Config()
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Paths.base, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: Paths.config, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Paths.config.path)
    }
}

enum EngineError: LocalizedError {
    case noKey, noData, http(Int, String), badReply(String), truncated
    var errorDescription: String? {
        switch self {
        case .noKey: return L.t("No MiniMax API key yet", "还没有填 MiniMax API Key")
        case .noData: return L.t("No health data file found (iCloud Drive › Shortcuts › HealthWidget)", "没有找到健康数据文件（iCloud 云盘 › 快捷指令 › HealthWidget）")
        case let .http(code, body): return L.t("MiniMax returned \(code): ", "MiniMax 接口返回 \(code)：") + body.prefix(200)
        case let .badReply(s): return L.t("Could not read the model's reply: ", "模型回复无法解析：") + s.prefix(200)
        case .truncated: return L.t("The model thought too long and the reply was cut off; try again", "模型思考过长，回复被截断，请再试一次")
        }
    }
}

enum Engine {
    static let systemEN = """
    You are the user's personal health-data assistant. From today's numbers, exported from the iPhone Health app, and the average of the previous 7 days, write a short daily summary in English.
    Rules:
    1. Use only the data given. Do not guess or invent missing metrics. Quote specific numbers and compare them with the 7-day average.
    2. With no history, judge against common adult ranges (about 7,000–10,000 steps a day, 7–9 hours of sleep, resting heart rate 50–80 bpm). Today's numbers may cover only part of the day: if steps are low, do not conclude anything; suggest how to use the rest of the day.
    3. The headline must be specific and name the most notable item, not a generic title like "Daily health report". Tips must follow from the data and be doable right away, not generic advice like "keep a regular routine".
    4. Friendly, concise, never preachy. No medical diagnosis. If something is clearly off (for example resting heart rate 5+ bpm above average, or under 6 hours of sleep), mention it gently and suggest keeping an eye on it.
    5. Write in English only. Output one JSON object and nothing else:
    {"headline": "a summary of at most 5 words", "summary": "2 to 3 sentences, at most 35 words in total", "tips": ["an action for today, at most 7 words; 1 to 3 tips"]}
    """

    static let systemZH = """
    你是用户的私人健康数据助手。根据用户 iPhone「健康」App 导出的当日数据和过去 7 天的平均值，用简体中文写一份当日小结。
    要求：
    1. 只依据给出的数据，缺失的指标不要猜测或编造；引用具体数字，并与 7 天平均对比。
    2. 没有历史数据时，参考一般成年人的常见范围评价（每天约 7000–10000 步、睡眠 7–9 小时、静息心率 50–80 次/分）。今天的数据可能只是截至目前，步数少时不要下定论，可以提醒剩下的时间怎么安排。
    3. 标题要具体，点出今天最值得注意的一项，不要用「今日健康数据简报」这类空泛标题。建议要结合数据、可以马上做，不要「保持规律作息」这类泛泛之谈。
    4. 语气友好、简洁，不说教。不做医学诊断；如果某项明显异常（例如静息心率比平均高 5 次/分以上、睡眠少于 6 小时），温和提醒并建议关注。
    5. 只输出一个 JSON 对象，不要其他文字：
    {"headline": "一句话总结，不超过 14 个汉字", "summary": "2 到 3 句话，不超过 90 个汉字", "tips": ["今天可执行的建议，每条不超过 16 个汉字，1 到 3 条"]}
    """

    static func prompt(_ day: DayRecord, _ avg: [String: Double], _ days: Int, _ lang: String) -> String {
        func line(_ m: [String: Double]) -> String {
            Metrics.defs.compactMap { d in m[d.key].map { "\(d.name(lang)) \(Metrics.format(d.key, $0)) \(d.unit(lang))" } }
                .joined(separator: lang == "zh" ? "；" : "; ")
        }
        let now = Date().formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: lang == "zh" ? "zh_CN" : "en_US")))
        if lang != "zh" {
            var s = day.person.map { "This data belongs to \($0), who shares their Health data with the user. Write about \($0) in the third person.\n" } ?? ""
            s += "Date: \(day.date) (it is now \(now))\nParsed metrics: \(day.metrics.isEmpty ? "(none)" : line(day.metrics))\n"
            s += avg.isEmpty ? "Previous 7-day average: no history yet\n" : "Previous 7-day average (\(days) days with data): \(line(avg))\n"
            return s + "Raw export:\n\(day.raw)"
        }
        var s = day.person.map { "这些数据属于「\($0)」，是对方共享给用户的。请用第三人称写「\($0)」。\n" } ?? ""
        s += "日期：\(day.date)（现在是 \(now)）\n解析出的指标：\(day.metrics.isEmpty ? "（无）" : line(day.metrics))\n"
        s += avg.isEmpty ? "过去 7 天平均：暂无历史数据\n" : "过去 7 天平均（共 \(days) 天有数据）：\(line(avg))\n"
        s += "原始导出内容：\n\(day.raw)"
        return s
    }

    /// Reads the newest health file, asks MiniMax for a summary and writes summary.json for the widget
    /// (persist: false leaves history.json and summary.json untouched, for tests).
    static func run(file: URL? = nil, person: String? = nil, persist: Bool = true) async throws -> Summary {
        let cfg = Config.load()
        guard !cfg.apiKey.isEmpty else { throw EngineError.noKey }
        guard let url = file ?? HealthParser.latestFile(person: person), let day = HealthParser.read(url) else { throw EngineError.noData }
        let all = try persist ? History.upsert(day) : History.load(day.person).filter { $0.date != day.date } + [day]
        let avg = History.weekAverage(all, before: day.date)
        let days = all.filter { $0.date < day.date }.suffix(7).count
        let lang = cfg.language == "zh" ? "zh" : "en"
        let reply = try await chat(cfg, lang == "zh" ? systemZH : systemEN, prompt(day, avg, days, lang))
        guard let obj = jsonObject(in: reply) else { throw EngineError.badReply(reply) }
        let s = Summary(
            date: day.date, generatedAt: Date(), model: cfg.model,
            headline: (obj["headline"] as? String) ?? (lang == "zh" ? "今日小结" : "Today"),
            summary: (obj["summary"] as? String) ?? reply,
            tips: (obj["tips"] as? [String]) ?? [],
            metrics: day.metrics, weekAvg: avg, error: nil, lang: lang, person: day.person)
        if persist { try s.save() }
        return s
    }

    static func chat(_ cfg: Config, _ system: String, _ user: String) async throws -> String {
        var req = URLRequest(url: URL(string: cfg.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": cfg.model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "max_tokens": 8192,  // includes the reasoning tokens
            "reasoning_effort": cfg.reasoningEffort,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8) ?? ""
        guard code == 200 else { throw EngineError.http(code, text) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (obj["choices"] as? [[String: Any]])?.first,
              let msg = choice["message"] as? [String: Any]
        else { throw EngineError.badReply(text) }
        let content = (msg["content"] as? String) ?? ""
        if choice["finish_reason"] as? String == "length", jsonObject(in: content) == nil { throw EngineError.truncated }
        // reasoning normally arrives in reasoning_content; drop any inline <think> block as well
        return content.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The outermost {...} in the reply (models sometimes wrap JSON in a code fence).
    static func jsonObject(in s: String) -> [String: Any]? {
        guard let a = s.firstIndex(of: "{"), let b = s.lastIndex(of: "}"), a < b else { return nil }
        return (try? JSONSerialization.jsonObject(with: Data(s[a...b].utf8))) as? [String: Any]
    }
}
