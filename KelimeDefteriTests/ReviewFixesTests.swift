import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

/// İnceleme sonrası düzeltmelerin testleri: ortak anlamlı seçenek, boşluğun yeri,
/// Günlük Tekrar dağılımı, kapatınca kaydedilen cevap, arka planda duran saat, geç gelen eski kayıt.
struct ReviewFixesTests {
    private typealias C = ChoiceQuiz.Candidate

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "test-\(UUID().uuidString)")! }

    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    private func studied(_ english: String, weak: Bool) -> Word {
        let word = Word(english: english, turkish: "anlam")
        word.reviewCount = 1
        word.stability = weak ? 1 : 30
        word.lastReviewedAt = Date.now.addingTimeInterval(weak ? -5 * 86_400 : 0)
        word.dueDate = word.lastReviewedAt!.addingTimeInterval(word.stability * 86_400)
        return word
    }

    // MARK: - Seçenekler

    @Test func wordSharingAnyMeaningIsNeverAWrongOption() {
        for seed in 0..<40 as Range<UInt64> {
            var generator = SeededGenerator(seed: seed)
            let others = [C(turkish: "eskimiş"), C(turkish: "verim"),
                          C(turkish: "yeter sayı"), C(turkish: "silinme")]
            let result = ChoiceQuiz.options(answer: C(turkish: "bayat, eskimiş"), others: others, using: &generator)
            #expect(result.options[result.correctIndex] == "bayat")
            #expect(!result.options.contains("eskimiş"))
            #expect(result.options.count == 4)
        }
        #expect(ChoiceQuiz.shareMeaning("bayat, eskimiş", "Eskimiş"))
        #expect(!ChoiceQuiz.shareMeaning("bayat", "eskimiş"))
    }

    @Test func matchBoardNeverHoldsTwoWordsWithSharedMeaning() {
        let words = [Word(english: "stale", turkish: "bayat, eskimiş"), Word(english: "outdated", turkish: "eskimiş")]
            + (0..<6).map { Word(english: "w\($0)", turkish: "anlam \($0)") }
        for seed in 0..<30 as Range<UInt64> {
            let round = GameRound(mode: .match, seed: seed, defaults: defaults())
            round.start(with: words, count: 6, conflicts: { ChoiceQuiz.shareMeaning($0.turkish, $1.turkish) })
            #expect(round.count == 6)
            #expect(round.words.count { ["stale", "outdated"].contains($0.english) } <= 1)
        }
    }

    // MARK: - Boşluğu Doldur

    @Test func blankPrefersTheWholeWordOverAnotherWord() {
        let cloze = ClozeSentence(sentence: "Artificial intelligence is art.", word: "art")
        #expect(cloze?.before == "Artificial intelligence is ")
        #expect(cloze?.after == ".")
        #expect(ClozeSentence(sentence: "Artificial intelligence.", word: "art") == nil)
        #expect(ClozeSentence(sentence: "The artist left.", word: "art") == nil)
        #expect(ClozeSentence(sentence: "Keep it running.", word: "run")?.match == "run")
        #expect(ClozeSentence(sentence: "The job stopped.", word: "stop")?.after == "ped.")
        #expect(ClozeSentence(sentence: "Deletions are tombstones.", word: "tombstone")?.after == "s.")
    }

    // MARK: - Günlük Tekrar

    @Test func dailyRoundMatchesTheCardBreakdown() {
        for seed in 0..<20 as Range<UInt64> {
            let words = (0..<18).map { studied("w\($0)", weak: true) }
                + (0..<5).map { Word(english: "n\($0)", turkish: "yeni") }
            let session = StudySession(seed: seed, defaults: defaults())
            session.start(with: words, plan: .daily)
            var asked: [Word] = []
            while let current = session.current, asked.count < 100 {
                asked.append(current)
                session.play(known: true)
            }
            #expect(asked.count == 20)
            #expect(asked.count { $0.english.hasPrefix("w") } == 18)
            #expect(asked.count { $0.english.hasPrefix("n") } == 2)
        }
    }

    // MARK: - Kapatınca cevap

    @Test func closingAfterRevealRecordsTheKnownResult() throws {
        let context = try makeContext()
        let correct = studied("stale", weak: true)
        context.insert(correct)
        let session = StudySession(seed: 1, defaults: defaults())
        session.start(with: [correct], plan: .daily)
        session.reveal(answer: "anlam")
        session.gradePendingAnswer()
        #expect(correct.logs?.map(\.correct) == [true])
        #expect(session.current == nil)

        let wrong = studied("quorum", weak: true)
        context.insert(wrong)
        let other = StudySession(seed: 1, defaults: defaults())
        other.start(with: [wrong], plan: .daily)
        other.reveal(answer: "başka")
        other.gradePendingAnswer()
        #expect(wrong.logs?.map(\.correct) == [false])
    }

    @Test func closingAfterPeekOrBeforeRevealRecordsNothing() {
        let word = studied("stale", weak: true)
        let session = StudySession(seed: 1, defaults: defaults())
        session.start(with: [word], plan: .daily)
        session.gradePendingAnswer()
        session.reveal(answer: nil)
        session.gradePendingAnswer()
        #expect(word.reviewCount == 1)
        #expect(session.current === word)
    }

    // MARK: - Arka planda duran saat

    @Test func backgroundTimeIsNotCountedAsResponseTime() throws {
        let context = try makeContext()
        let word = Word(english: "stale", turkish: "eskimiş")
        context.insert(word)
        let start = Date.now
        let session = StudySession(seed: 1, defaults: defaults())
        session.start(with: [word], plan: .daily, now: start)
        session.pauseClock(now: start.addingTimeInterval(2))
        session.resumeClock(now: start.addingTimeInterval(302))
        session.reveal(answer: "eskimiş", now: start.addingTimeInterval(303))
        session.play(known: true, now: start.addingTimeInterval(304))
        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        #expect(logs.first?.responseTime == 3)
        #expect(logs.first?.grade == AnswerGrade.easy.rawValue)

        let round = GameRound(mode: .multipleChoice, seed: 1, defaults: defaults())
        round.start(with: [word], count: 1, now: start)
        round.pauseClock(now: start.addingTimeInterval(1))
        round.resumeClock(now: start.addingTimeInterval(101))
        #expect(round.shownAt == start.addingTimeInterval(100))
    }

    // MARK: - Geç gelen eski kayıt

    @Test func oldFormatWordIsMigratedBeforeItsFirstAnswer() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let word = Word(english: "quorum", turkish: "yeter sayı")
        word.box = 4
        word.dueDate = now
        word.reviewCount = 4
        word.correctCount = 4
        context.insert(word)

        let values = MemoryMigration.values(box: 4, dueDate: now, reviewCount: 4, correctCount: 4)
        ReviewRecorder.record(word, grade: .good, mode: .dailyReview, responseTime: 3, now: now)
        // Kutudan çıkan değerler taban olur, cevap onun üstüne oynatılır.
        #expect(word.baseStability == values.stability)
        #expect(word.baseDifficulty == values.difficulty)
        #expect(word.baseAnchorAt == values.lastReviewedAt)
        #expect(word.stability > values.stability)
        #expect(word.lastReviewedAt == DayBoundary.start(of: now))
    }
}

struct RepeatAnswerTests {
    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    /// Aynı gün iki kez bilinmeyip hemen sonra bilinen kelime: gün tek bir yanlış gibi değerlendirilir.
    @Test func sameDayAnswersAreJudgedTogether() throws {
        let context = try makeContext()
        let start = Date.now
        func word(_ english: String) -> Word {
            let word = Word(english: english, turkish: "eskimiş")
            word.reviewCount = 5
            word.correctCount = 5
            word.stability = 20
            word.difficulty = 5
            word.lastReviewedAt = start.addingTimeInterval(-40 * 86_400)
            word.dueDate = word.lastReviewedAt!.addingTimeInterval(20 * 86_400)
            context.insert(word)
            return word
        }
        let repeated = word("stale")
        let once = word("outdated")
        for (offset, grade) in [(0.0, AnswerGrade.again), (10, .again), (20, .good)] {
            ReviewRecorder.record(repeated, grade: grade, mode: .dailyReview, responseTime: 3, now: start.addingTimeInterval(offset))
        }
        ReviewRecorder.record(once, grade: .again, mode: .dailyReview, responseTime: 3, now: start)

        #expect(repeated.stability == once.stability)
        #expect(repeated.difficulty == once.difficulty)
        #expect(repeated.isLapsed)
        #expect(repeated.lastReviewedAt == DayBoundary.start(of: start))
        #expect(repeated.logs?.count == 3)
    }

    /// Sayaç iki cihazda aynı anda artınca biri kaybolsa da cevap kayıtları sayılır.
    @Test func countsNeverFallBelowLoggedAnswers() throws {
        let context = try makeContext()
        let word = Word(english: "quorum", turkish: "yeter sayı")
        context.insert(word)
        for correct in [true, true, false] {
            let log = ReviewLog(mode: "daily", correct: correct, grade: correct ? 3 : 1, responseTime: 2)
            context.insert(log)
            log.word = word
        }
        word.reviewCount = 1
        word.correctCount = 1
        #expect(word.answerCount == 3)
        #expect(word.correctAnswerCount == 2)

        // Kayıtlardan önceki (Leitner dönemi) cevaplar yalnızca sayaçta.
        word.reviewCount = 10
        word.correctCount = 7
        #expect(word.answerCount == 10)
        #expect(word.correctAnswerCount == 7)
    }
}

/// Uygulama cevap açıkken arka plana geçince (kapatılabilir) cevap kaydedilir, kart yerinde kalır.
struct CommitPendingAnswerTests {
    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    private func setUp() throws -> (ModelContext, Word, StudySession) {
        let context = try makeContext()
        let word = Word(english: "stale", turkish: "eskimiş")
        context.insert(word)
        let session = StudySession(seed: 1, defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        session.start(with: [word], plan: .daily)
        return (context, word, session)
    }

    @Test func commitRecordsOnceAndKeepsTheCard() throws {
        let (context, word, session) = try setUp()
        session.reveal(answer: "eskimiş")
        session.commitPendingAnswer()
        session.commitPendingAnswer()
        #expect(word.answerCount == 1)
        #expect(session.current === word)
        #expect(session.phase == .revealed(.correct))
        #expect(try context.fetch(FetchDescriptor<ReviewLog>()).count == 1)

        // Döndüğünde "Devam": yeniden kaydetmeden ilerler.
        session.play(known: true)
        #expect(session.current == nil)
        #expect(word.answerCount == 1)
        #expect(session.reviewedCount == 1)
        #expect(session.roundEntries.count == 1)
        #expect(try context.fetch(FetchDescriptor<ReviewLog>()).count == 1)
    }

    @Test func differentChoiceAfterCommitReplacesTheRecord() throws {
        let (context, word, session) = try setUp()
        // "Doğru Say" zor sayılır.
        let reference = Word(english: "stale", turkish: "eskimiş")
        context.insert(reference)
        ReviewRecorder.record(reference, grade: .hard, mode: .dailyReview, responseTime: 0)

        session.reveal(answer: "bayat")
        session.commitPendingAnswer()
        #expect(word.correctAnswerCount == 0)
        #expect(word.isLapsed)
        // Döndüğünde "Doğru Say": yanlış kaydı geri alınır, hafıza yeniden hesaplanır, doğru olarak yazılır.
        session.play(known: true)
        try context.save()
        #expect(word.logs?.map(\.correct) == [true])
        #expect(word.answerCount == 1)
        #expect(word.correctAnswerCount == 1)
        #expect(!word.isLapsed)
        #expect(word.stability == reference.stability)
        #expect(session.roundEntries.map(\.firstCorrect) == [true])
    }

    @Test func peekedAnswerIsNotCommitted() throws {
        let (context, word, session) = try setUp()
        session.reveal(answer: nil)
        session.commitPendingAnswer()
        #expect(word.reviewCount == 0)
        #expect(try context.fetch(FetchDescriptor<ReviewLog>()).isEmpty)
    }
}

/// Yanlış bilinen kelime zayıflar (turuncu, en fazla %50) ve ertesi güne kadar sorulmaz; ertesi gün
/// üretimde doğru bilinince toparlanır.
struct LapseTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    private func strongWord(in context: ModelContext) -> Word {
        let word = Word(english: "coalesce", turkish: "birleştirmek")
        context.insert(word)
        word.reviewCount = 3
        word.stability = 20
        word.difficulty = 5
        word.lastReviewedAt = now.addingTimeInterval(-2 * Memory.dayLength)
        word.dueDate = word.lastReviewedAt!.addingTimeInterval(20 * Memory.dayLength)
        return word
    }

    @Test func wrongAnswerMakesAStrongWordWeakRightAway() throws {
        let word = strongWord(in: try makeContext())
        #expect(word.memory(at: now)! > 0.97)
        ReviewRecorder.record(word, grade: .again, mode: .match, responseTime: 0, now: now)
        #expect(word.memory(at: now) == Memory.lapseMemory)
        #expect(word.isLapsed)
        #expect(!word.isLearned)
        // Bugün bir daha seçilmez, yarın 04:00'te sırası gelir.
        #expect(!word.isDue(at: now))
        #expect(word.isDue(at: DayBoundary.nextStart(after: now)))
    }

    @Test func newWordAnsweredWrongStartsWeak() throws {
        let context = try makeContext()
        let word = Word(english: "quorum", turkish: "yeter sayı")
        context.insert(word)
        ReviewRecorder.record(word, grade: .again, mode: .dailyReview, responseTime: 3, now: now)
        #expect(!word.isNew)
        #expect(word.memory(at: now) == Memory.lapseMemory)
        #expect(word.isLapsed)
    }

    @Test func correctAnswerNextDayClearsTheLapse() throws {
        let word = strongWord(in: try makeContext())
        ReviewRecorder.record(word, grade: .again, mode: .dailyReview, responseTime: 3, now: now)
        let later = now.addingTimeInterval(Memory.dayLength)
        ReviewRecorder.record(word, grade: .good, mode: .dailyReview, responseTime: 3, now: later)
        #expect(!word.isLapsed)
        #expect(word.memory(at: later)! > 0.98)
        #expect(!word.isDue(at: later))
        #expect(word.dueDate == DayBoundary.start(of: later).addingTimeInterval(word.stability * Memory.dayLength))
    }

    @Test func wrongThenRightLaterTheSameDayIsStillWrong() throws {
        let word = strongWord(in: try makeContext())
        ReviewRecorder.record(word, grade: .again, mode: .dailyReview, responseTime: 3, now: now)
        let stability = word.stability
        // İki saat sonra doğru: günde 1 doğru + 1 yanlış "bilemedin" sayılır.
        ReviewRecorder.record(word, grade: .good, mode: .dailyReview, responseTime: 3, now: now.addingTimeInterval(7_200))
        #expect(word.stability == stability)
        #expect(word.isLapsed)
        #expect(word.dueDate == DayBoundary.nextStart(after: now))
    }

    @Test func normalScheduleIsUnchanged() throws {
        let word = strongWord(in: try makeContext())
        #expect(word.memory(at: now) == Memory.retrievability(elapsedDays: 2, stability: 20))
    }
}

/// Tur ilerlemesi kelime sayısıyla gösterilir; bilinmeyen kelimenin tekrarı toplamı büyütmez.
struct RoundProgressTests {
    @Test func progressCountsWordsNotAnswers() {
        let words = (0..<4).map { index -> Word in
            let word = Word(english: "w\(index)", turkish: "anlam")
            word.reviewCount = 1
            word.stability = 1
            word.lastReviewedAt = Date.now.addingTimeInterval(-5 * 86_400)
            word.dueDate = word.lastReviewedAt!.addingTimeInterval(86_400)
            return word
        }
        let session = StudySession(seed: 1, defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        session.start(with: words, plan: .daily)
        #expect(session.wordCount == 4)
        session.play(known: false)
        #expect(session.wordCount == 4)
        #expect(session.finishedWordCount == 0)
        while session.current != nil { session.play(known: true) }
        #expect(session.finishedWordCount == 4)
        #expect(session.reviewedCount == 5)
    }
}
