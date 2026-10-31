import SwiftUI

// The card drawn by the widget and by the app's desktop panel.

enum CardSize { case small, medium, large }

struct MetricTile: View {
    let key: String
    let value: Double
    let avg: Double?

    var body: some View {
        let def = Metrics.byKey[key]!
        VStack(alignment: .leading, spacing: 1) {
            Text(def.name).font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(Metrics.format(key, value)).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(def.unit).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            if let a = avg, a > 0 {
                let pct = (value - a) / a * 100
                Text(abs(pct) < 3 ? "≈ 均值" : String(format: "%@ %.0f%%", pct > 0 ? "↑" : "↓", abs(pct)))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CardView: View {
    let summary: Summary?
    let size: CardSize

    static let order = ["sleep_h", "steps", "resting_hr", "active_kcal", "exercise_min", "hrv", "stand_h", "distance_km", "hr", "spo2", "weight"]

    var body: some View {
        if let s = summary { content(s) } else { empty }
    }

    var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("健康小结", systemImage: "heart.text.square").font(.headline).foregroundStyle(.pink)
            Text("还没有数据。打开 HealthWidget，填入 API Key，并在 iPhone 上设置快捷指令。")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func header(_ s: Summary) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill").foregroundStyle(.pink).font(.system(size: 11))
            Text(shortDate(s.date)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if !Calendar.current.isDateInToday(s.generatedAt) {
                Text("旧").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
            }
        }
    }

    func tiles(_ s: Summary, _ n: Int) -> [String] {
        Array(Self.order.filter { s.metrics[$0] != nil }.prefix(n))
    }

    @ViewBuilder func content(_ s: Summary) -> some View {
        switch size {
        case .small:
            VStack(alignment: .leading, spacing: 6) {
                header(s)
                Text(s.headline).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 0)
                let keys = tiles(s, 2)
                HStack { ForEach(keys, id: \.self) { MetricTile(key: $0, value: s.metrics[$0]!, avg: s.weekAvg[$0]) } }
            }
        case .medium:
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    header(s)
                    let keys = tiles(s, 4)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                        ForEach(keys, id: \.self) { MetricTile(key: $0, value: s.metrics[$0]!, avg: s.weekAvg[$0]) }
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 128)
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.headline).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(s.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(5)
                    Spacer(minLength: 0)
                }
            }
        case .large:
            VStack(alignment: .leading, spacing: 8) {
                header(s)
                Text(s.headline).font(.system(size: 17, weight: .semibold))
                Text(s.summary).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                let keys = tiles(s, 6)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(keys, id: \.self) { MetricTile(key: $0, value: s.metrics[$0]!, avg: s.weekAvg[$0]) }
                }
                if !s.tips.isEmpty {
                    Divider()
                    ForEach(s.tips, id: \.self) { t in
                        Label(t, systemImage: "checkmark.circle").font(.system(size: 12)).foregroundStyle(.primary)
                    }
                }
                Spacer(minLength: 0)
                Text("由 \(s.model) 生成 · \(s.generatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    func shortDate(_ d: String) -> String {
        let p = d.split(separator: "-")
        return p.count == 3 ? "\(Int(p[1]) ?? 0)月\(Int(p[2]) ?? 0)日" : d
    }
}
