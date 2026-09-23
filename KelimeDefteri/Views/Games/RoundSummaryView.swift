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

    var body: some View {
        List {
            Section {
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
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 4))
            }

            if !entries.isEmpty {
                Section("Hafıza") {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                }
            }
        }
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

    private func row(_ entry: Entry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(entry.correct ? .green : .red)
                .accessibilityLabel(entry.correct ? "Doğru" : "Yanlış")
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.word.english)
                    .font(.system(.body, design: .serif, weight: .semibold))
                Text(entry.word.turkish)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
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
        .accessibilityElement(children: .combine)
    }
}
