import Foundation

/// API settings in ~/Library/Application Support/HealthWidget/config.json (mode 600); MINIMAX_API_KEY in the environment wins.
struct Config: Codable {
    var apiKey: String = ""
    var baseURL: String = "https://api.minimaxi.com/v1"
    var model: String = "MiniMax-M3.1-Flash"
    var reasoningEffort: String = "low"  // the model always thinks; a daily note needs little of it

    static func load() -> Config {
        var c = (try? Data(contentsOf: Paths.config)).flatMap { try? JSONDecoder().decode(Config.self, from: $0) } ?? Config()
        if let k = ProcessInfo.processInfo.environment["MINIMAX_API_KEY"], !k.isEmpty { c.apiKey = k }
        return c
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
        case .noKey: return "还没有填 MiniMax API Key"
        case .noData: return "没有找到健康数据文件（iCloud 云盘 › 快捷指令 › HealthWidget）"
        case let .http(code, body): return "MiniMax 接口返回 \(code)：\(body.prefix(200))"
        case let .badReply(s): return "模型回复无法解析：\(s.prefix(200))"
        case .truncated: return "模型思考过长，回复被截断，请再试一次"
        }
    }
}

enum Engine {
    static let system = """
    你是用户的私人健康数据助手。根据用户 iPhone「健康」App 导出的当日数据和过去 7 天的平均值，用简体中文写一份当日小结。
    要求：
    1. 只依据给出的数据，缺失的指标不要猜测或编造；引用具体数字，并与 7 天平均对比。
    2. 没有历史数据时，参考一般成年人的常见范围评价（每天约 7000–10000 步、睡眠 7–9 小时、静息心率 50–80 次/分）。今天的数据可能只是截至目前，步数少时不要下定论，可以提醒剩下的时间怎么安排。
    3. 标题要具体，点出今天最值得注意的一项，不要用「今日健康数据简报」这类空泛标题。建议要结合数据、可以马上做，不要「保持规律作息」这类泛泛之谈。
    4. 语气友好、简洁，不说教。不做医学诊断；如果某项明显异常（例如静息心率比平均高 5 次/分以上、睡眠少于 6 小时），温和提醒并建议关注。
    5. 只输出一个 JSON 对象，不要其他文字：
    {"headline": "一句话总结，不超过 14 个汉字", "summary": "2 到 3 句话，不超过 90 个汉字", "tips": ["今天可执行的建议，每条不超过 16 个汉字，1 到 3 条"]}
    """

    static func prompt(_ day: DayRecord, _ avg: [String: Double], _ days: Int) -> String {
        func line(_ m: [String: Double]) -> String {
            Metrics.defs.compactMap { d in m[d.key].map { "\(d.name) \(Metrics.format(d.key, $0)) \(d.unit)" } }.joined(separator: "；")
        }
        var s = "日期：\(day.date)（现在是 \(Date().formatted(date: .omitted, time: .shortened))）\n解析出的指标：\(day.metrics.isEmpty ? "（无）" : line(day.metrics))\n"
        s += avg.isEmpty ? "过去 7 天平均：暂无历史数据\n" : "过去 7 天平均（共 \(days) 天有数据）：\(line(avg))\n"
        s += "原始导出内容：\n\(day.raw)"
        return s
    }

    /// Reads the newest health file, asks MiniMax for a summary and writes summary.json for the widget
    /// (persist: false leaves history.json and summary.json untouched, for tests).
    static func run(file: URL? = nil, persist: Bool = true) async throws -> Summary {
        let cfg = Config.load()
        guard !cfg.apiKey.isEmpty else { throw EngineError.noKey }
        guard let url = file ?? HealthParser.latestFile(), let day = HealthParser.read(url) else { throw EngineError.noData }
        let all = try persist ? History.upsert(day) : History.load().filter { $0.date != day.date } + [day]
        let avg = History.weekAverage(all, before: day.date)
        let days = all.filter { $0.date < day.date }.suffix(7).count
        let reply = try await chat(cfg, prompt(day, avg, days))
        guard let obj = jsonObject(in: reply) else { throw EngineError.badReply(reply) }
        let s = Summary(
            date: day.date, generatedAt: Date(), model: cfg.model,
            headline: (obj["headline"] as? String) ?? "今日小结",
            summary: (obj["summary"] as? String) ?? reply,
            tips: (obj["tips"] as? [String]) ?? [],
            metrics: day.metrics, weekAvg: avg, error: nil)
        if persist { try s.save() }
        return s
    }

    static func chat(_ cfg: Config, _ user: String) async throws -> String {
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
