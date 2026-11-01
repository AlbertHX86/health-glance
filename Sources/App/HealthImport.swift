import Foundation

/// Daily numbers from the Health app's own export (Health › your picture › Export All Health Data), for a history much
/// longer than the shortcut has written. Reads export.zip without unpacking it to disk, or the export.xml inside it.
///
/// Sums (steps, energy, exercise, distance, stand hours, sleep) are added up per source and the largest source counts,
/// so an iPhone and an Apple Watch counting the same steps are not added together. Sleep belongs to the day you wake
/// up on (it ends before 18:00 that day, or after 18:00 the day before). Heart rates are averaged; weight is the last one.
enum HealthImport {
    enum Kind { case sum, avg, last, sleep }

    static let types: [String: (key: String, kind: Kind)] = [
        "HKQuantityTypeIdentifierStepCount": ("steps", .sum),
        "HKQuantityTypeIdentifierActiveEnergyBurned": ("active_kcal", .sum),
        "HKQuantityTypeIdentifierAppleExerciseTime": ("exercise_min", .sum),
        "HKQuantityTypeIdentifierDistanceWalkingRunning": ("distance_km", .sum),
        "HKCategoryTypeIdentifierAppleStandHour": ("stand_h", .sum),
        "HKCategoryTypeIdentifierSleepAnalysis": ("sleep_h", .sleep),
        "HKQuantityTypeIdentifierRestingHeartRate": ("resting_hr", .avg),
        "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": ("hrv", .avg),
        "HKQuantityTypeIdentifierOxygenSaturation": ("spo2", .avg),
        "HKQuantityTypeIdentifierBodyMass": ("weight", .last),
    ]

    static let asleep: Set<String> = ["HKCategoryValueSleepAnalysisAsleep", "HKCategoryValueSleepAnalysisAsleepUnspecified",
                                      "HKCategoryValueSleepAnalysisAsleepCore", "HKCategoryValueSleepAnalysisAsleepDeep",
                                      "HKCategoryValueSleepAnalysisAsleepREM"]

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Read an export and merge its days into your history. `progress` gets the number of records read so far.
    static func run(_ url: URL, progress: @escaping (Int) -> Void = { _ in }) throws -> (days: Int, first: String, last: String) {
        let days = try read(url, progress: progress)
        guard let first = days.first?.date, let last = days.last?.date else {
            throw Failure(message: L.t("No Health records found in that file", "这个文件里没有找到健康记录"))
        }
        _ = try History.merge(days)
        return (days.count, first, last)
    }

    static func read(_ url: URL, progress: @escaping (Int) -> Void = { _ in }) throws -> [DayRecord] {
        let collector = Collector(progress: progress)
        let parser: XMLParser
        var unzip: Process?  // the tar streaming the zip
        var fifo: URL?
        if url.pathExtension.lowercased() == "zip" {
            guard let entry = try xmlEntry(in: url) else {
                throw Failure(message: L.t("No export.xml inside that zip", "压缩包里没有 export.xml"))
            }
            // tar (libarchive, which keeps the Chinese file names intact, unlike unzip) streams the XML into a named
            // pipe that the parser reads, so nothing large is written to disk
            let f = FileManager.default.temporaryDirectory.appendingPathComponent("healthglance-\(UUID().uuidString).xml")
            guard mkfifo(f.path, 0o600) == 0 else { throw Failure(message: "mkfifo failed") }
            fifo = f
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", "exec /usr/bin/tar -xOf \"$1\" \"$2\" > \"$3\"", "sh", url.path, entry, f.path]
            try p.run()
            unzip = p
            guard let s = InputStream(url: f) else { throw Failure(message: "cannot open the pipe") }
            parser = XMLParser(stream: s)
        } else {
            guard let s = InputStream(url: url) else { throw Failure(message: L.t("Cannot open the file", "打不开这个文件")) }
            parser = XMLParser(stream: s)
        }
        defer {
            unzip?.terminate()  // stops tar if parsing ended early
            if let fifo { try? FileManager.default.removeItem(at: fifo) }
        }
        parser.shouldResolveExternalEntities = false
        parser.delegate = collector
        if !parser.parse(), collector.records == 0 {
            throw Failure(message: parser.parserError?.localizedDescription ?? L.t("Could not read the export", "读不了这个导出文件"))
        }
        return collector.days()
    }

    /// The main XML in an export zip: "apple_health_export/export.xml" (导出.xml in Chinese), not the CDA file.
    static func xmlEntry(in zip: URL) throws -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        p.arguments = ["-tf", zip.path]
        let out = Pipe()
        p.standardOutput = out
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let names = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        return names.filter { n in
            n.lowercased().hasSuffix(".xml") && !n.lowercased().contains("cda") && n.split(separator: "/").count <= 2
        }.first
    }

    final class Collector: NSObject, XMLParserDelegate {
        let progress: (Int) -> Void
        var records = 0
        // date → metric → source → (sum, count, latest start)
        var acc: [String: [String: [String: (sum: Double, n: Int, at: String)]]] = [:]
        let stamp: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
            return f
        }()

        init(progress: @escaping (Int) -> Void) { self.progress = progress }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
            guard name == "Record", let type = a["type"], let (key, kind) = HealthImport.types[type],
                  let start = a["startDate"], start.count >= 10 else { return }
            records += 1
            if records % 50_000 == 0 { progress(records) }
            let source = a["sourceName"] ?? "?"
            var day = String(start.prefix(10))
            var value: Double
            switch kind {
            case .sleep:
                guard let v = a["value"], HealthImport.asleep.contains(v), let s = stamp.date(from: start),
                      let e = a["endDate"].flatMap(stamp.date(from:)), e > s else { return }
                value = e.timeIntervalSince(s) / 3600
                day = HealthParser.dateFmt.string(from: e.addingTimeInterval(6 * 3600))  // the night before belongs to the morning
            default:
                if type == "HKCategoryTypeIdentifierAppleStandHour" {
                    guard a["value"] == "HKCategoryValueAppleStandHourStood" else { return }
                    value = 1
                } else {
                    guard let v = a["value"].flatMap(Double.init) else { return }
                    value = HealthImport.convert(key, v, unit: a["unit"] ?? "")
                }
            }
            var cell = acc[day, default: [:]][key, default: [:]][source] ?? (0, 0, "")
            if kind == .last {
                if start >= cell.at { cell = (value, 1, start) }
            } else {
                cell.sum += value
                cell.n += 1
            }
            acc[day, default: [:]][key, default: [:]][source] = cell
        }

        func days() -> [DayRecord] {
            acc.keys.sorted().compactMap { date in
                var m: [String: Double] = [:]
                for (key, bySource) in acc[date]! {
                    let kind = HealthImport.types.values.first { $0.key == key }!.kind
                    switch kind {
                    case .sum, .sleep: m[key] = bySource.values.map(\.sum).max()
                    case .avg:
                        let n = bySource.values.map(\.n).reduce(0, +)
                        if n > 0 { m[key] = bySource.values.map(\.sum).reduce(0, +) / Double(n) }
                    case .last: m[key] = bySource.values.max { $0.at < $1.at }?.sum
                    }
                }
                m = m.filter { Metrics.plausible[$0.key]?.contains($0.value) ?? true }
                return m.isEmpty ? nil : DayRecord(date: date, metrics: m, raw: "", file: "Health export")
            }
        }
    }

    static func convert(_ key: String, _ v: Double, unit: String) -> Double {
        switch (key, unit.lowercased()) {
        case ("active_kcal", "kj"): return v / 4.184
        case ("distance_km", "mi"): return v * 1.609344
        case ("distance_km", "m"): return v / 1000
        case ("weight", "lb"): return v * 0.45359237
        case ("spo2", "%"): return v <= 1 ? v * 100 : v
        case ("spo2", _): return v <= 1 ? v * 100 : v
        default: return v
        }
    }
}
