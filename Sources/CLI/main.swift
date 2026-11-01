import Foundation

// healthwidget-cli [file]: parse a health file (or your newest one in the inbox) and print what was read;
// --sources prints the source test (sources.txt); --garden updates the garden page now; --garden-demo [--lang zh]
// renders made-up players into build/garden-demo.html;
// with --generate also call MiniMax and print the summary; add --save to write summary.json / history.json as the app does.

let args = Array(CommandLine.arguments.dropFirst())
L.lang = Config.load().language
if args.contains("--pets-demo") {
    let today = HealthParser.dateFmt.string(from: Date())
    var cfg = Config.load()
    if let i = args.firstIndex(of: "--lang"), i + 1 < args.count { cfg.language = args[i + 1] }
    cfg.gardenName = "小雨"
    cfg.gardenStart = Garden.add(today, -8)
    let out = URL(fileURLWithPath: "build/pets-demo.html")
    try! Pets.render(Garden.demoLedger(today: today), cfg: cfg, today: today, now: Date(), sprites: !args.contains("--no-sprites")).write(to: out, atomically: true, encoding: .utf8)
    print(out.path); exit(0)
}
if args.contains("--pets-gallery") {
    // one made-up player per rarity / legendary species, to look at every kind of pet
    let today = HealthParser.dateFmt.string(from: Date())
    var cfg = Config.load()
    if let i = args.firstIndex(of: "--lang"), i + 1 < args.count { cfg.language = args[i + 1] }
    var wanted: [String: String] = [:]
    for n in 1...3000 {
        let pet = Pet.hatch("Player \(n)", season: 1)
        let key = pet.species > 0 ? "s\(pet.species)" : "r\(pet.rarity)"
        if wanted[key] == nil { wanted[key] = "Player \(n)" }
        if wanted.count == 5 { break }
    }
    var l = Ledger()
    for (_, name) in wanted {
        for i in 0..<9 { l.players[name, default: [:]][Garden.add(today, i - 8)] = GardenDay(metrics: ["steps": 9000 + Double(i * 300), "sleep_h": 7.5, "active_kcal": 480, "resting_hr": 60], plant: nil) }
    }
    cfg.gardenStart = Garden.add(today, -8)
    let out = URL(fileURLWithPath: "build/pets-gallery.html")
    try! Pets.render(l, cfg: cfg, today: today, now: Date(), sprites: !args.contains("--no-sprites")).write(to: out, atomically: true, encoding: .utf8)
    print(out.path, wanted); exit(0)
}
if args.contains("--garden-demo") {
    // made-up players into build/garden-demo.html; the real ledger is not touched
    let today = HealthParser.dateFmt.string(from: Date())
    var cfg = Config.load()
    if let i = args.firstIndex(of: "--lang"), i + 1 < args.count { cfg.language = args[i + 1] }
    cfg.gardenName = "小雨"
    cfg.gardenStart = Garden.add(today, -8)
    let out = URL(fileURLWithPath: "build/garden-demo.html")
    try! Garden.render(Garden.demoLedger(today: today), cfg: cfg, today: today, now: Date()).write(to: out, atomically: true, encoding: .utf8)
    print(out.path); exit(0)
}
if args.contains("--garden") {
    let page = Garden.update(cfg: Config.load())
    print(page.map { "写入 \($0.path)" } ?? "没有变化：\(Garden.pageURL().path)"); exit(0)
}
if args.contains("--sources") {
    guard let r = Sources.latest() else { print("没有找到 sources.txt"); exit(1) }
    print("sources.txt 更新于 \(r.modified)")
    for c in r.counts { print("  \(c.n)\t\(c.name)") }
    exit(0)
}
let file = args.first { !$0.hasPrefix("--") }.map { URL(fileURLWithPath: $0) }
guard let url = file ?? HealthParser.latestFile(), let day = HealthParser.read(url) else {
    print("没有找到健康数据文件"); exit(1)
}
print("文件：\(url.path)\n日期：\(day.date)\n人：\(day.person ?? "自己")")
for d in Metrics.defs { if let v = day.metrics[d.key] { print("  \(d.name(L.lang)): \(Metrics.format(d.key, v)) \(d.unit(L.lang))") } }
if args.contains("--generate") {
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            let t0 = Date()
            let s = try await Engine.run(file: url, persist: args.contains("--save"))
            print(String(format: "\n耗时 %.1f 秒", Date().timeIntervalSince(t0)))
            print("标题：\(s.headline)\n小结：\(s.summary)\n建议：\(s.tips.joined(separator: " / "))")
        } catch { print("失败：\(error.localizedDescription)") }
        sem.signal()
    }
    sem.wait()
}
