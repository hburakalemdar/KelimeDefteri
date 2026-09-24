import SwiftUI

/// Kelimenin hafıza gücünü (hatırlama ihtimalini) halka olarak gösterir.
///
/// Halka hafıza oranında dolar; %90 ve üstü yeşil, %60–90 turuncu (zayıf), altı kırmızı.
/// Yeni kelimede kesik çizgili gri boş halka. İstenirse yanında ya da ortasında "%62" / "Yeni" yazar.
struct MemoryRing: View {
    enum TextPlacement {
        case none, trailing, center
    }

    /// 0…1 arası hatırlama ihtimali; yeni kelimede `nil`.
    let memory: Double?
    var size: CGFloat = 18
    var text: TextPlacement = .none
    /// Zayıf kelime (`Word.isLapsed`): halka hafıza değerine bakmadan turuncu.
    var isLapsed: Bool = false

    var body: some View {
        switch text {
        case .none:
            ring
        case .trailing:
            HStack(spacing: size / 3) {
                ring
                Text(MemoryStats.text(memory))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        case .center:
            ring
                .overlay {
                    Text(MemoryStats.text(memory))
                        .font(.system(size: size * 0.28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                        .padding(size / 6)
                }
        }
    }

    private var lineWidth: CGFloat { max(2, size / 7) }

    private var color: Color {
        if isLapsed, memory != nil { return .orange }
        return memory.map { MemoryStats.Level($0).color } ?? .secondary
    }

    private var ring: some View {
        ZStack {
            if let memory {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(memory, 0.02))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Circle()
                    .stroke(.tertiary, style: StrokeStyle(lineWidth: lineWidth, dash: [lineWidth * 0.9, lineWidth * 1.1]))
            }
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        memory == nil ? "Yeni kelime" : "Hafıza \(MemoryStats.text(memory))"
    }
}

/// Yanlış bilinip tekrar edilecek kelimenin (`Word.isLapsed`) etiketi: "Tekrar edilecek · Yarın".
/// Yalnızca kelime listesinde ve ayrıntı sayfasında; tur özetinde etiket yok, yalnızca turuncu vurgu.
struct LapsedLabel: View {
    let word: Word

    var body: some View {
        Label(Self.text(for: word), systemImage: "arrow.counterclockwise")
            .foregroundStyle(.orange)
    }

    static let title = "Tekrar edilecek"

    /// Vadesi henüz gelmemiş olsa da ne zaman sorulacağı yazılır.
    static func text(for word: Word, now: Date = .now) -> String {
        "\(title) · \(Leitner.dueDescription(for: word.dueDate, now: now))"
    }
}

extension MemoryStats.Level {
    var color: Color {
        switch self {
        case .strong: .green
        case .fading: .orange
        case .weak: .red
        }
    }
}

extension Word {
    /// Sıralama için: yeni kelime en başta (−1), sonra zayıftan güçlüye.
    var memorySortValue: Double { memory() ?? -1 }
}

/// Defterin tek satırlık özeti, Kelimelerim süzgeçleriyle birebir:
/// "9 kelime · 2 zayıf · 1 tekrar edilecek · 3 güçlü · 3 yeni".
enum DeckSummary {
    enum Group { case weak, repeating, strong, new }

    /// Gruplar birbirini dışlar: yeni kelimenin hafızası henüz yok, zayıf da güçlü de sayılmaz.
    /// "Zayıf" burada Günlük Tekrar'ın soracağı küme: vadesi gelmiş çalışılmış kelimeler (`isDue`).
    /// Yanlış bilinip vadesi henüz gelmemiş kelime (`isLapsed`) "tekrar edilecek"tir; güçlü sayılmaz.
    static func group(of word: Word, now: Date = .now) -> Group {
        if word.isNew { return .new }
        if word.isDue(at: now) { return .weak }
        return word.isLapsed ? .repeating : .strong
    }

    /// Vadesi gelmemiş, yanlış bilinip tekrar edilecek kelime sayısı.
    static func repeatingCount(_ words: [Word], now: Date = .now) -> Int {
        words.count { group(of: $0, now: now) == .repeating }
    }

    /// Sıfır olan parça yazılmaz.
    static func text(for words: [Word], now: Date = .now) -> String {
        let groups = words.map { group(of: $0, now: now) }
        let parts = [(Group.weak, "zayıf"), (.repeating, "tekrar edilecek"), (.strong, "güçlü"), (.new, "yeni")]
            .compactMap { group, name in
                let count = groups.count { $0 == group }
                return count > 0 ? "\(count) \(name)" : nil
            }
        return (["\(words.count) kelime"] + parts).joined(separator: " · ")
    }

    /// Günlük Tekrar'da bugün iş kalmadığında kartın alt satırı. "Bütün kelimeler güçlü" yalnızca gerçekten
    /// öyleyse; yanlış bilinip tekrar edilecek ya da bugünün sınırı yüzünden bekleyen yeni kelime varsa
    /// "Bugünlük tekrar bitti · 6 kelime tekrar edilecek · sıradaki tekrar yarın".
    static func allDoneText(for words: [Word], now: Date = .now) -> String {
        let repeating = repeatingCount(words, now: now)
        let newWaiting = StudySession.recentWaitingCount(words, now: now)
        var parts = [repeating > 0 || newWaiting > 0 ? "Bugünlük tekrar bitti" : "Bütün kelimeler güçlü"]
        if repeating > 0 { parts.append("\(repeating) kelime tekrar edilecek") }
        if let next = words.filter({ !$0.isNew }).map(\.dueDate).filter({ $0 > now }).min() {
            parts.append("sıradaki tekrar " + Leitner.dueDescription(for: next, now: now).lowercased(with: Locale(identifier: "tr_TR")))
        }
        return parts.joined(separator: " · ")
    }
}

/// Ayarlar uygulamasındaki gibi renkli kare içinde beyaz simge.
struct SettingsIcon: View {
    let systemName: String
    let color: Color
    /// Ayarlar satırında 30, oyun kartında 44.
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size / 2, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size * 7 / 30, style: .continuous))
            .accessibilityHidden(true)
    }
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
