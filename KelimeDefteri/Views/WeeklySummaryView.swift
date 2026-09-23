import SwiftData
import SwiftUI

/// Çalış ekranındaki hedef kartından açılır: son 7 günün halkaları, sayılar ve en çok zorlanılan kelimeler.
struct WeeklySummaryView: View {
    @Query private var logs: [ReviewLog]
    @AppStorage(DailyGoal.key, store: DailyGoal.defaults) private var target = DailyGoal.defaultTarget

    var body: some View {
        let now = Date.now
        let answered = logs.filter { $0.word != nil }
        let summary = WeeklySummary(
            answers: answered.map { .init(word: $0.word!.persistentModelID, date: $0.date, correct: $0.correct) },
            now: now
        )
        let streak = DailyGoal.streak(dates: answered.map(\.date), target: target, now: now)
        let wordsByID = Dictionary(answered.map { ($0.word!.persistentModelID, $0.word!) }, uniquingKeysWith: { first, _ in first })

        List {
            Section {
                weekRings(summary)
            } footer: {
                Text("Her halka günlük \(target) cevaplık hedefe göre dolar.")
            }

            Section {
                LabeledContent("Cevap", value: "\(summary.answerCount)")
                if let accuracy = summary.accuracy {
                    LabeledContent("Doğru bilme", value: accuracy.formatted(.percent.precision(.fractionLength(0))))
                }
                LabeledContent("Güçlenen kelime", value: "\(summary.strengthenedCount)")
                LabeledContent("Seri", value: streak > 0 ? "\(streak) gün" : "Yok")
            } header: {
                Text("Son 7 Gün")
            } footer: {
                Text("Güçlenen kelime: bu hafta doğru bildiğin ve son cevabı doğru olan kelime. Seri, halkayı üst üste kapattığın gün sayısı.")
            }

            if !summary.hardest.isEmpty {
                Section("En Çok Zorlandıkların") {
                    ForEach(summary.hardest, id: \.word) { hard in
                        if let word = wordsByID[hard.word] {
                            NavigationLink(value: word) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(word.english)
                                            .font(.system(.body, design: .serif, weight: .semibold))
                                        Text(word.turkish)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 8)
                                    Text("\(hard.wrong) / \(hard.total) yanlış")
                                        .font(.footnote)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Bu Hafta")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Word.self) { word in
            WordDetailView(word: word)
        }
    }

    /// Fitness'taki gibi yedi küçük halka, altında günün kısa adı; bugün kalın.
    private func weekRings(_ summary: WeeklySummary<PersistentIdentifier>) -> some View {
        HStack(spacing: 0) {
            ForEach(summary.days, id: \.day) { day in
                let isToday = Calendar.current.isDateInToday(day.day)
                VStack(spacing: 6) {
                    GoalRing(progress: .init(answered: day.count, target: target, streak: 0), size: 34, showsCount: false)
                    Text(day.day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption2.weight(isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.day.formatted(.dateTime.weekday(.wide))): \(day.count) cevap")
            }
        }
        .padding(.vertical, 6)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        WeeklySummaryView()
    }
    .modelContainer(PreviewData.container)
}
#endif
