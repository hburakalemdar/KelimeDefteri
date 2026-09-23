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
        guard let words = try? context.fetch(descriptor), !words.isEmpty else { return }
        for word in words { migrate(word) }
        context.saveLogging()
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
