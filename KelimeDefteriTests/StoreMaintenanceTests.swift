import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

final class StoreMaintenanceTests {
    private let base = Date(timeIntervalSince1970: 1_790_000_000)
    /// Sahipsiz kayıt notları gerçek ayarlara karışmasın diye her test kendi ayar alanını kullanır.
    private let suiteName = "StoreMaintenanceTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// Bellek içi depo iOS 27 simülatöründe kaydederken ara ara çöktüğü için geçici dosya kullanılır.
    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    private func words(_ context: ModelContext) throws -> [Word] {
        try context.fetch(FetchDescriptor<Word>(sortBy: [SortDescriptor(\.english)]))
    }

    private func addLog(to word: Word, correct: Bool, in context: ModelContext) {
        let log = ReviewLog(date: base, mode: "recall", correct: correct, grade: correct ? 3 : 1, responseTime: 2)
        context.insert(log)
        log.word = word
    }

    @Test func oldestStaysAndFieldsMerge() throws {
        let context = try makeContext()
        let newer = Word(english: "Quorum", turkish: "yeter sayı, nisap", example: "No quorum today.", createdAt: base.addingTimeInterval(60))
        newer.reviewCount = 3
        newer.correctCount = 2
        let older = Word(english: "quorum", turkish: "yeter sayı", createdAt: base)
        older.reviewCount = 1
        older.correctCount = 1
        let other = Word(english: "stale", turkish: "eskimiş")
        for word in [newer, older, other] { context.insert(word) }
        try context.save()

        let summary = StoreMaintenance.run(in: context, defaults: defaults, now: base)
        #expect(summary == StoreMaintenance.Summary(mergedWords: 1, removedLogs: 0))

        let remaining = try words(context)
        #expect(remaining.count == 2)
        let kept = try #require(remaining.first { $0.english == "quorum" })
        #expect(kept.createdAt == base)
        #expect(kept.turkish == "yeter sayı, nisap")
        #expect(kept.example == "No quorum today.")
        #expect(kept.reviewCount == 4)
        #expect(kept.correctCount == 3)
    }

    @Test func existingExampleIsNotOverwritten() throws {
        let context = try makeContext()
        let older = Word(english: "stale", turkish: "eskimiş", example: "A stale cache.", createdAt: base)
        let newer = Word(english: "stale", turkish: "bayat", example: "Stale bread.", createdAt: base.addingTimeInterval(1))
        context.insert(older)
        context.insert(newer)

        StoreMaintenance.run(in: context, defaults: defaults, now: base)
        let kept = try #require(try words(context).first)
        #expect(kept.example == "A stale cache.")
        #expect(kept.turkish == "eskimiş, bayat")
    }

    @Test func logsMoveToKeptWord() throws {
        let context = try makeContext()
        let older = Word(english: "quorum", turkish: "yeter sayı", createdAt: base)
        let newer = Word(english: "quorum", turkish: "nisap", createdAt: base.addingTimeInterval(5))
        context.insert(older)
        context.insert(newer)
        addLog(to: older, correct: true, in: context)
        addLog(to: newer, correct: false, in: context)
        addLog(to: newer, correct: true, in: context)
        try context.save()

        StoreMaintenance.run(in: context, defaults: defaults, now: base)
        let kept = try #require(try words(context).first)
        #expect(try words(context).count == 1)
        #expect(kept.logs?.count == 3)
        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        #expect(logs.count == 3)
        #expect(logs.allSatisfy { $0.word === kept })
    }

    @Test func memoryComesFromLatestReviewedWord() throws {
        let context = try makeContext()
        let older = Word(english: "quorum", turkish: "yeter sayı", createdAt: base)
        older.stability = 3
        older.difficulty = 6
        older.dueDate = base.addingTimeInterval(3 * 86_400)
        older.lastReviewedAt = base
        let newer = Word(english: "quorum", turkish: "nisap", createdAt: base.addingTimeInterval(5))
        newer.stability = 9
        newer.difficulty = 4
        newer.dueDate = base.addingTimeInterval(20 * 86_400)
        newer.lastReviewedAt = base.addingTimeInterval(86_400)
        context.insert(older)
        context.insert(newer)

        StoreMaintenance.run(in: context, defaults: defaults, now: base)
        let kept = try #require(try words(context).first)
        #expect(kept.createdAt == base)
        #expect(kept.stability == 9)
        #expect(kept.difficulty == 4)
        #expect(kept.dueDate == base.addingTimeInterval(20 * 86_400))
        #expect(kept.lastReviewedAt == base.addingTimeInterval(86_400))
    }

    @Test func studiedOlderKeepsMemoryOverUnstudiedNewer() throws {
        let context = try makeContext()
        let older = Word(english: "quorum", turkish: "yeter sayı", createdAt: base)
        older.stability = 3
        older.lastReviewedAt = base
        older.dueDate = base.addingTimeInterval(3 * 86_400)
        let newer = Word(english: "quorum", turkish: "nisap", createdAt: base.addingTimeInterval(5))
        context.insert(older)
        context.insert(newer)

        StoreMaintenance.run(in: context, defaults: defaults, now: base)
        let kept = try #require(try words(context).first)
        #expect(kept.stability == 3)
        #expect(kept.lastReviewedAt == base)
    }

    @Test func unstudiedGroupKeepsOlderMemory() throws {
        let context = try makeContext()
        let older = Word(english: "quorum", turkish: "yeter sayı", createdAt: base)
        older.dueDate = base
        let newer = Word(english: "quorum", turkish: "nisap", createdAt: base.addingTimeInterval(5))
        newer.difficulty = 8
        newer.dueDate = base.addingTimeInterval(99)
        context.insert(older)
        context.insert(newer)

        StoreMaintenance.run(in: context, defaults: defaults, now: base)
        let kept = try #require(try words(context).first)
        #expect(kept.isNew)
        #expect(kept.difficulty == 5)
        #expect(kept.dueDate == base)
        #expect(kept.lastReviewedAt == nil)
    }

    @Test func tripleCopiesMergeIntoOne() throws {
        let context = try makeContext()
        let first = Word(english: "take", turkish: "almak", createdAt: base)
        let second = Word(english: "Take", turkish: "götürmek", createdAt: base.addingTimeInterval(1))
        second.reviewCount = 2
        second.lastReviewedAt = base.addingTimeInterval(10)
        second.stability = 4
        let third = Word(english: "take.", turkish: "almak, sürmek", example: "Take it.", createdAt: base.addingTimeInterval(2))
        third.reviewCount = 1
        third.lastReviewedAt = base.addingTimeInterval(5)
        third.stability = 2
        for word in [third, first, second] { context.insert(word) }
        addLog(to: third, correct: true, in: context)

        let summary = StoreMaintenance.run(in: context, defaults: defaults, now: base)
        #expect(summary.mergedWords == 2)
        let remaining = try words(context)
        #expect(remaining.count == 1)
        let kept = try #require(remaining.first)
        #expect(kept.english == "take")
        #expect(kept.turkish == "almak, götürmek, sürmek")
        #expect(kept.example == "Take it.")
        #expect(kept.reviewCount == 3)
        #expect(kept.stability == 4)
        #expect(kept.logs?.count == 1)
    }

    @Test func equalDatesResolveTheSameWayRegardlessOfInsertOrder() throws {
        func result(insertingReversed: Bool) throws -> (String, String) {
            let context = try makeContext()
            var pair = [
                Word(english: "Quorum", turkish: "nisap", createdAt: base),
                Word(english: "quorum", turkish: "yeter sayı", createdAt: base),
            ]
            if insertingReversed { pair.reverse() }
            for word in pair { context.insert(word) }
            try context.save()
            StoreMaintenance.run(in: context, defaults: defaults, now: base)
            let kept = try #require(try words(context).first)
            return (kept.english, kept.turkish)
        }
        let forward = try result(insertingReversed: false)
        let reversed = try result(insertingReversed: true)
        #expect(forward == reversed)
        // "Q" < "q": büyük harfli yazılış kalır, anlamları önce gelir.
        #expect(forward.0 == "Quorum")
        #expect(forward.1 == "nisap, yeter sayı")
    }

    @Test func relatedButDifferentWordsStaySeparate() throws {
        let context = try makeContext()
        context.insert(Word(english: "take", turkish: "almak", createdAt: base))
        context.insert(Word(english: "take into account", turkish: "hesaba katmak", createdAt: base))
        try context.save()

        let summary = StoreMaintenance.run(in: context, defaults: defaults, now: base)
        #expect(!summary.changed)
        #expect(try words(context).count == 2)
    }

    private func insertOrphan(in context: ModelContext) -> ReviewLog {
        let orphan = ReviewLog(date: base, mode: "recall", correct: false, grade: 1, responseTime: 3)
        context.insert(orphan)
        return orphan
    }

    private func logCount(_ context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<ReviewLog>())
    }

    @Test func orphanLogIsNotDeletedOnFirstSight() throws {
        let context = try makeContext()
        let word = Word(english: "quorum", turkish: "yeter sayı")
        context.insert(word)
        addLog(to: word, correct: true, in: context)
        _ = insertOrphan(in: context)
        try context.save()

        let summary = StoreMaintenance.run(in: context, defaults: defaults, now: base)
        #expect(!summary.changed)
        #expect(try logCount(context) == 2)
        #expect(defaults.data(forKey: StoreMaintenance.orphanDefaultsKey) != nil)

        // Bir saat dolmadan yine silinmez.
        let early = StoreMaintenance.run(in: context, defaults: defaults, now: base.addingTimeInterval(59 * 60))
        #expect(!early.changed)
        #expect(try logCount(context) == 2)
    }

    @Test func orphanLogIsDeletedAfterAnHour() throws {
        let context = try makeContext()
        let word = Word(english: "quorum", turkish: "yeter sayı")
        context.insert(word)
        addLog(to: word, correct: true, in: context)
        _ = insertOrphan(in: context)
        try context.save()

        StoreMaintenance.run(in: context, defaults: defaults, now: base)
        // Arada yapılan çalışma ilk görülme zamanını ileri kaydırmaz.
        StoreMaintenance.run(in: context, defaults: defaults, now: base.addingTimeInterval(30 * 60))
        let summary = StoreMaintenance.run(in: context, defaults: defaults, now: base.addingTimeInterval(60 * 60))
        #expect(summary == StoreMaintenance.Summary(mergedWords: 0, removedLogs: 1))
        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.word === word)
        #expect(!context.hasChanges)
        #expect(defaults.data(forKey: StoreMaintenance.orphanDefaultsKey) == nil)

        // Sonraki çalıştırma bir şey değiştirmez.
        #expect(!StoreMaintenance.run(in: context, defaults: defaults, now: base.addingTimeInterval(2 * 60 * 60)).changed)
    }

    @Test func orphanThatFindsItsWordIsKept() throws {
        let context = try makeContext()
        let orphan = insertOrphan(in: context)
        try context.save()
        StoreMaintenance.run(in: context, defaults: defaults, now: base)

        // Kelimesi iCloud'dan sonradan geldi.
        let word = Word(english: "quorum", turkish: "yeter sayı")
        context.insert(word)
        orphan.word = word
        try context.save()
        let summary = StoreMaintenance.run(in: context, defaults: defaults, now: base.addingTimeInterval(2 * 60 * 60))
        #expect(!summary.changed)
        #expect(try logCount(context) == 1)
        #expect(defaults.data(forKey: StoreMaintenance.orphanDefaultsKey) == nil)

        // Yeniden sahipsiz kalırsa süre baştan sayılır.
        orphan.word = nil
        try context.save()
        let later = base.addingTimeInterval(3 * 60 * 60)
        #expect(!StoreMaintenance.run(in: context, defaults: defaults, now: later).changed)
        #expect(StoreMaintenance.run(in: context, defaults: defaults, now: later.addingTimeInterval(60 * 60)).removedLogs == 1)
    }
}
