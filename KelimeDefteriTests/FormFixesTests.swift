import Foundation
import Testing
@testable import KelimeDefteri

/// Form ve Kelimelerim düzeltmeleri: süzgeçle birebir defter özeti, %90'da değişen halka rengi,
/// geç gelen çevirinin atılması.
struct FormFixesTests {
    private let now = Date.now

    private func studied(_ english: String, weak: Bool) -> Word {
        let word = Word(english: english, turkish: "anlam")
        word.reviewCount = 1
        word.stability = weak ? 1 : 30
        word.lastReviewedAt = now.addingTimeInterval(weak ? -5 * 86_400 : 0)
        // Zayıf = vadesi gelmiş (Günlük Tekrar'ın soracağı küme).
        word.dueDate = word.lastReviewedAt!.addingTimeInterval(word.stability * 86_400)
        return word
    }

    @Test func summaryMatchesFilters() {
        let words = [studied("a", weak: true), studied("b", weak: true)]
            + (0..<4).map { studied("s\($0)", weak: false) }
            + (0..<3).map { Word(english: "n\($0)", turkish: "yeni") }
        #expect(DeckSummary.text(for: words, now: now) == "9 kelime · 2 zayıf · 4 güçlü · 3 yeni")
        let filters: [(WordListView.Filter, Int)] = [(.all, 9), (.weak, 2), (.strong, 4), (.new, 3)]
        for (filter, count) in filters {
            #expect(words.count { filter.includes($0, now: now) } == count)
        }
    }

    @Test func summarySkipsZeroParts() {
        #expect(DeckSummary.text(for: [Word(english: "x", turkish: "y")], now: now) == "1 kelime · 1 yeni")
        #expect(DeckSummary.text(for: [studied("a", weak: false)], now: now) == "1 kelime · 1 güçlü")
    }

    @Test func ringTurnsGreenAtWeakThreshold() {
        #expect(MemoryStats.Level(Memory.targetRetention) == .strong)
        #expect(MemoryStats.Level(0.899) == .fading)
        #expect(MemoryStats.Level(0.6) == .fading)
        #expect(MemoryStats.Level(0.59) == .weak)
        #expect(MemoryStats.Bucket(0.899) == .below90)
        #expect(MemoryStats.Bucket(0.9) == .below95)
        // Dilim renkleri Level ile tutarlı: %90 altı dilimler yeşil değil, üstü yeşil.
        for bucket in MemoryStats.Bucket.allCases {
            guard let value = bucket.representative else { continue }
            let strong = MemoryStats.Level(value) == .strong
            #expect(strong == [.below95, .top].contains(bucket))
        }
        // Zayıf kelime ile yeşil halka birbirini dışlar.
        let weak = studied("w", weak: true)
        #expect(weak.isDue(at: now))
        #expect(MemoryStats.Level(weak.memory(at: now)!) != .strong)
    }

    @Test func lateTranslationIsDiscarded() {
        #expect(WordFormView.translationIsCurrent(requested: "stale", pending: "stale", english: "stale"))
        // A çevrilirken B seçildi.
        #expect(!WordFormView.translationIsCurrent(requested: "stale", pending: "stale", english: "idempotent"))
        // Kaydedildi ya da temizlendi: süren istek sıfırlandı.
        #expect(!WordFormView.translationIsCurrent(requested: "stale", pending: nil, english: ""))
        // B isteği sürerken geç gelen A sonucu atılır.
        #expect(!WordFormView.translationIsCurrent(requested: "stale", pending: "idempotent", english: "idempotent"))
    }
}
