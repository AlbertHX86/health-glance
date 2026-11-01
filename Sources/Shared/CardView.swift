import SwiftUI

// The card drawn by the widget and by the app's pinned desktop card, styled after Apple's own widgets:
// system widget sizes, 16 pt margins, continuous corners, Health-app category colours and SF Pro Rounded numbers.

enum CardSize {
    case small, medium, large

    /// macOS widget sizes in points (margins included)
    var frame: CGSize {
        switch self {
        case .small: return CGSize(width: 170, height: 170)
        case .medium: return CGSize(width: 364, height: 170)
        case .large: return CGSize(width: 364, height: 382)
        }
    }
}

enum WidgetStyle {
    static let cornerRadius: CGFloat = 22
    static let margin: CGFloat = 16
}

/// SF Symbol and Health-app colour per metric.
enum MetricStyle {
    static func icon(_ key: String) -> String {
        switch key {
        case "steps", "distance_km": return "figure.walk"
        case "active_kcal": return "flame.fill"
        case "exercise_min": return "figure.run"
        case "stand_h": return "figure.stand"
        case "sleep_h": return "bed.double.fill"
        case "resting_hr", "hr": return "heart.fill"
        case "hrv": return "waveform.path.ecg"
        case "spo2": return "lungs.fill"
        case "weight": return "scalemass.fill"
        default: return "circle.fill"
        }
    }

    /// Names that fit the narrow tiles of the small and medium widgets.
    static func shortName(_ key: String, _ lang: String) -> String {
        let en = ["distance_km": "Distance", "active_kcal": "Active", "resting_hr": "Resting", "hr": "Heart", "stand_h": "Stand"]
        let zh = ["distance_km": "距离", "active_kcal": "活动", "hrv": "HRV", "hr": "心率"]
        return (lang == "zh" ? zh[key] : en[key]) ?? Metrics.byKey[key]!.name(lang)
    }

    static func tint(_ key: String) -> Color {
        switch key {
        case "steps", "distance_km", "active_kcal": return .orange
        case "exercise_min": return .green
        case "stand_h": return .cyan
        case "sleep_h": return .teal
        case "resting_hr", "hr", "hrv": return .pink
        case "spo2": return .blue
        case "weight": return .purple
        default: return .secondary
        }
    }
}

struct MetricTile: View {
    let key: String
    let value: Double
    let avg: Double?
    let lang: String
    var big = false

    var body: some View {
        let def = Metrics.byKey[key]!
        VStack(alignment: .leading, spacing: 1) {
            Label {
                Text(big ? def.name(lang) : MetricStyle.shortName(key, lang)).lineLimit(1)
            } icon: {
                Image(systemName: MetricStyle.icon(key))
            }
            .labelStyle(TightLabel())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MetricStyle.tint(key))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(Metrics.format(key, value))
                    .font(.system(size: big ? 22 : 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                if big || key != "steps" {  // "6,120" needs no unit when space is short
                    Text(def.unit(lang))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            if let a = avg, a > 0 {
                let pct = (value - a) / a * 100
                Text(abs(pct) < 3 ? (lang == "zh" ? "与均值持平" : "≈ 7-day avg") : String(format: "%@ %.0f%%", pct > 0 ? "▲" : "▼", abs(pct)))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon; configuration.title }
    }
}

struct CardView: View {
    let summary: Summary?
    let size: CardSize
    var lang: String = "en"
    @State var leaving: Set<String> = []  // ticked a moment ago: shown ticked, then faded out
    /// Set by the app (menu and desktop card): every tip shows and ticks on click. The widget leaves it nil and shows
    /// the first three with their ticks.
    var onToggle: ((String) -> Void)? = nil

    static let order = ["sleep_h", "steps", "resting_hr", "active_kcal", "exercise_min", "hrv", "stand_h", "distance_km", "hr", "spo2", "weight"]

    func t(_ en: String, _ zh: String) -> String { lang == "zh" ? zh : en }

    var body: some View {
        if let s = summary { content(s) } else { empty }
    }

    var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            header(nil)
            Text(t("No data yet", "还没有数据")).font(.system(size: 15, weight: .semibold))
            Text(t("Add your MiniMax API key in the menu bar, then set up the iPhone shortcut.",
                   "在菜单栏填入 MiniMax API Key，再在 iPhone 上设置快捷指令。"))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Pink heart + "Today" (or the data's date when it is not today's), like the title row of Apple's widgets.
    func header(_ s: Summary?) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
            Text(s.map { s in (s.person.map { "\($0) · " } ?? "") + dayLabel(s.date) } ?? "HealthGlance").lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.pink)
    }

    func tiles(_ s: Summary, _ n: Int) -> [String] {
        Array(Self.order.filter { s.metrics[$0] != nil }.prefix(n))
    }

    func tile(_ s: Summary, _ k: String, big: Bool = false) -> MetricTile {
        MetricTile(key: k, value: s.metrics[k]!, avg: s.weekAvg[k], lang: lang, big: big)
    }

    @ViewBuilder func content(_ s: Summary) -> some View {
        switch size {
        case .small:
            VStack(alignment: .leading, spacing: 4) {
                header(s)
                Text(s.headline).font(.system(size: 15, weight: .semibold)).lineLimit(3).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 8) { ForEach(tiles(s, 2), id: \.self) { tile(s, $0) } }
            }
        case .medium:
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    header(s)
                    Text(s.headline).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                    Text(s.summary).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(4)
                    Spacer(minLength: 0)
                }
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    let keys = tiles(s, 4)
                    ForEach(Array(stride(from: 0, to: keys.count, by: 2)), id: \.self) { i in
                        GridRow {
                            tile(s, keys[i])
                            if i + 1 < keys.count { tile(s, keys[i + 1]) } else { Color.clear.frame(height: 1) }
                        }
                    }
                }
                .frame(width: 172)
            }
        case .large:
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    header(s)
                    Text(s.headline).font(.system(size: 19, weight: .bold)).lineLimit(2)
                    Text(s.summary).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                    let keys = tiles(s, 6)
                    ForEach(Array(stride(from: 0, to: keys.count, by: 3)), id: \.self) { i in
                        GridRow {
                            ForEach(i..<min(i + 3, keys.count), id: \.self) { tile(s, keys[$0], big: true) }
                        }
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if !s.tips.isEmpty {
                    let done = Set(s.done ?? [])
                    let open = s.tips.filter { !done.contains($0) }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(t("Suggestions", "建议")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            if !done.isEmpty {
                                Text(t("\(done.count) done", "已完成 \(done.count) 条")).font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                        }
                        if open.isEmpty {
                            Label(t("All done for today", "今天的建议都完成了"), systemImage: "checkmark.seal.fill")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.green)
                        }
                        ForEach(onToggle == nil ? Array(open.prefix(3)) : open, id: \.self) { tip in
                            if let onToggle {
                                Button { tick(tip, onToggle) } label: { tipRow(tip).contentShape(Rectangle()) }
                                    .buttonStyle(.plain)
                                    .transition(.opacity)
                            } else {
                                tipRow(tip)
                            }
                        }
                        if onToggle == nil, open.count > 3 {
                            Text(t("+\(open.count - 3) more in the menu bar", "菜单栏里还有 \(open.count - 3) 条"))
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
                Text(t("Updated ", "更新于 ") + s.generatedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: lang == "zh" ? "zh_CN" : "en_US"))))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    /// Show the tick for a moment, then fade the tip out as it is marked done.
    func tick(_ tip: String, _ onToggle: @escaping (String) -> Void) {
        guard !leaving.contains(tip) else { return }
        withAnimation(.easeOut(duration: 0.15)) { _ = leaving.insert(tip) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.4)) { onToggle(tip) }
            leaving.remove(tip)
        }
    }

    func tipRow(_ tip: String) -> some View {
        let done = leaving.contains(tip)
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            Text(tip).lineLimit(onToggle == nil ? 1 : 2).strikethrough(done).foregroundStyle(done ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: onToggle != nil)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .medium))
    }

    func dayLabel(_ d: String) -> String {
        guard let date = HealthParser.dateFmt.date(from: d) else { return d }
        if Calendar.current.isDateInToday(date) { return t("Today", "今天") }
        if Calendar.current.isDateInYesterday(date) { return t("Yesterday", "昨天") }
        let f = DateFormatter()
        f.locale = Locale(identifier: lang == "zh" ? "zh_CN" : "en_US")
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f.string(from: date)
    }
}

/// A card with the widget's own shape and background, for places the system does not draw them
/// (the pinned desktop card and the menu-bar preview).
struct WidgetFrame<Content: View>: View {
    let size: CardSize
    var grows = false  // taller than the widget when the content needs it (all tips in the app)
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(WidgetStyle.margin)
            .frame(width: size.frame.width)
            .frame(minHeight: size.frame.height, maxHeight: grows ? nil : size.frame.height)
            .fixedSize(horizontal: false, vertical: grows)
            .background(.background, in: RoundedRectangle(cornerRadius: WidgetStyle.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: WidgetStyle.cornerRadius, style: .continuous).strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
    }
}
