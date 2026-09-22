import SwiftUI

/// Kelimenin Leitner kutusunu küçük bir ilerleme halkası olarak gösterir.
struct BoxRing: View {
    let box: Int
    var size: CGFloat = 18

    var body: some View {
        let progress = Double(max(box, 0)) / Double(Leitner.maxBox)
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: size / 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.tint, style: StrokeStyle(lineWidth: size / 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("Kutu \(box) / \(Leitner.maxBox)")
    }
}

/// Defterin tek satırlık özeti: "48 kelime · 12 sırada · 9 öğrenildi".
enum DeckSummary {
    static func text(for words: [Word], now: Date = .now) -> String {
        let due = words.count { $0.isDue(at: now) }
        let learned = words.count(where: \.isLearned)
        return "\(words.count) kelime · \(due) sırada · \(learned) öğrenildi"
    }
}

#if os(iOS)
/// Ayarlar uygulamasındaki gibi renkli kare içinde beyaz simge.
struct SettingsIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color.gradient, in: .rect(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}
#endif

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
