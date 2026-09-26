import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

/// Mantık düzeltmelerinin testleri: duraklatılmış saat, tur süresi, gün dönümü, tur içinde yeniden
/// sorma, %50 gösterimi, eski biçimli kelime, silinmiş kelime, bildirim sayısı.
struct LogicFixesTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "test-\(UUID().uuidString)")! }

    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    /// Çalışılmış ve zayıflamış kelime.
    private func weakWord(_ english: String) -> Word {
        let word = Word(english: english, turkish: "anlam \(english)")
        word.reviewCount = 2
        word.correctCount = 2
        word.stability = 3
        word.difficulty = 5
        word.lastReviewedAt = now.addingTimeInterval(-10 * Memory.dayLength)
        word.dueDate = word.lastReviewedAt!.addingTimeInterval(3 * Memory.dayLength)
        return word
    }

    /// Güçlü (uzun süredir hatırlanan) kelime.
    private func strongWord(_ english: String) -> Word {
        let word = Word(english: english, turkish: "anlam \(english)")
        word.reviewCount = 3
        word.stability = 30
        word.difficulty = 5
        word.lastReviewedAt = now.addingTimeInterval(-Memory.dayLength)
        word.dueDate = word.lastReviewedAt!.addingTimeInterval(30 * Memory.dayLength)
        return word
    }

    // MARK: - 1. Duraklatma ilerleyince silinmez

    @Test func pauseSurvivesANewRound() throws {
        let context = try makeContext()
        let first = Word(english: "stale", turkish: "eskimiş")
        context.insert(first)
        let session = StudySession(seed: 1, defaults: defaults())
        session.start(with: [first], plan: .daily, now: now)
        session.play(known: true, now: now.addingTimeInterval(3))
        #expect(session.current == nil)
        // Pencere kapandı; saatler sonra ⇧⌘E ile kelime eklendi ve yeni tur başladı.
        session.pauseClock(now: now.addingTimeInterval(5))
        let added = Word(english: "quorum", turkish: "yeter sayı")
        context.insert(added)
        let later = now.addingTimeInterval(5 * 3_600)
        session.start(with: [added], plan: .daily, now: later)
        // Pencere bir saat sonra açılıyor.
        session.resumeClock(now: later.addingTimeInterval(3_600))
        session.reveal(answer: "yeter sayı", now: later.addingTimeInterval(3_602))
        session.play(known: true, now: later.addingTimeInterval(3_603))
        let log = try context.fetch(FetchDescriptor<ReviewLog>()).first { $0.word === added }
        #expect(log?.responseTime == 2)
        #expect(log?.grade == AnswerGrade.easy.rawValue)
    }

    @Test func gameRoundPauseSurvivesAdvanceAndStart() {
        let words = (0..<3).map { Word(english: "w\($0)", turkish: "anlam \($0)") }
        let round = GameRound(mode: .multipleChoice, seed: 1, defaults: defaults())
        round.start(with: words, count: 3, now: now)
        round.pauseClock(now: now.addingTimeInterval(1))
        round.advance(now: now.addingTimeInterval(50))
        round.resumeClock(now: now.addingTimeInterval(150))
        #expect(round.shownAt == now.addingTimeInterval(150))

        round.pauseClock(now: now.addingTimeInterval(200))
        round.start(with: words, count: 3, now: now.addingTimeInterval(300))
        round.resumeClock(now: now.addingTimeInterval(1_000))
        #expect(round.shownAt == now.addingTimeInterval(1_000))
        #expect(round.startedAt == now.addingTimeInterval(1_000))
    }

    // MARK: - 2. Tur süresi arka planı saymaz

    @Test func roundDurationSkipsBackgroundTime() {
        let words = [weakWord("a"), weakWord("b")]
        let session = StudySession(seed: 1, defaults: defaults())
        session.start(with: words, plan: .daily, now: now)
        session.play(known: true, now: now.addingTimeInterval(10))
        session.pauseClock(now: now.addingTimeInterval(20))
        session.resumeClock(now: now.addingTimeInterval(3_620))
        #expect(session.startedAt == now.addingTimeInterval(3_600))
        session.play(known: true, now: now.addingTimeInterval(3_630))
        #expect(session.finishedAt.timeIntervalSince(session.startedAt) == 30)

        // Bitmiş turda kaymaz: süre eksiye düşmesin.
        session.pauseClock(now: now.addingTimeInterval(4_000))
        session.resumeClock(now: now.addingTimeInterval(9_000))
        #expect(session.startedAt == now.addingTimeInterval(3_600))

        let round = GameRound(mode: .match, seed: 1, defaults: defaults())
        round.start(with: words, count: 2, now: now)
        round.pauseClock(now: now.addingTimeInterval(5))
        round.resumeClock(now: now.addingTimeInterval(105))
        #expect(round.startedAt == now.addingTimeInterval(100))
        round.finish()
        round.pauseClock(now: now.addingTimeInterval(200))
        round.resumeClock(now: now.addingTimeInterval(900))
        #expect(round.startedAt == now.addingTimeInterval(100))
    }

    // MARK: - 4. Gün dönümü

    @Test func answerOnAnotherDayChangesMemoryAgain() throws {
        let context = try makeContext()
        var calendar = Calendar.current
        calendar.timeZone = .current
        let dayOne = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: now)!
        let dayTwo = dayOne.addingTimeInterval(14 * 3_600)
        let words = [weakWord("a"), weakWord("b"), weakWord("c")]
        for word in words { context.insert(word) }
        let session = StudySession(seed: 1, defaults: defaults())
        session.start(with: words, plan: .daily, now: dayOne)
        #expect(!session.began(onAnotherDayThan: dayOne.addingTimeInterval(3_600)))
        #expect(session.began(onAnotherDayThan: dayTwo))

        let missed = session.current!
        session.play(known: false, now: dayOne.addingTimeInterval(60))
        #expect(missed.isLapsed)
        let lapsedStability = missed.stability
        session.play(known: true, now: dayTwo)
        session.play(known: true, now: dayTwo.addingTimeInterval(10))
        #expect(session.current === missed)
        session.play(known: true, now: dayTwo.addingTimeInterval(30))
        // Ertesi günkü cevap hafızayı değiştirdi: kelime zayıflıktan çıktı, dayanıklılık büyüdü.
        #expect(missed.lastReviewedAt == DayBoundary.start(of: dayTwo))
        #expect(missed.stability > lapsedStability)
        #expect(!missed.isLapsed)
        #expect(!missed.isDue(at: dayTwo.addingTimeInterval(60)))
        // Özet ilk cevabı tutar.
        #expect(session.roundEntries.count == 3)
        #expect(session.roundEntries.first { $0.word === missed }?.firstCorrect == false)
    }

    // MARK: - 6. Yanlış cevaptan sonra %50

    @Test func lapsedMemoryShowsFiftyPercentForAWhile() throws {
        let context = try makeContext()
        let word = strongWord("coalesce")
        context.insert(word)
        ReviewRecorder.record(word, grade: .again, mode: .dailyReview, responseTime: 3, now: now)
        #expect(MemoryStats.text(word.memory(at: now)) == "%50")
        #expect(MemoryStats.text(word.memory(at: now.addingTimeInterval(3_600))) == "%50")

        let new = Word(english: "quorum", turkish: "yeter sayı")
        context.insert(new)
        ReviewRecorder.record(new, grade: .again, mode: .dailyReview, responseTime: 3, now: now)
        #expect(MemoryStats.text(new.memory(at: now)) == "%50")
        #expect(new.isLapsed)
        // Zayıf kelime yarına kadar yeniden seçilmez.
        #expect(!new.isDue(at: now))
        #expect(new.isDue(at: DayBoundary.nextStart(after: now)))
    }

    // MARK: - 7. Tur içinde yeniden sorma

    @Test func missedWordWithoutRoomIsNotAskedAgain() throws {
        let context = try makeContext()
        let word = strongWord("idempotent")
        context.insert(word)
        let session = StudySession(seed: 1, defaults: defaults())
        session.start(with: [word], plan: .extraPractice, now: now)
        session.play(known: false, now: now.addingTimeInterval(5))
        // Arada 2 kart kalmadığı için yeniden sorulmaz, kelime biten sayılır.
        #expect(session.current == nil)
        #expect(session.finishedWordCount == 1)
        #expect(word.isLapsed)
    }

    @Test func sameDayRepeatDoesNotClearTheLapse() throws {
        let context = try makeContext()
        let words = ["idempotent", "coalesce", "quorum"].map(strongWord)
        for word in words { context.insert(word) }
        let session = StudySession(seed: 1, defaults: defaults())
        session.start(with: words, plan: .extraPractice, now: now)
        let missed = session.current!
        session.play(known: false, now: now.addingTimeInterval(5))
        #expect(session.current !== missed)
        session.play(known: true, now: now.addingTimeInterval(10))
        session.play(known: true, now: now.addingTimeInterval(15))
        #expect(session.current === missed)
        // Yanlıştan 30 dakika içindeki doğru günün notuna sayılmaz: kelime zayıf kalır, yarın sorulur.
        session.play(known: true, now: now.addingTimeInterval(20))
        #expect(session.current == nil)
        #expect(session.finishedWordCount == 3)
        #expect(missed.isLapsed)
        #expect(missed.dueDate == DayBoundary.nextStart(after: now))
        #expect(session.roundEntries.first { $0.word === missed }?.firstCorrect == false)
    }

    // MARK: - 8. Eski biçimli kelime

    private func oldFormatWord() -> Word {
        let word = Word(english: "quorum", turkish: "yeter sayı")
        word.box = 3
        word.reviewCount = 4
        word.correctCount = 3
        word.dueDate = now.addingTimeInterval(-2 * Memory.dayLength)
        return word
    }

    @Test func oldFormatWordIsNotTreatedAsNew() {
        let word = oldFormatWord()
        let session = StudySession(seed: 1, defaults: defaults())
        session.start(with: [word], plan: .daily, now: now)
        #expect(!word.isNew)
        #expect(session.current === word)
        #expect(StudySession.dailyCount([word], now: now) == (weak: 1, new: 0))
        session.play(known: true, now: now)
        #expect(session.roundEntries.first?.dueBefore == now.addingTimeInterval(-2 * Memory.dayLength))
        #expect(session.roundEntries.first?.lapsedBefore == false)

        let other = oldFormatWord()
        let round = GameRound(mode: .multipleChoice, seed: 1, defaults: defaults())
        round.start(with: [other], count: 1, now: now)
        round.record(other, grade: .good, now: now)
        #expect(round.entries.first?.dueBefore != nil)

        let synced = oldFormatWord()
        session.start(with: [], plan: .weak, now: now)
        session.sync(with: [synced], now: now)
        #expect(!synced.isNew)
    }

    // MARK: - 9. Öğrenildi

    @Test func lapsedWordIsNotLearned() throws {
        let context = try makeContext()
        let word = strongWord("coalesce")
        context.insert(word)
        #expect(word.isLearned)
        ReviewRecorder.record(word, grade: .again, mode: .dailyReview, responseTime: 3, now: now)
        word.stability = 25
        #expect(word.isLapsed)
        #expect(!word.isLearned)
    }

    // MARK: - 10. Silinmiş kelime

    @Test func deletedWordIsIgnored() throws {
        let context = try makeContext()
        let word = Word(english: "stale", turkish: "eskimiş")
        context.insert(word)
        try context.save()
        context.delete(word)
        #expect(ReviewRecorder.record(word, grade: .good, mode: .dailyReview, responseTime: 3, now: now) == nil)
        #expect(word.reviewCount == 0)

        // Depoya eklenmemiş kelimeye kayıt bağlanamaz; hafızası kayıtlardan hesaplandığı için değişmez.
        let loose = Word(english: "quorum", turkish: "yeter sayı")
        #expect(ReviewRecorder.record(loose, grade: .good, mode: .dailyReview, responseTime: 3, now: now) == nil)
        #expect(loose.isNew)
    }

    @Test func sessionSurvivesADeletedCurrentWord() throws {
        let context = try makeContext()
        let words = [Word(english: "stale", turkish: "eskimiş"), Word(english: "quorum", turkish: "yeter sayı")]
        for word in words { context.insert(word) }
        try context.save()
        let session = StudySession(seed: 1, defaults: defaults())
        session.start(with: words, plan: .daily, now: now)
        let deleted = session.current!
        session.reveal(answer: "yanlış", now: now)
        context.delete(deleted)
        session.commitPendingAnswer(now: now)
        session.play(known: true, now: now)
        #expect(session.current != nil)
        #expect(session.current !== deleted)
        #expect(session.wordCount == 1)
        #expect(try context.fetch(FetchDescriptor<ReviewLog>()).isEmpty)
    }

    // MARK: - 11. Rozet ve bildirim sayısı

    @Test func badgeCountMatchesDailyReview() {
        let fresh = (0..<12).map { Word(english: "n\($0)", turkish: "anlam") }
        #expect(ReminderScheduler.dailyTotal(fresh, now: now, newAllowance: 10) == 10)
        #expect(ReminderScheduler.dailyTotal(fresh, now: now, newAllowance: 5) == 5)
        // Tekrarlarda tavan yok (güvenlik tavanı 100); yeni hakkı tekrarların üstüne.
        let weak = (0..<25).map { weakWord("w\($0)") }
        #expect(ReminderScheduler.dailyTotal(weak + fresh, now: now, newAllowance: 10) == 35)
        let piledUp = (0..<120).map { weakWord("p\($0)") }
        #expect(ReminderScheduler.dailyTotal(piledUp + fresh, now: now, newAllowance: 10) == 100)
        #expect(ReminderScheduler.dailyTotal([strongWord("s")], now: now, newAllowance: 10) == 0)
    }
}
