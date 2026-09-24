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
        if !words.isEmpty { context.saveLogging() }
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

    /// Tek kelimenin taban göçü (Motor 2, SPEC §6): kutu göçünden sonra, `replay`den önce çağrılır.
    /// Yalnızca `baseAt == nil` iken çalışır; sonuç yalnızca kelimenin kendi alanlarından çıkar.
    ///
    /// - Hiç cevaplanmamış kelime (`reviewCount == 0`): boş taban (`baseAt = .distantPast`), bütün
    ///   cevap kayıtları oynatılır.
    /// - Eski veri: taban = o anki önbellek. Eski "vade son tekrardan önce = zayıf" işaretini gerçek
    ///   zayıflık gününe çevirir; zayıf kelimenin vadesi göç anı olur. `baseAt` göç anındaki son cevap
    ///   kaydının (ya da eski çıpanın, hangisi ileriyse) tarihidir, `now` değil.
    @MainActor
    static func migrateBaseIfNeeded(_ word: Word, now: Date = .now) {
        guard word.baseAt == nil else { return }
        migrate(word)
        guard word.reviewCount > 0 else {
            word.baseAt = .distantPast
            return
        }
        let wasLapsed = word.lastReviewedAt.map { word.dueDate > .distantPast && word.dueDate < $0 } ?? false
        word.baseStability = word.stability
        word.baseDifficulty = word.difficulty
        word.baseAnchorAt = word.lastReviewedAt
        word.baseLearnedAt = word.learnedAt
        word.baseLapsedAt = wasLapsed ? word.lastReviewedAt.map { DayBoundary.start(of: $0) } : nil
        word.baseDueDate = wasLapsed ? now : word.dueDate
        let lastLog = (word.logs ?? []).map(\.date).max()
        word.baseAt = [lastLog, word.lastReviewedAt].compactMap { $0 }.max() ?? word.createdAt
    }

    /// Kelimenin tabanı (`replay`in başlangıcı).
    @MainActor
    static func base(of word: Word) -> Memory.Base {
        Memory.Base(
            stability: word.baseStability, difficulty: word.baseDifficulty, dueDate: word.baseDueDate,
            lapsedAt: word.baseLapsedAt, anchorAt: word.baseAnchorAt, learnedAt: word.baseLearnedAt,
            at: word.baseAt
        )
    }
}
