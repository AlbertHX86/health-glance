import SwiftUI
import WidgetKit

// Desktop widget: shows the cached summary.json; the app generates it and asks WidgetKit to reload.

struct Entry: TimelineEntry {
    let date: Date
    let summary: Summary?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), summary: .placeholder("en")) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), summary: Summary.load() ?? .placeholder("en")))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [Entry(date: Date(), summary: Summary.load())], policy: .after(next)))
    }
}

struct HealthWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: Entry

    var body: some View {
        let size: CardSize = family == .systemSmall ? .small : (family == .systemMedium ? .medium : .large)
        CardView(summary: entry.summary, size: size, lang: entry.summary?.lang ?? "en")
            .containerBackground(.background, for: .widget)
    }
}

struct HealthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HealthSummary", provider: Provider()) { HealthWidgetView(entry: $0) }
            .configurationDisplayName("HealthGlance")
            .description("A daily AI summary of your iPhone Health data.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct HealthWidgetBundle: WidgetBundle {
    var body: some Widget { HealthWidget() }
}
