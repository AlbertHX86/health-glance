import Foundation

// healthwidget-cli [file]: parse a health file (or the newest one in the inbox) and print what was read;
// with --generate also call MiniMax and print the summary; add --save to write summary.json / history.json as the app does.

let args = Array(CommandLine.arguments.dropFirst())
let file = args.first { !$0.hasPrefix("--") }.map { URL(fileURLWithPath: $0) }
guard let url = file ?? HealthParser.latestFile(), let day = HealthParser.read(url) else {
    print("没有找到健康数据文件"); exit(1)
}
print("文件：\(url.path)\n日期：\(day.date)")
for d in Metrics.defs { if let v = day.metrics[d.key] { print("  \(d.name)：\(Metrics.format(d.key, v)) \(d.unit)") } }
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
