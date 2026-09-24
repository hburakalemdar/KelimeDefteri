import SwiftData
import SwiftUI

/// Bütün oyunlarda ortak tur özeti: kaç doğru, ne kadar sürdü, her kelimenin turdan önceki ve sonraki
/// tekrar zamanı ("önce → sonra"). Yüzde gösterilmez.
struct RoundSummaryView: View {
    struct Entry: Identifiable {
        let word: Word
        /// Turdaki ilk cevaptan hemen önceki vade; yeni kelimede `nil`.
        let dueBefore: Date?
        /// Turdaki ilk cevaptan hemen önce zayıf mıydı.
        let lapsedBefore: Bool
        /// İlk cevap doğru muydu.
        let correct: Bool

        init(word: Word, dueBefore: Date?, lapsedBefore: Bool, correct: Bool) {
            self.word = word
            self.dueBefore = dueBefore
            self.lapsedBefore = lapsedBefore
            self.correct = correct
        }

        /// Oyun turunun kaydından.
        init(_ entry: StudySession.RoundEntry) {
            self.init(
                word: entry.word, dueBefore: entry.dueBefore,
                lapsedBefore: entry.lapsedBefore, correct: entry.firstCorrect
            )
        }

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
                        #if os(iOS)
                        .font(.largeTitle.bold())
                        #else
                        .font(.title.bold())
                        #endif
                    Text(RoundText.summary(
                        correct: entries.count(where: \.correct), total: entries.count, seconds: duration
                    ))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
                .padding(.horizontal, 4)
                #if os(iOS)
                .padding(.bottom, 24)
                #else
                .padding(.bottom, 16)
                #endif

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
                    .background(GameStyle.cardFill, in: .rect(cornerRadius: GameStyle.cardRadius, style: .continuous))
                }
            }
            .gamePagePadding()
        }
        .background(GameStyle.pageBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Button(action: onAgain) {
                    Text("Bir Tur Daha")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                #if os(macOS)
                .keyboardShortcut(.defaultAction)
                .help("Bir tur daha (↩)")
                #endif
                Button(action: onDone) {
                    Text("Bitti")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                #if os(macOS)
                .keyboardShortcut(.cancelAction)
                .help("Oyunlara dön (Esc)")
                #endif
            }
            .controlSize(.large)
            .gameBarPadding()
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

    /// "3 gün gecikti → 8 gün sonra": turdan önceki ve sonraki tekrar zamanı; yeni kelimede "Yeni → Yarın".
    private func memory(_ entry: Entry) -> some View {
        HStack(spacing: 6) {
            Text(entry.dueBefore.map { Leitner.dueDescription(for: $0) } ?? "Yeni")
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
