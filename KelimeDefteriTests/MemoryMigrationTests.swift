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
}
