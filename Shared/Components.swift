import SwiftUI

/// Kelimenin Leitner kutusunu nokta dizisi olarak gösterir.
struct BoxDots: View {
    let box: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...Leitner.maxBox, id: \.self) { index in
                Circle()
                    .fill(index <= box ? Color.accentColor : Color.emptyDot)
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

private extension Color {
    #if os(macOS)
    static let emptyDot = Color(nsColor: .quaternaryLabelColor)
    #else
    static let emptyDot = Color(.systemFill)
    #endif
}

extension AttributedString {
    /// Kitaptaki cümleyi tırnak içinde, geçen kelimeyi kalın ve belirgin gösterir.
    init(quoting sentence: String, highlighting word: String) {
        self.init("“\(sentence)”")
        if let range = range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) {
            self[range].inlinePresentationIntent = .stronglyEmphasized
            self[range].foregroundColor = .primary
        }
    }
}
