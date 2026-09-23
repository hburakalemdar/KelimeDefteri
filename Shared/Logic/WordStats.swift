import Foundation

/// Bir kelimenin cevap kayıtlarından çıkan istatistik: geçmiş noktaları, oyunlara göre sayılar,
/// ortalama cevap süresi. Ayrıntı sayfası kullanır.
nonisolated struct WordStats: Equatable {
    struct Entry: Equatable {
        let date: Date
        let mode: String
        let correct: Bool
        let responseTime: Double
    }

    /// Geçmişte gösterilecek en fazla nokta sayısı.
    static let historyLimit = 30

    /// Son gösterimler, eskiden yeniye (en fazla `historyLimit`).
    let recent: [Entry]
    /// Oyun adına göre sayılar, çoktan aza: [("Günlük Tekrar", 8), ("Eşleştir", 3)].
    let countsByMode: [(title: String, count: Int)]
    /// Süresi ölçülen cevapların ortalaması (saniye); hiç yoksa `nil`.
    let averageResponseTime: Double?

    init(entries: [Entry]) {
        let sorted = entries.sorted { $0.date < $1.date }
        recent = Array(sorted.suffix(Self.historyLimit))

        var counts: [String: Int] = [:]
        for entry in sorted { counts[entry.mode, default: 0] += 1 }
        countsByMode = counts
            .map { (title: GameMode(rawValue: $0.key)?.title ?? $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.title < $1.title }

        let timed = sorted.map(\.responseTime).filter { $0 > 0 }
        averageResponseTime = timed.isEmpty ? nil : timed.reduce(0, +) / Double(timed.count)
    }

    /// "Günlük Tekrar 8 · Eşleştir 3"
    var countsText: String {
        countsByMode.map { "\($0.title) \($0.count)" }.joined(separator: " · ")
    }

    static func == (lhs: WordStats, rhs: WordStats) -> Bool {
        lhs.recent == rhs.recent && lhs.countsText == rhs.countsText
            && lhs.averageResponseTime == rhs.averageResponseTime
    }
}
