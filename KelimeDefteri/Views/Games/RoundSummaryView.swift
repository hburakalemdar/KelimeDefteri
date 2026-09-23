import SwiftData
import SwiftUI

/// Bütün oyunlarda ortak tur özeti: kaç doğru, ne kadar sürdü, her kelimenin önceki hafızası ve
/// cevaptan sonra sıradaki tekrarın ne zaman olduğu. (Cevaptan hemen sonra hafıza hep ~%100 olduğu
/// için ikinci bir yüzde bir şey anlatmaz.)
struct RoundSummaryView: View {
    struct Entry: Identifiable {
        let word: Word
        /// Kelime ilk sorulduğundaki hafıza; yeni kelimede `nil`.
        let before: Double?
        /// İlk cevap doğru muydu.
        let correct: Bool

        var id: ObjectIdentifier { ObjectIdentifier(word) }
    }

    let entries: [Entry]
    let duration: TimeInterval
    var onAgain: () -> Void
    var onDone: () -> Void

    @Query private var words: [Word]

    /// Tur sürerken silinen kelimeler özette gösterilmez.
    private var visible: [Entry] {
        let alive = words.aliveIDs
        return entries.filter { !$0.word.isGone(from: alive) }
    }

    var body: some View {
        let entries = visible
        // List yerine kendi kartı: List'in son satırı ayrı çizildiği için son iki satır arasında
        // kart boyunca soluk bir çizgi kalıyordu.
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tur Bitti")
                        .font(.largeTitle.bold())
                    Text(RoundText.summary(
                        correct: entries.count(where: \.correct), total: entries.count, seconds: duration
                    ))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 24)

                if !entries.isEmpty {
                    Text("Hafıza")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(entries) { entry in
                            if entry.id != entries.first?.id {
                                Divider().padding(.leading, 48)
                            }
                            row(entry)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26, style: .continuous))
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Button(action: onAgain) {
                    Text("Bir Tur Daha")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                Button(action: onDone) {
                    Text("Bitti")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    /// Satırın üstünde kelime ve sağında hafıza; altında Türkçe anlam tam genişlikte (en fazla iki satır).
    /// Kelimeyle hafıza aynı satıra sığmazsa (uzun kelime, büyük yazı) hafıza kelimenin altına iner.
    private func row(_ entry: Entry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: entry.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(entry.correct ? .green : .red)
                .accessibilityLabel(entry.correct ? "Doğru" : "Yanlış")
            VStack(alignment: .leading, spacing: 2) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        english(entry).fixedSize()
                        Spacer(minLength: 8)
                        memory(entry)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        english(entry)
                        memory(entry)
                    }
                }
                Text(entry.word.turkish)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func english(_ entry: Entry) -> some View {
        Text(entry.word.english)
            .font(.system(.body, design: .serif, weight: .semibold))
    }

    /// "%45 → 12 gün sonra": önceki hafıza ve sıradaki tekrar.
    private func memory(_ entry: Entry) -> some View {
        HStack(spacing: 6) {
            MemoryRing(memory: entry.before, size: 14, text: .trailing)
                .foregroundStyle(.secondary)
            Text("→")
                .foregroundStyle(.secondary)
            let due = entry.word.dueDate
            Text(Leitner.dueDescription(for: due))
                .foregroundStyle(due > .now ? Color.primary : Color.red)
        }
        .font(.footnote.weight(.medium))
        .monospacedDigit()
        .fixedSize()
    }
}
