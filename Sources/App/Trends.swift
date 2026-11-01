import Charts
import SwiftUI

/// A chart the model asked for in an answer: one metric over the last days, as a line or as daily bars, with the
/// average and an optional goal. Long ranges are drawn as weekly means so the line stays readable.
struct ChartBlock: View {
    let spec: Engine.ChartSpec
    let history: [DayRecord]
    let today: Summary?
    let lang: String

    func t(_ en: String, _ zh: String) -> String { lang == "zh" ? zh : en }

    struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    var points: [Point] {
        let f = HealthParser.dateFmt
        let from = f.string(from: Calendar.current.date(byAdding: .day, value: -(spec.days - 1), to: Date())!)
        var byDate = Dictionary(history.compactMap { d in d.metrics[spec.metric].map { (d.date, $0) } }, uniquingKeysWith: { _, b in b })
        if let s = today, let v = s.metrics[spec.metric] { byDate[s.date] = v }
        let daily = byDate.filter { $0.key >= from }.compactMap { k, v in f.date(from: k).map { Point(date: $0, value: v) } }
            .sorted { $0.date < $1.date }
        guard spec.days > 120 else { return daily }
        let cal = Calendar.current
        let weeks = Dictionary(grouping: daily) { cal.dateInterval(of: .weekOfYear, for: $0.date)!.start }
        return weeks.map { Point(date: $0.key, value: $0.value.map(\.value).reduce(0, +) / Double($0.value.count)) }.sorted { $0.date < $1.date }
    }

    var title: String {
        let name = Metrics.byKey[spec.metric]?.name(lang) ?? spec.metric
        return lang == "zh" ? "\(name) · 最近 \(spec.days) 天" : "\(name) · last \(spec.days) days"
    }

    var body: some View {
        let key = spec.metric
        let pts = points
        let tint = MetricStyle.tint(key)
        let label = Metrics.byKey[key]?.name(lang) ?? key
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: MetricStyle.icon(key))
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            if pts.count < 2 {
                Text(t("Not enough days yet: the shortcut sends the last 30 days each time it runs.",
                       "天数还不够：快捷指令每次运行都会带上最近 30 天的数据。"))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                let values = pts.map(\.value)
                let avg = values.reduce(0, +) / Double(values.count)
                let bars = spec.type == "bar" && spec.days <= 120
                Chart {
                    ForEach(pts) { p in
                        if bars {
                            BarMark(x: .value("Date", p.date, unit: .day), y: .value(label, p.value))
                                .foregroundStyle(spec.goal.map { p.value >= $0 ? tint : tint.opacity(0.45) } ?? tint)
                                .cornerRadius(3)
                        } else {
                            AreaMark(x: .value("Date", p.date), y: .value(label, p.value))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("Date", p.date), y: .value(label, p.value))
                                .interpolationMethod(.monotone)
                                .foregroundStyle(tint)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        }
                    }
                    RuleMark(y: .value("Average", avg))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    if let g = spec.goal {
                        RuleMark(y: .value("Goal", g))
                            .foregroundStyle(.green.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1.2))
                            .annotation(position: .top, alignment: .trailing) {
                                Text(t("goal ", "目标 ") + Metrics.format(key, g)).font(.system(size: 9, weight: .medium)).foregroundStyle(.green)
                            }
                    }
                }
                .chartYScale(domain: .automatic(includesZero: bars || ["steps", "active_kcal", "exercise_min", "distance_km", "stand_h"].contains(key)))
                .chartXAxis {
                    if spec.days <= 120 {
                        AxisMarks(values: .stride(by: .day, count: max(1, spec.days / 4))) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), collisionResolution: .greedy)
                        }
                    } else {
                        AxisMarks(values: .stride(by: .month, count: spec.days > 400 ? 4 : 2)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.abbreviated), collisionResolution: .greedy)
                        }
                    }
                }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .frame(height: 120)
                HStack(spacing: 10) {
                    stat(t("Average", "平均"), avg)
                    stat(t("Low", "最低"), values.min()!)
                    stat(t("High", "最高"), values.max()!)
                    Spacer(minLength: 0)
                    if spec.days > 120 { Text(t("weekly means", "按周平均")).font(.system(size: 10)).foregroundStyle(.tertiary) }
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func stat(_ label: String, _ v: Double) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(.secondary)
            // the title names the metric; steps need no unit, which keeps the row on one line
            Text(Metrics.format(spec.metric, v) + (spec.metric == "steps" ? "" : " " + (Metrics.byKey[spec.metric]?.unit(lang) ?? ""))).monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium))
        .lineLimit(1)
    }
}
