import SwiftData
import SwiftUI

/// Bir kelimenin tüm bilgisi ve ilerlemesi; Kişiler'deki kart gibi. Düzenle formu açar.
struct WordDetailView: View {
    let word: Word
    @Query private var words: [Word]
    @State private var isEditing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Düzenle formundan silinince sayfa boş kalır ve geri döner; silinmiş kaydın alanları okunmaz.
        if isGone {
            Color.clear.onAppear { dismiss() }
        } else {
            content
        }
    }

    private var isGone: Bool {
        word.isDeleted || word.modelContext == nil || !words.aliveIDs.contains(word.persistentModelID)
    }

    private var content: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(word.english)
                            .font(.system(.largeTitle, design: .serif, weight: .semibold))
                            .textSelection(.enabled)
                        Spacer(minLength: 12)
                        Button("Telaffuzu dinle", systemImage: "speaker.wave.2.fill") {
                            Speaker.shared.speak(word.english)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                    }
                    Text(word.turkish)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.tint)
                        .textSelection(.enabled)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 8, trailing: 4))
            }

            if !word.example.isEmpty {
                Section("Kitaptaki Cümle") {
                    Text(AttributedString(quoting: word.example, highlighting: word.english))
                        .font(.system(.body, design: .serif).italic())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.vertical, 2)
                }
            }

            let related = word.related(in: words)
            if !related.isEmpty {
                Section("İlişkili") {
                    ForEach(related) { other in
                        NavigationLink(value: other) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(other.english)
                                    .font(.system(.body, design: .serif, weight: .semibold))
                                Text(other.turkish)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }

            memorySection
            historySection
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Düzenle") { isEditing = true }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                WordFormView(mode: .edit(word))
            }
        }
    }
}

// MARK: - Hafıza ve geçmiş

extension WordDetailView {
    private var stats: WordStats {
        WordStats(entries: (word.logs ?? []).map {
            WordStats.Entry(date: $0.date, mode: $0.mode, correct: $0.correct, responseTime: $0.responseTime)
        })
    }

    private var memorySection: some View {
        Section("Hafıza") {
            let memory = word.memory()
            HStack(spacing: 16) {
                MemoryRing(memory: memory, size: 56, text: .center)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(memoryTitle(memory))
                        if word.isLearned { LearnedBadge() }
                    }
                    .font(.headline)
                    Text(memoryDetail(memory))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)

            if !word.isNew {
                LabeledContent("Sıradaki tekrar", value: Leitner.dueDescription(for: word.dueDate))
            }
            LabeledContent("Görülme", value: "\(word.answerCount)")
            if word.answerCount > 0 {
                LabeledContent(
                    "Doğru bilme",
                    value: (Double(word.correctAnswerCount) / Double(word.answerCount))
                        .formatted(.percent.precision(.fractionLength(0)))
                )
            }
            if let last = word.lastReviewedAt {
                LabeledContent("Son görülme", value: last.formatted(.relative(presentation: .named)))
            }
            if let average = stats.averageResponseTime {
                LabeledContent(
                    "Ortalama cevap süresi",
                    value: "\(average.formatted(.number.precision(.fractionLength(1)))) sn"
                )
            }
            LabeledContent("Eklendi", value: word.createdAt.formatted(date: .long, time: .omitted))
        }
    }

    /// Halka yüzdeyi gösterdiği için yazı kelimenin durumunu anlatır.
    private func memoryTitle(_ memory: Double?) -> String {
        guard let memory else { return "Yeni" }
        if memory < Memory.targetRetention { return "Zayıfladı" }
        return word.isLearned ? "Öğrenildi" : "Güçlü"
    }

    private func memoryDetail(_ memory: Double?) -> String {
        guard let memory else { return "Henüz çalışılmadı; ilk turda sorulacak." }
        if memory < Memory.targetRetention { return "Hatırlama ihtimali %90'ın altına indi; tekrar zamanı." }
        return word.isLearned ? "Uzun aralıklarla sorulur." : "Zayıflayınca yeniden sorulur."
    }

    @ViewBuilder
    private var historySection: some View {
        let stats = stats
        if !stats.recent.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    FlowLayout(spacing: 5) {
                        ForEach(Array(stats.recent.enumerated()), id: \.offset) { _, entry in
                            Circle()
                                .fill(entry.correct ? Color.green : Color.red)
                                .frame(width: 9, height: 9)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Son \(stats.recent.count) gösterimde \(stats.recent.count { $0.correct }) doğru")
                    Text(stats.countsText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Geçmiş")
            } footer: {
                Text("Soldan sağa eskiden yeniye son \(stats.recent.count) gösterim; yeşil doğru, kırmızı yanlış.")
            }
        }
    }
}

#if DEBUG
#Preview {
    let container = PreviewData.container
    let word = try! container.mainContext.fetch(FetchDescriptor<Word>()).first!
    return NavigationStack {
        WordDetailView(word: word)
    }
    .modelContainer(container)
}
#endif
