import SwiftData
import SwiftUI
import WidgetKit

/// Kilit ekranı widget'ı: "Hafıza %78 · 6 kelime zayıfladı" ve günlük hedef. Dokununca Hızlı Tur açılır.
struct SummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Glance.summaryKind, provider: SummaryProvider()) { entry in
            SummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Hafıza ve Hedef")
        .description("Defterin hafızası, zayıflayan kelimeler ve günlük hedef halkası. Dokununca Hızlı Tur başlar.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

nonisolated struct SummaryEntry: TimelineEntry, Sendable {
    let date: Date
    /// Veritabanı açılamadıysa `nil`.
    let summary: GlanceSummary?
    /// Günlük hedef halkası; veritabanı açılamadıysa `nil`.
    let goal: DailyGoal.Progress?

    static let sample = SummaryEntry(
        date: .now,
        summary: GlanceSummary(average: 0.78, weak: 6, new: 2, total: 40),
        goal: DailyGoal.Progress(answered: 12, target: 30, streak: 4)
    )
}

nonisolated struct SummaryProvider: TimelineProvider {
    /// Hafıza zamanla azaldığı için özet önceden, yarım saat arayla hesaplanır;
    /// araya gece yarısı düşerse o an da eklenir (halka yeni günde sıfırlanır).
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
        guard let container = SharedStore.container else { return [SummaryEntry(date: now, summary: nil, goal: nil)] }
        let context = container.mainContext
        let words = (try? context.fetch(FetchDescriptor<Word>())) ?? []
        // Çalış ekranı gibi: silinmiş kelimelerin sahipsiz kayıtları sayılmaz.
        let answers = ((try? context.fetch(FetchDescriptor<ReviewLog>())) ?? [])
            .filter { $0.word != nil }
            .map(\.date)
        let target = DailyGoal.target()
        return DailyGoal.timelineDates(from: now, step: step, count: entryCount).map { date in
            SummaryEntry(
                date: date,
                summary: GlanceQuiz.summary(words, now: date),
                goal: DailyGoal.progress(dates: answers, target: target, now: date)
            )
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
            if let goal = entry.goal {
                Gauge(value: goal.fraction) {
                    Text("Hedef")
                } currentValueLabel: {
                    if goal.isComplete {
                        Image(systemName: "checkmark")
                    } else {
                        Text("\(goal.answered)")
                    }
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
                .accessibilityLabel(DailyGoal.text(goal))
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
                    .lineLimit(1)
                if let goal = entry.goal {
                    Label(DailyGoal.shortText(goal), systemImage: goal.isComplete ? "checkmark.circle.fill" : "target")
                        .lineLimit(1)
                        .accessibilityLabel([DailyGoal.text(goal), DailyGoal.streakText(goal.streak)].compactMap(\.self).joined(separator: ", "))
                }
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
