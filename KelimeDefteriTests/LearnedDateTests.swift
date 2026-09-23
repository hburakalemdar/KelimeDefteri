import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

/// Öğrenilme tarihi (`Word.learnedAt`): cevapta yazılır/silinir, eski kelimelere geçişle dolar,
/// "Bu Hafta" sayfasında haftalık sayılır.
struct LearnedDateTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()

    /// 21 Eylül 2026 + gün, verilen saat (İstanbul).
    private func day(_ offset: Int, _ hour: Int = 9) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: hour))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    /// Verilen dayanıklılıkta, son tekrarı `last` olan kelime.
    private func word(_ english: String, stability: Double, last: Date, in context: ModelContext) -> Word {
        let word = Word(english: english, turkish: "t", createdAt: day(-60))
        context.insert(word)
        word.stability = stability
        word.difficulty = 5
        word.reviewCount = 3
        word.correctCount = 3
        word.lastReviewedAt = last
        word.dueDate = last.addingTimeInterval(stability * Memory.dayLength)
        return word
    }

    private func record(_ word: Word, _ grade: AnswerGrade, at date: Date) {
        ReviewRecorder.record(word, grade: grade, mode: .dailyReview, responseTime: 3, now: date, calendar: calendar)
    }

    @Test func learnedAtIsSetOnTheAnswerThatMakesTheWordLearned() throws {
        let context = try makeContext()
        let word = word("quorum", stability: 15, last: day(-15), in: context)
        #expect(!word.isLearned)

        record(word, .good, at: day(0))
        #expect(word.isLearned)
        #expect(word.learnedAt == day(0))

        // Sonraki doğru cevap tarihi değiştirmez.
        record(word, .good, at: day(40))
        #expect(word.isLearned)
        #expect(word.learnedAt == day(0))
    }

    @Test func wrongAnswerClearsLearnedAt() throws {
        let context = try makeContext()
        let word = word("quorum", stability: 30, last: day(-20), in: context)
        word.learnedAt = day(-20)

        record(word, .again, at: day(0))
        #expect(!word.isLearned)
        #expect(word.learnedAt == nil)
    }

    @Test func notLearnedWordKeepsNilLearnedAt() throws {
        let context = try makeContext()
        let word = word("quorum", stability: 2, last: day(-2), in: context)
        record(word, .good, at: day(0))
        #expect(!word.isLearned)
        #expect(word.learnedAt == nil)
    }

    @Test func migrationFillsLearnedAtFromLastReviewAndIsIdempotent() throws {
        let context = try makeContext()
        let learned = word("quorum", stability: 30, last: day(-10), in: context)
        let weak = word("latch", stability: 3, last: day(-1), in: context)
        let lapsed = word("mutex", stability: 30, last: day(-1), in: context)
        lapsed.dueDate = day(-3)
        try context.save()

        #expect(MemoryMigration.fillLearnedDates(context: context) == 1)
        #expect(learned.learnedAt == day(-10))
        #expect(weak.learnedAt == nil)
        #expect(lapsed.learnedAt == nil)

        // İkinci çalıştırma bir şey değiştirmez.
        #expect(MemoryMigration.fillLearnedDates(context: context) == 0)
        MemoryMigration.migrateIfNeeded(context: context)
        #expect(learned.learnedAt == day(-10))
    }

    @Test func migrationKeepsExistingLearnedAt() throws {
        let context = try makeContext()
        let learned = word("quorum", stability: 30, last: day(-1), in: context)
        learned.learnedAt = day(-30)
        try context.save()
        #expect(MemoryMigration.fillLearnedDates(context: context) == 0)
        #expect(learned.learnedAt == day(-30))
    }

    @Test func weeklySummaryCountsLearnedThisWeek() {
        let now = day(0, 12)
        let summary = WeeklySummary<Int>(
            answers: [],
            learnedDates: [day(0), day(-6, 0), day(-7, 23), day(-30), nil, day(1)],
            now: now,
            calendar: calendar
        )
        #expect(summary.learnedCount == 6)
        // Bugün ve 6 gün önce (gün başı dahil) sayılır; 7 gün önce, bilinmeyen ve yarın sayılmaz.
        #expect(summary.learnedThisWeek == 2)

        let empty = WeeklySummary<Int>(answers: [], now: now, calendar: calendar)
        #expect(empty.learnedCount == 0)
        #expect(empty.learnedThisWeek == 0)
    }
}
