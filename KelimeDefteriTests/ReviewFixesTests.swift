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
        return word
    }

    // MARK: - Seçenekler

    @Test func wordSharingAnyMeaningIsNeverAWrongOption() {
        for seed in 0..<40 as Range<UInt64> {
            var generator = SeededGenerator(seed: seed)
            let others = [C(turkish: "eskimiş", source: ""), C(turkish: "verim", source: ""),
                          C(turkish: "yeter sayı", source: ""), C(turkish: "silinme", source: "")]
            let result = ChoiceQuiz.options(answer: C(turkish: "bayat, eskimiş", source: ""), others: others, using: &generator)
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
                session.grade(known: true)
            }
            #expect(asked.count == 20)
            #expect(asked.count { $0.english.hasPrefix("w") } == 18)
            #expect(asked.count { $0.english.hasPrefix("n") } == 2)
        }
    }

    // MARK: - Kapatınca cevap

    @Test func closingAfterRevealRecordsTheKnownResult() {
        let correct = studied("stale", weak: true)
        let session = StudySession(seed: 1, defaults: defaults())
        session.start(with: [correct], plan: .daily)
        session.reveal(answer: "anlam")
        session.gradePendingAnswer()
        #expect(correct.reviewCount == 2)
        #expect(correct.correctCount == 1)
        #expect(session.current == nil)

        let wrong = studied("quorum", weak: true)
        let other = StudySession(seed: 1, defaults: defaults())
        other.start(with: [wrong], plan: .daily)
        other.reveal(answer: "başka")
        other.gradePendingAnswer()
        #expect(wrong.reviewCount == 2)
        #expect(wrong.correctCount == 0)
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
        session.grade(known: true, now: start.addingTimeInterval(304))
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
        let expected = Memory.review(
            stability: values.stability, difficulty: values.difficulty, lastReviewedAt: values.lastReviewedAt,
            grade: .good, weight: GameMode.dailyReview.weight, now: now
        )
        ReviewRecorder.record(word, grade: .good, mode: .dailyReview, responseTime: 3, now: now)
        #expect(word.stability == expected.stability)
        #expect(word.difficulty == expected.difficulty)
        #expect(word.stability > values.stability)
    }
}
