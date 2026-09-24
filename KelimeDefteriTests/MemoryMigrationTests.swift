import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

struct MemoryMigrationTests {
    private let due = Date(timeIntervalSince1970: 1_790_000_000)

    /// Bellek içi depo iOS 27 simülatöründe kaydederken ara ara çöktüğü için geçici dosya kullanılır.
    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    @Test func valuesComeFromBoxAndAccuracy() {
        let values = MemoryMigration.values(box: 3, dueDate: due, reviewCount: 4, correctCount: 3)
        #expect(values.stability == 7)
        #expect(values.lastReviewedAt == due.addingTimeInterval(-7 * 86_400))
        // 5 + (0.5 − 0.75) × 6 = 3.5
        #expect(abs(values.difficulty - 3.5) < 1e-9)
    }

    @Test func boxZeroGetsHalfDayAndDifficultyIsClamped() {
        let values = MemoryMigration.values(box: 0, dueDate: .distantPast, reviewCount: 5, correctCount: 0)
        #expect(values.stability == 0.5)
        #expect(values.lastReviewedAt == nil)
        #expect(values.difficulty == 8)
        let perfect = MemoryMigration.values(box: 9, dueDate: due, reviewCount: 2, correctCount: 2)
        #expect(perfect.stability == 35)
        #expect(perfect.difficulty == 2)
    }

    @Test func migratesOnlyStudiedWordsAndOnlyOnce() throws {
        let context = try makeContext()
        let studied = Word(english: "stale", turkish: "eskimiş")
        studied.box = 2
        studied.dueDate = due
        studied.reviewCount = 4
        studied.correctCount = 2
        let fresh = Word(english: "quorum", turkish: "yeter sayı")
        context.insert(studied)
        context.insert(fresh)
        try context.save()

        MemoryMigration.migrateIfNeeded(context: context)
        #expect(studied.stability == 3)
        #expect(studied.difficulty == 5)
        #expect(studied.lastReviewedAt == due.addingTimeInterval(-3 * 86_400))
        #expect(fresh.stability == 0)
        #expect(fresh.lastReviewedAt == nil)

        // Sonradan değişen değer ikinci geçişte ezilmemeli.
        studied.stability = 12
        studied.difficulty = 4
        MemoryMigration.migrateIfNeeded(context: context)
        #expect(studied.stability == 12)
        #expect(studied.difficulty == 4)
        #expect(fresh.stability == 0)
    }

    @Test func deletingWordDeletesItsLogs() throws {
        let context = try makeContext()
        let word = Word(english: "idempotent", turkish: "tekrarlanabilir")
        context.insert(word)
        let log = ReviewLog(mode: "daily", correct: true, grade: 3, responseTime: 4)
        context.insert(log)
        log.word = word
        try context.save()
        #expect(word.logs?.count == 1)

        context.delete(word)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<ReviewLog>()) == 0)
    }

    // MARK: - Taban göçü (SPEC-MOTOR2 §6)

    private func log(_ word: Word, at date: Date, correct: Bool, mode: GameMode = .dailyReview, in context: ModelContext) {
        let log = ReviewLog(date: date, mode: mode.rawValue, correct: correct, grade: correct ? 3 : 1, responseTime: 3)
        context.insert(log)
        log.word = word
    }

    /// Eski sürümde çalışılmış kelime: S gün dayanıklılık, son tekrar `last`.
    private func oldWord(stability: Double, last: Date, in context: ModelContext) -> Word {
        let word = Word(english: "stale", turkish: "eskimiş")
        context.insert(word)
        word.stability = stability
        word.difficulty = 6
        word.reviewCount = 3
        word.correctCount = 2
        word.lastReviewedAt = last
        word.dueDate = last.addingTimeInterval(stability * Memory.dayLength)
        return word
    }

    @Test func unansweredWordGetsAnEmptyBase() throws {
        let context = try makeContext()
        let word = Word(english: "quorum", turkish: "yeter sayı")
        context.insert(word)
        MemoryMigration.migrateBaseIfNeeded(word, now: due)
        #expect(word.baseAt == .distantPast)
        #expect(word.baseStability == 0)
        #expect(word.baseAnchorAt == nil)
        // Göç bir kez çalışır.
        word.reviewCount = 3
        MemoryMigration.migrateBaseIfNeeded(word, now: due)
        #expect(word.baseAt == .distantPast)
    }

    @Test func oldWordBaseIsItsCacheUpToItsLastLog() throws {
        let context = try makeContext()
        let last = due.addingTimeInterval(-2 * Memory.dayLength)
        let word = oldWord(stability: 30, last: last, in: context)
        word.learnedAt = last.addingTimeInterval(-40 * Memory.dayLength)
        // Göç anında son kayıt çıpadan bir saat sonra (eski sürüm aynı gün ikinci cevabı hafızaya işlemiyordu).
        log(word, at: last, correct: true, in: context)
        log(word, at: last.addingTimeInterval(3600), correct: true, in: context)
        MemoryMigration.migrateBaseIfNeeded(word, now: due)
        #expect(word.baseAt == last.addingTimeInterval(3600))
        #expect(word.baseStability == 30)
        #expect(word.baseDifficulty == 6)
        #expect(word.baseAnchorAt == last)
        #expect(word.baseDueDate == last.addingTimeInterval(30 * Memory.dayLength))
        #expect(word.baseLapsedAt == nil)
        #expect(word.baseLearnedAt == word.learnedAt)

        // Yeniden hesap: tabandaki kayıtlar bir daha işlenmez, önbellek değişmez.
        #expect(!MemoryCache.refresh(word, now: due))
        #expect(word.stability == 30)
        #expect(word.learnedAt == last.addingTimeInterval(-40 * Memory.dayLength))
    }

    @Test func baseAtIsTheOldAnchorWhenItIsLater() throws {
        let context = try makeContext()
        let last = due.addingTimeInterval(-2 * Memory.dayLength)
        let word = oldWord(stability: 10, last: last, in: context)
        log(word, at: last.addingTimeInterval(-86_400), correct: true, in: context)
        MemoryMigration.migrateBaseIfNeeded(word, now: due)
        #expect(word.baseAt == last)
    }

    @Test func oldLapseBecomesARealLapseDueNow() throws {
        let context = try makeContext()
        let last = due.addingTimeInterval(-3 * Memory.dayLength)
        let word = oldWord(stability: 8, last: last, in: context)
        // Eski hile: yanlıştan sonra vade son tekrarın gerisine konuyordu.
        word.dueDate = last.addingTimeInterval(-5 * Memory.dayLength)
        MemoryMigration.migrateBaseIfNeeded(word, now: due)
        #expect(word.baseLapsedAt == DayBoundary.start(of: last))
        #expect(word.baseDueDate == due)

        MemoryCache.refresh(word, now: due)
        #expect(word.isLapsed)
        #expect(word.dueDate == due)
        #expect(word.isDue(at: due))
        #expect(Leitner.dueDescription(for: word.dueDate, now: due) == "Bugün")
    }

    @Test func staleCacheIgnoresLateOldLogsButPlaysNewOnes() throws {
        let context = try makeContext()
        let last = due.addingTimeInterval(-40 * Memory.dayLength)
        let word = oldWord(stability: 30, last: last, in: context)
        log(word, at: last, correct: true, in: context)
        MemoryMigration.migrateBaseIfNeeded(word, now: due)
        #expect(word.baseAt == last)

        // Başka cihazdan geç gelen, tabandan önceki yanlış: yok sayılır.
        log(word, at: last.addingTimeInterval(-86_400), correct: false, in: context)
        MemoryCache.refresh(word, now: due)
        #expect(word.stability == 30)
        #expect(!word.isLapsed)

        // Tabandan sonraki cevap oynatılır.
        log(word, at: due, correct: false, in: context)
        MemoryCache.refresh(word, now: due)
        #expect(word.isLapsed)
        #expect(word.stability < 30)
        #expect(word.answerCount == 3)
    }

    @Test func refreshAllMigratesAndReplaysEveryWordAndSaves() throws {
        let context = try makeContext()
        let old = oldWord(stability: 30, last: due.addingTimeInterval(-30 * Memory.dayLength), in: context)
        let fresh = Word(english: "quorum", turkish: "yeter sayı")
        context.insert(fresh)
        // Kelimesiz gelen kayıt (gecikmeli eşitleme) sonradan bağlanınca bir sonraki hesapta işlenir.
        let late = ReviewLog(date: due, mode: GameMode.dailyReview.rawValue, correct: true, grade: 3, responseTime: 2)
        context.insert(late)
        try context.save()

        MemoryCache.refreshAll(in: context, now: due)
        #expect(old.baseAt != nil)
        #expect(fresh.baseAt == .distantPast)
        #expect(fresh.isNew)
        #expect(!context.hasChanges)

        late.word = fresh
        #expect(MemoryCache.refreshAll(in: context, now: due) == 1)
        #expect(fresh.stability == 3)
        #expect(!context.hasChanges)
        // Değişiklik yoksa hiçbir şey yazılmaz.
        #expect(MemoryCache.refreshAll(in: context, now: due) == 0)
    }
}
