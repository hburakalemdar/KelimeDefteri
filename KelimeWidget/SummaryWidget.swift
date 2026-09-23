import SwiftData
import SwiftUI
import WidgetKit

/// Kilit ekranı widget'ı: "Hafıza %78 · 6 kelime zayıfladı". Dokununca Hızlı Tur açılır.
struct SummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Glance.summaryKind, provider: SummaryProvider()) { entry in
            SummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Hafıza")
        .description("Defterin ortalama hafızası ve zayıflayan kelimeler. Dokununca Hızlı Tur başlar.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

nonisolated struct SummaryEntry: TimelineEntry, Sendable {
    let date: Date
    /// Veritabanı açılamadıysa `nil`.
    let summary: GlanceSummary?

    static let sample = SummaryEntry(date: .now, summary: GlanceSummary(average: 0.78, weak: 6, new: 2, total: 40))
}

nonisolated struct SummaryProvider: TimelineProvider {
    /// Hafıza zamanla azaldığı için özet önceden, yarım saat arayla hesaplanır.
    static let step: TimeInterval = 30 * 60
    static let entryCount = 12

    func placeholder(in context: Context) -> SummaryEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
            return
        }
        let box = UncheckedSendable(value: completion)
        Task { @MainActor in box.value(Self.entries(now: .now).first ?? .sample) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        let box = UncheckedSendable(value: completion)
        Task { @MainActor in box.value(Timeline(entries: Self.entries(now: .now), policy: .atEnd)) }
    }

    @MainActor
    static func entries(now: Date) -> [SummaryEntry] {
        guard let container = SharedStore.container else { return [SummaryEntry(date: now, summary: nil)] }
        let words = (try? container.mainContext.fetch(FetchDescriptor<Word>())) ?? []
        return (0..<entryCount).map { step in
            let date = now.addingTimeInterval(Double(step) * Self.step)
            return SummaryEntry(date: date, summary: GlanceQuiz.summary(words, now: date))
        }
    }
}

struct SummaryWidgetView: View {
    let entry: SummaryEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetURL(Glance.quickRoundURL)
            .containerBackground(for: .widget) {
                if family == .accessoryCircular { AccessoryWidgetBackground() }
            }
    }

    @ViewBuilder
    private var content: some View {
        let summary = entry.summary ?? GlanceSummary(average: nil, weak: 0, new: 0, total: 0)
        switch family {
        case .accessoryCircular:
            if let average = summary.average {
                Gauge(value: average) {
                    Text("Hafıza")
                } currentValueLabel: {
                    Text("\(MemoryStats.percent(average))")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
            } else {
                Image(systemName: "book.closed")
                    .font(.title2)
                    .widgetAccentable()
            }
        case .accessoryInline:
            ViewThatFits {
                Text(summary.line)
                Text(summary.total == 0 ? summary.detailText : summary.memoryText)
            }
        default:
            VStack(alignment: .leading, spacing: 1) {
                Label(summary.total == 0 ? "Kelime Defteri" : summary.memoryText, systemImage: "bolt.fill")
                    .font(.headline)
                    .widgetAccentable()
                Text(summary.detailText)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview(as: .accessoryRectangular) {
    SummaryWidget()
} timeline: {
    SummaryEntry.sample
}

#Preview(as: .accessoryCircular) {
    SummaryWidget()
} timeline: {
    SummaryEntry.sample
}
