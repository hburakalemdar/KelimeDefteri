import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

struct MotivationTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar
    }()

    /// 23 Eylül 2026, 15:00 (İstanbul).
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 15))!
    }

    /// `offset` gün önce/sonra, verilen saatte `count` cevap.
    private func answers(_ count: Int, day offset: Int, hour: Int = 10) -> [Date] {
        let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
        let start = day.addingTimeInterval(Double(hour) * 3600)
        return (0..<count).map { start.addingTimeInterval(Double($0) * 60) }
    }

    // MARK: - Kilit ekranı widget'ı

    @Test func widgetShortText() {
        #expect(DailyGoal.shortText(.init(answered: 12, target: 30, streak: 4)) == "12/30 · 4 gün seri")
        #expect(DailyGoal.shortText(.init(answered: 0, target: 30, streak: 0)) == "0/30")
    }

    @Test func timelineIncludesMidnight() {
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))!
        // 22:00'den yarım saat arayla 12 an: 00:00 zaten adımlardan biri, tekrar eklenmez.
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 22))!
        let dates = DailyGoal.timelineDates(from: start, step: 1800, count: 12, calendar: calendar)
        #expect(dates.count == 12)
        #expect(dates.contains(midnight))

        // 21:45'ten başlayınca gece yarısı adımlara denk gelmez, ayrıca eklenir.
        let offset = start.addingTimeInterval(-15 * 60)
        let shifted = DailyGoal.timelineDates(from: offset, step: 1800, count: 12, calendar: calendar)
        #expect(shifted.count == 13)
        #expect(shifted.contains(midnight))
        #expect(shifted.first == offset)
        #expect(shifted == shifted.sorted())

        // Öğleden sonra başlayan 6 saatlik çizelgede gece yarısı yok.
        #expect(DailyGoal.timelineDates(from: now, step: 1800, count: 12, calendar: calendar).count == 12)
    }

    // MARK: - Günlük hedef

    @Test func todayCountUsesLocalDay() {
        // Dün 23:59 ve bugün 00:01: yalnızca ikincisi bugün sayılır.
        let dates = answers(1, day: -1, hour: 0).map { $0.addingTimeInterval(23 * 3600 + 59 * 60) }
            + answers(1, day: 0, hour: 0).map { $0.addingTimeInterval(60) }
        let progress = DailyGoal.progress(dates: dates, target: 30, now: now, calendar: calendar)
        #expect(progress.answered == 1)
        #expect(!progress.isComplete)
        #expect(progress.remaining == 29)
        #expect(abs(progress.fraction - 1.0 / 30) < 1e-9)
    }

    @Test func ringClosesAndCapsAtFull() {
        let progress = DailyGoal.progress(dates: answers(45, day: 0), target: 30, now: now, calendar: calendar)
        #expect(progress.isComplete)
        #expect(progress.fraction == 1)
        #expect(progress.remaining == 0)
        #expect(DailyGoal.text(progress) == "Hedef tamamlandı · 45 cevap")
        #expect(DailyGoal.text(.init(answered: 12, target: 30, streak: 0)) == "12 / 30 cevap")
    }

    // MARK: - Seri

    @Test func streakCountsFromYesterdayWhenTodayIsOpen() {
        let dates = answers(30, day: -3) + answers(31, day: -2) + answers(30, day: -1) + answers(5, day: 0)
        #expect(DailyGoal.streak(dates: dates, target: 30, now: now, calendar: calendar) == 3)
        // Bugün de kapanınca seri bir artar.
        let closed = dates + answers(25, day: 0, hour: 12)
        #expect(DailyGoal.streak(dates: closed, target: 30, now: now, calendar: calendar) == 4)
    }

    @Test func streakBreaksOnMissedDay() {
        // -3 gün kapandı, -2 eksik kaldı: seri yalnızca dünü sayar.
        let dates = answers(30, day: -3) + answers(29, day: -2) + answers(30, day: -1)
        #expect(DailyGoal.streak(dates: dates, target: 30, now: now, calendar: calendar) == 1)
        // Dün de kapanmadıysa seri sıfır.
        #expect(DailyGoal.streak(dates: answers(30, day: -2), target: 30, now: now, calendar: calendar) == 0)
        #expect(DailyGoal.streakText(0) == nil)
        #expect(DailyGoal.streakText(4) == "4 günlük seri")
    }

    @Test func streakUsesCurrentTargetForPastDays() {
        let dates = answers(20, day: -2) + answers(20, day: -1)
        #expect(DailyGoal.streak(dates: dates, target: 30, now: now, calendar: calendar) == 0)
        #expect(DailyGoal.streak(dates: dates, target: 20, now: now, calendar: calendar) == 2)
    }

    @Test func targetReadsDefaultsWithFallback() throws {
        let suite = "motivation-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(DailyGoal.target(in: defaults) == DailyGoal.defaultTarget)
        defaults.set(50, forKey: DailyGoal.key)
        #expect(DailyGoal.target(in: defaults) == 50)
        defaults.set(0, forKey: DailyGoal.key)
        #expect(DailyGoal.target(in: defaults) == DailyGoal.defaultTarget)
        #expect(DailyGoal.options.contains(DailyGoal.defaultTarget))
    }

    // MARK: - Haftalık özet

    private typealias Summary = WeeklySummary<String>

    private func answer(_ word: String, day offset: Int, correct: Bool, minute: Int = 0) -> Summary.Answer {
        let date = answers(1, day: offset).first!.addingTimeInterval(Double(minute) * 60)
        return .init(word: word, date: date, correct: correct)
    }

    @Test func weeklyCountsOnlyLastSevenDays() {
        let summary = Summary(answers: [
            answer("old", day: -7, correct: false),
            answer("a", day: -6, correct: true),
            answer("a", day: 0, correct: false),
            answer("b", day: -1, correct: true),
            answer("future", day: 1, correct: true),
        ], now: now, calendar: calendar)
        #expect(summary.answerCount == 3)
        #expect(summary.correctCount == 2)
        #expect(summary.accuracy == 2.0 / 3)
        #expect(summary.days.count == 7)
        #expect(summary.days.first?.day == calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)))
        #expect(summary.days.map(\.count) == [1, 0, 0, 0, 0, 1, 1])
    }

    @Test func strengthenedNeedsLastAnswerCorrect() {
        let summary = Summary(answers: [
            answer("a", day: -2, correct: false),
            answer("a", day: -1, correct: true),   // sonunda doğru: güçlendi
            answer("b", day: -2, correct: true),
            answer("b", day: -1, correct: false),  // sonunda yanlış: zayıf
            answer("c", day: 0, correct: true),
            answer("d", day: 0, correct: false),
        ], now: now, calendar: calendar)
        #expect(summary.strengthenedCount == 2)
    }

    @Test func hardestSortedByWrongThenRate() {
        var list: [Summary.Answer] = []
        // e: 3 yanlış / 3; f: 3 yanlış / 5; g: 1 yanlış; h: hiç yanlış yok.
        for index in 0..<3 { list.append(answer("e", day: -1, correct: false, minute: index)) }
        for index in 0..<3 { list.append(answer("f", day: -2, correct: false, minute: index)) }
        for index in 0..<2 { list.append(answer("f", day: -2, correct: true, minute: 10 + index)) }
        list.append(answer("g", day: 0, correct: false))
        list.append(answer("h", day: 0, correct: true))
        for word in ["i", "j", "k", "l"] { list.append(answer(word, day: -3, correct: false)) }

        let summary = Summary(answers: list, now: now, calendar: calendar)
        #expect(summary.hardest.count == Summary.hardestLimit)
        #expect(summary.hardest.prefix(2).map(\.word) == ["e", "f"])
        #expect(summary.hardest[1].total == 5)
        #expect(!summary.hardest.map(\.word).contains("h"))
        // Tek yanlışı olanlarda en son görülen önde: g (bugün).
        #expect(summary.hardest[2].word == "g")
    }

    @Test func emptyWeek() {
        let summary = Summary(answers: [], now: now, calendar: calendar)
        #expect(summary.answerCount == 0)
        #expect(summary.accuracy == nil)
        #expect(summary.hardest.isEmpty)
        #expect(summary.days.allSatisfy { $0.count == 0 })
    }

    // MARK: - Kayıtlardan uçtan uca

    @Test func goalCountsRecordedAnswers() throws {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let word = Word(english: "quorum", turkish: "yeter sayı")
        context.insert(word)
        for index in 0..<3 {
            ReviewRecorder.record(word, grade: .good, mode: .quickRound, responseTime: 3,
                                  now: now.addingTimeInterval(Double(index)))
        }
        try context.save()
        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        let progress = DailyGoal.progress(dates: logs.map(\.date), target: 3, now: now, calendar: calendar)
        #expect(progress.answered == 3)
        #expect(progress.isComplete)
        #expect(progress.streak == 1)
    }

    // MARK: - Öğrenildi

    @Test func learnedThreshold() {
        let word = Word(english: "coalesce", turkish: "birleştirmek")
        word.stability = Memory.learnedStability - 0.1
        word.lastReviewedAt = now
        word.dueDate = now.addingTimeInterval(word.stability * Memory.dayLength)
        #expect(!word.isLearned)
        word.stability = Memory.learnedStability
        word.dueDate = now.addingTimeInterval(word.stability * Memory.dayLength)
        #expect(word.isLearned)
        // Yanlış bilinip henüz toparlanmamış (zayıf) kelime öğrenilmiş sayılmaz.
        word.lapsedAt = now
        #expect(!word.isLearned)
    }
}
