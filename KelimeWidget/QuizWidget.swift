import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

/// Ana ekran widget'ı: bir İngilizce kelime ve 4 Türkçe seçenek. Seçeneğe dokununca cevap hafızaya
/// yazılır, doğru/yanlış kısa bir süre görünür, sonra sıradaki soru gelir. StandBy'da da aynı görünüm.
struct QuizWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Glance.quizKind, provider: QuizProvider()) { entry in
            QuizWidgetView(entry: entry)
        }
        .configurationDisplayName("Kelime Sorusu")
        .description("Uygulamayı açmadan bir kelime sor; 4 seçenekten doğrusuna dokun.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

nonisolated struct QuizEntry: TimelineEntry, Sendable {
    enum Content: Sendable {
        case question(GlanceQuestion)
        case feedback(GlanceFeedback)
        /// Defterde soru kurmaya yetecek kelime yok.
        case tooFewWords
        /// Veritabanı açılamadı.
        case unavailable
    }

    let date: Date
    let content: Content

    static let sample = QuizEntry(date: .now, content: .question(GlanceQuestion(
        id: "sample", english: "idempotent", wordKey: "idempotent",
        options: ["eş etkili", "bayat", "yeter sayı", "gecikme"], correctIndex: 0
    )))
}

/// Tamamlama kapanışını ana iş parçacığına taşımak için (WidgetKit onu `Sendable` işaretlemiyor).
nonisolated struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}

nonisolated struct QuizProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuizEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (QuizEntry) -> Void) {
        if context.isPreview {
            completion(.sample)
            return
        }
        let box = UncheckedSendable(value: completion)
        Task { @MainActor in box.value(QuizTimeline.entries(now: .now).first ?? .sample) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuizEntry>) -> Void) {
        let box = UncheckedSendable(value: completion)
        Task { @MainActor in
            let now = Date.now
            // Soru cevaplanınca ya da süresi dolunca değişir (`GlanceQuizStore.currentQuestion`); tazeleme en geç
            // o anda, yoksa saatte bir (silinen ya da başka yerde cevaplanan kelimeyi yakalamak için).
            let entries = QuizTimeline.entries(now: now)
            let next = GlanceQuizStore.nextRefresh(for: GlanceQuizStore.load(), now: now)
            box.value(Timeline(entries: entries, policy: .after(next)))
        }
    }
}

enum QuizTimeline {
    /// Az önce cevap verildiyse önce geri bildirim, süresi dolunca sıradaki soru.
    static func entries(now: Date) -> [QuizEntry] {
        guard let container = SharedStore.container else { return [QuizEntry(date: now, content: .unavailable)] }
        let words = (try? container.mainContext.fetch(FetchDescriptor<Word>())) ?? []
        let answered = GlanceQuiz.answeredKeys(in: container.mainContext, on: now)
        var generator = SystemRandomNumberGenerator()
        let question = GlanceQuizStore.currentQuestion(words: words, answered: answered, now: now, using: &generator)
        let next: QuizEntry.Content = question.map { .question($0) } ?? .tooFewWords
        if let feedback = GlanceQuizStore.activeFeedback(in: GlanceQuizStore.load(), now: now) {
            return [
                QuizEntry(date: now, content: .feedback(feedback)),
                QuizEntry(date: feedback.date.addingTimeInterval(GlanceQuizStore.feedbackDuration), content: next),
            ]
        }
        return [QuizEntry(date: now, content: next)]
    }
}

// MARK: - Görünüm

struct QuizWidgetView: View {
    let entry: QuizEntry
    @Environment(\.widgetFamily) private var family

    private var isSmall: Bool { family == .systemSmall }

    var body: some View {
        content
            .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.content {
        case .question(let question):
            layout(question, feedback: nil)
        case .feedback(let feedback):
            layout(feedback.question, feedback: feedback)
        case .tooFewWords:
            message("Soru için defterde en az \(GlanceQuiz.minimumWords) kelime olmalı.", systemImage: "book.closed")
        case .unavailable:
            message("Veritabanı açılamadı.", systemImage: "exclamationmark.triangle")
        }
    }

    private func layout(_ question: GlanceQuestion, feedback: GlanceFeedback?) -> some View {
        VStack(alignment: .leading, spacing: isSmall ? 6 : 8) {
            // Sonuç şıkların renginden okunur; başlığa ayrı simge konmaz (kelimeyi küçültüyordu).
            Text(question.english)
                .font(.system(isSmall ? .headline : .title3, design: .serif, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityValue(feedback.map { $0.isCorrect ? "Doğru" : "Yanlış" } ?? "")
            // Cevaptan sonra birden çok anlamlı kelimenin bütün anlamları (şıkta yalnızca biri soruldu).
            if feedback != nil, let meanings = question.otherMeaningsText {
                Text(meanings)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if isSmall {
                VStack(spacing: 4) {
                    ForEach(question.options.indices, id: \.self) { index in
                        option(question, index: index, feedback: feedback)
                    }
                }
            } else {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(Array(stride(from: 0, to: question.options.count, by: 2)), id: \.self) { start in
                        GridRow {
                            ForEach(start ..< min(start + 2, question.options.count), id: \.self) { index in
                                option(question, index: index, feedback: feedback)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Soru sorulurken düğme; geri bildirimde dokunulamayan, doğru ve seçilen şıkkı işaretli satır.
    @ViewBuilder
    private func option(_ question: GlanceQuestion, index: Int, feedback: GlanceFeedback?) -> some View {
        let label = OptionLabel(
            text: question.options[index],
            state: feedback.map { OptionLabel.State(index: index, feedback: $0) } ?? .plain,
            isSmall: isSmall
        )
        if feedback == nil {
            Button(intent: AnswerQuestionIntent(questionID: question.id, choice: index)) { label }
                .buttonStyle(.plain)
        } else {
            label
        }
    }

    private func message(_ text: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .widgetAccentable()
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Seçenek satırı: gri zemin; geri bildirimde doğru şık yeşil ✓, yanlış seçilen kırmızı ✕.
private struct OptionLabel: View {
    enum State {
        case plain, correct, wrongChoice, dimmed

        init(index: Int, feedback: GlanceFeedback) {
            if index == feedback.question.correctIndex {
                self = .correct
            } else if index == feedback.chosen {
                self = .wrongChoice
            } else {
                self = .dimmed
            }
        }
    }

    let text: String
    let state: State
    let isSmall: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(isSmall ? .caption.weight(.medium) : .subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            switch state {
            case .correct:
                Image(systemName: "checkmark").font(.caption.bold()).widgetAccentable()
            case .wrongChoice:
                Image(systemName: "xmark").font(.caption.bold())
            case .plain, .dimmed:
                EmptyView()
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, isSmall ? 8 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background, in: .rect(cornerRadius: isSmall ? 8 : 10, style: .continuous))
        .opacity(state == .dimmed ? 0.5 : 1)
    }

    private var foreground: Color {
        switch state {
        case .correct: .green
        case .wrongChoice: .red
        case .plain, .dimmed: .primary
        }
    }

    private var background: AnyShapeStyle {
        switch state {
        case .correct: AnyShapeStyle(Color.green.opacity(0.18))
        case .wrongChoice: AnyShapeStyle(Color.red.opacity(0.18))
        case .plain, .dimmed: AnyShapeStyle(.fill.tertiary)
        }
    }
}

#Preview(as: .systemSmall) {
    QuizWidget()
} timeline: {
    QuizEntry.sample
    QuizEntry(date: .now, content: .feedback(GlanceFeedback(
        question: GlanceQuestion(id: "s", english: "stale", wordKey: "stale",
                                 options: ["eş etkili", "bayat", "yeter sayı", "gecikme"], correctIndex: 1,
                                 meanings: ["bayat", "eskimiş"]),
        chosen: 2, date: .now
    )))
}

#Preview(as: .systemMedium) {
    QuizWidget()
} timeline: {
    QuizEntry.sample
}
