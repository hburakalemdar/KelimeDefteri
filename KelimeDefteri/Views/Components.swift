import SwiftUI

/// Kelimenin Leitner kutusunu nokta dizisi olarak gösterir.
struct BoxDots: View {
    let box: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...Leitner.maxBox, id: \.self) { index in
                Circle()
                    .fill(index <= box ? Color.accentColor : Color(.systemFill))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Kutu \(box) / \(Leitner.maxBox)")
    }
}

/// Toplam, sıradaki ve öğrenilen kelime sayıları.
struct StatsLine: View {
    let words: [Word]

    var body: some View {
        let due = words.filter { $0.isDue() }.count
        let learned = words.filter(\.isLearned).count
        HStack(spacing: 14) {
            stat(words.count, "kelime")
            stat(due, "sırada")
            stat(learned, "öğrenildi")
        }
        .font(.footnote.monospaced())
        .foregroundStyle(.secondary)
    }

    private func stat(_ value: Int, _ label: String) -> some View {
        (Text("\(value) ").foregroundStyle(.primary).fontWeight(.semibold) + Text(label))
            .monospacedDigit()
    }
}
