import Charts
import SwiftUI

/// A line chart of one metric over the last week to two years, from the person's history (and today's numbers).
/// Long ranges are drawn as weekly means so the line stays readable.
struct TrendsView: View {
    @ObservedObject var model: Model

    static let ranges: [(days: Int, en: String, zh: String)] = [(7, "1W", "1周"), (30, "1M", "1月"), (90, "3M", "3月"), (365, "1Y", "1年"), (730, "2Y", "2年")]

    func t(_ en: String, _ zh: String) -> String { model.lang == "zh" ? zh : en }

    struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    /// Metrics there is something to draw for, in the card's order.
    var metrics: [String] {
        let have = Set(model.history.flatMap { $0.metrics.keys })
        return CardView.order.filter { have.contains($0) }
    }

    var points: [Point] {
        let f = HealthParser.dateFmt
        let from = f.string(from: Calendar.current.date(byAdding: .day, value: -(model.trendDays - 1), to: Date())!)
        var byDate = Dictionary(model.history.compactMap { d in d.metrics[model.trendMetric].map { (d.date, $0) } }, uniquingKeysWith: { _, b in b })
        if let s = model.summary, let v = s.metrics[model.trendMetric] { byDate[s.date] = v }
        let daily = byDate.filter { $0.key >= from }.compactMap { k, v in f.date(from: k).map { Point(date: $0, value: v) } }
            .sorted { $0.date < $1.date }
        guard model.trendDays > 120 else { return daily }
        let cal = Calendar.current
        let weeks = Dictionary(grouping: daily) { cal.dateInterval(of: .weekOfYear, for: $0.date)!.start }
        return weeks.map { Point(date: $0.key, value: $0.value.map(\.value).reduce(0, +) / Double($0.value.count)) }.sorted { $0.date < $1.date }
    }

    var body: some View {
        let key = model.trendMetric
        let pts = points
        let tint = MetricStyle.tint(key)
        let def = Metrics.byKey[key]
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $model.trendMetric) {
                    ForEach(metrics.isEmpty ? [key] : metrics, id: \.self) { k in
                        Label(Metrics.byKey[k]?.name(model.lang) ?? k, systemImage: MetricStyle.icon(k)).tag(k)
                    }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                Spacer(minLength: 0)
                Picker("", selection: $model.trendDays) {
                    ForEach(Self.ranges, id: \.days) { r in Text(model.lang == "zh" ? r.zh : r.en).tag(r.days) }
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            if pts.count < 2 {
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("Not enough days yet. Import your Health export for a longer history.", "天数还不够。导入「健康」App 的导出文件，就能看到更长的历史。"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button(t("Import Health export…", "导入健康导出文件…")) { model.importExport() }.controlSize(.small)
                }
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                let values = pts.map(\.value)
                let avg = values.reduce(0, +) / Double(values.count)
                Chart {
                    ForEach(pts) { p in
                        AreaMark(x: .value("Date", p.date), y: .value(def?.name(model.lang) ?? key, p.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", p.date), y: .value(def?.name(model.lang) ?? key, p.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(tint)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                    RuleMark(y: .value("Average", avg))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartYScale(domain: .automatic(includesZero: ["steps", "active_kcal", "exercise_min", "distance_km", "stand_h"].contains(key)))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: model.trendDays > 120 ? .dateTime.month(.abbreviated) : .dateTime.month(.defaultDigits).day())
                    }
                }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .frame(height: 130)
                HStack(spacing: 10) {
                    stat(t("Average", "平均"), avg)
                    stat(t("Low", "最低"), values.min()!)
                    stat(t("High", "最高"), values.max()!)
                    Spacer(minLength: 0)
                    if model.trendDays > 120 { Text(t("weekly means", "按周平均")).font(.system(size: 10)).foregroundStyle(.tertiary) }
                }
            }
        }
    }

    func stat(_ label: String, _ v: Double) -> some View {
        let key = model.trendMetric
        return HStack(spacing: 3) {
            Text(label).foregroundStyle(.secondary)
            Text("\(Metrics.format(key, v)) \(Metrics.byKey[key]?.unit(model.lang) ?? "")").monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium))
    }
}
