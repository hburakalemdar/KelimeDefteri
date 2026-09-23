import Foundation
import SwiftData

/// Leitner kutularından hafıza değerlerine (dayanıklılık, zorluk, son tekrar) tek seferlik geçiş.
///
/// Yalnızca çalışılmış ama henüz hafıza değeri olmayan kelimelere dokunur; geçişten sonra
/// dayanıklılık 0'dan büyük olduğu için ikinci çalıştırma hiçbir şeyi değiştirmez.
nonisolated enum MemoryMigration {
    struct Values: Equatable {
        let stability: Double
        let difficulty: Double
        let lastReviewedAt: Date?
    }

    static func needsMigration(stability: Double, reviewCount: Int) -> Bool {
        stability == 0 && reviewCount > 0
    }

    static func values(box: Int, dueDate: Date, reviewCount: Int, correctCount: Int) -> Values {
        let intervals = Leitner.intervalsInDays
        let stability = max(Double(intervals[min(max(box, 0), intervals.count - 1)]), 0.5)
        let lastReviewedAt = dueDate > .distantPast ? dueDate.addingTimeInterval(-stability * 86_400) : nil
        let correctRate = Double(correctCount) / Double(max(reviewCount, 1))
        let difficulty = min(max(5 + (0.5 - correctRate) * 6, 1), 10)
        return Values(stability: stability, difficulty: difficulty, lastReviewedAt: lastReviewedAt)
    }
}

extension MemoryMigration {
    /// Uygulama açılışında ve öne gelişinde çağrılır (iOS ve Mac); iCloud'dan sonradan gelen
    /// eski biçimli kayıtlar da böylece geçer. Değişiklik varsa kaydeder.
    @MainActor
    static func migrateIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Word>(predicate: #Predicate { $0.stability == 0 && $0.reviewCount > 0 })
        let words = (try? context.fetch(descriptor)) ?? []
        for word in words { migrate(word) }
        let filled = fillLearnedDates(context: context)
        if !words.isEmpty || filled > 0 { context.saveLogging() }
    }

    /// `learnedAt` alanından önce öğrenilmiş sayılan kelimelere ilk değer olarak son tekrar tarihini
    /// (yoksa eklenme tarihini) yazar; öğrenilmiş olmayan kelimede kalmış tarihi siler. Sonuç yalnızca
    /// kelimenin kendi alanlarından çıkar: iki cihaz aynı değeri yazar, ikinci çalıştırma bir şey değiştirmez.
    /// Kaydetmez; değişen kelime sayısını döner.
    @MainActor @discardableResult
    static func fillLearnedDates(context: ModelContext) -> Int {
        let learned = Memory.learnedStability
        let descriptor = FetchDescriptor<Word>(predicate: #Predicate {
            ($0.learnedAt == nil && $0.stability >= learned) || ($0.learnedAt != nil && $0.stability < learned)
        })
        guard let words = try? context.fetch(descriptor) else { return 0 }
        var changed = 0
        for word in words {
            if word.isLearned, word.learnedAt == nil {
                word.learnedAt = word.lastReviewedAt ?? word.createdAt
                changed += 1
            } else if !word.isLearned, word.learnedAt != nil {
                word.learnedAt = nil
                changed += 1
            }
        }
        return changed
    }

    /// Kelime eski biçimdeyse hafıza değerlerini kutusundan çıkarır. Cevap kaydedilmeden önce de
    /// çağrılır: geçmeden çalışılan kelime yeni sayılır ve kutu geçmişi bir daha geri gelmez.
    @MainActor
    static func migrate(_ word: Word) {
        guard needsMigration(stability: word.stability, reviewCount: word.reviewCount) else { return }
        let values = values(
            box: word.box, dueDate: word.dueDate,
            reviewCount: word.reviewCount, correctCount: word.correctCount
        )
        word.stability = values.stability
        word.difficulty = values.difficulty
        word.lastReviewedAt = values.lastReviewedAt
    }
}
