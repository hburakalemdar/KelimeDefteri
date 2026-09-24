import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

struct ReviewRecorderTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    @Test func gradeFromRecallAnswer() {
        #expect(AnswerGrade.recall(verdict: .incorrect, known: false, responseTime: 3) == .again)
        #expect(AnswerGrade.recall(verdict: .peeked, known: false, responseTime: 3) == .again)
        #expect(AnswerGrade.recall(verdict: .peeked, known: true, responseTime: 3) == .hard)
        #expect(AnswerGrade.recall(verdict: .almost, known: true, responseTime: 1) == .hard)
        #expect(AnswerGrade.recall(verdict: .synonymOf("other"), known: true, responseTime: 1) == .hard)
        // "Doğru Say": kullanıcının kendi beyanı, zor sayılır.
        #expect(AnswerGrade.recall(verdict: .incorrect, known: true, responseTime: 20) == .hard)
        // Kısa kelime: 2,5 sn'den kısa easy, 8 sn'den kısa good.
        #expect(AnswerGrade.recall(verdict: .correct, known: true, responseTime: 2.4, letters: 4) == .easy)
        #expect(AnswerGrade.recall(verdict: .correct, known: true, responseTime: 2.5, letters: 4) == .good)
        #expect(AnswerGrade.recall(verdict: .correct, known: true, responseTime: 7.9, letters: 4) == .good)
        #expect(AnswerGrade.recall(verdict: .correct, known: true, responseTime: 8, letters: 4) == .hard)
        // Uzun kelime (20 harf): eşikler 10 sn ve 24 sn.
        #expect(AnswerGrade.recall(verdict: .correct, known: true, responseTime: 9, letters: 20) == .easy)
        #expect(AnswerGrade.recall(verdict: .correct, known: true, responseTime: 20, letters: 20) == .good)
        #expect(AnswerGrade.recall(verdict: .correct, known: true, responseTime: 25, letters: 20) == .hard)
        #expect(AnswerGrade.recognition(correct: true) == .good)
        #expect(AnswerGrade.recognition(correct: false) == .again)
    }

    @Test func recordWritesLogAndReplaysTheWord() throws {
        let context = try makeContext()
        let word = Word(english: "quorum", turkish: "yeter sayı")
        context.insert(word)

        let log = ReviewRecorder.record(word, grade: .good, mode: .dailyReview, responseTime: 5, now: now)
        let today = DayBoundary.start(of: now)
        #expect(word.baseAt == .distantPast)
        #expect(word.stability == 3)
        #expect(word.difficulty == 5)
        #expect(word.lastReviewedAt == today)
        #expect(word.dueDate == today.addingTimeInterval(3 * Memory.dayLength))
        #expect(log?.word === word)
        #expect(log?.mode == GameMode.dailyReview.rawValue)
        // Sayaçlar artırılmaz; cevap sayısı kayıtlardan okunur.
        #expect(word.reviewCount == 0)
        #expect(word.answerCount == 1)
        #expect(word.correctAnswerCount == 1)

        let later = now.addingTimeInterval(3 * Memory.dayLength)
        ReviewRecorder.record(word, grade: .again, mode: .multipleChoice, responseTime: 2, now: later)
        #expect(word.isLapsed)
        #expect(word.lapsedAt == DayBoundary.start(of: later))
        #expect(word.dueDate == DayBoundary.nextStart(after: later))
        #expect(!word.isDue(at: later))
        #expect(word.isDue(at: DayBoundary.nextStart(after: later)))
        try context.save()
        #expect(word.logs?.count == 2)
        #expect(word.answerCount == 2)
        #expect(word.correctAnswerCount == 1)
    }

    @Test func undoRestoresThePreviousState() throws {
        let context = try makeContext()
        let word = Word(english: "quorum", turkish: "yeter sayı")
        context.insert(word)
        ReviewRecorder.record(word, grade: .good, mode: .dailyReview, responseTime: 5, now: now)
        let snapshot = (word.stability, word.difficulty, word.dueDate, word.lastReviewedAt, word.lapsedAt)

        let later = now.addingTimeInterval(3600)
        let wrong = try #require(ReviewRecorder.record(word, grade: .again, mode: .dailyReview, responseTime: 5, now: later))
        #expect(word.isLapsed)
        ReviewRecorder.undo(wrong, now: later)
        #expect(word.stability == snapshot.0)
        #expect(word.difficulty == snapshot.1)
        #expect(word.dueDate == snapshot.2)
        #expect(word.lastReviewedAt == snapshot.3)
        #expect(word.lapsedAt == snapshot.4)
        #expect(word.answerCount == 1)

        // İlk cevabı da geri alınan kelime yeniden yeni olur.
        let first = try #require(word.logs?.first)
        ReviewRecorder.undo(first, now: later)
        #expect(word.isNew)
        #expect(word.answerCount == 0)
    }

    @Test func memoryTextAndBuckets() {
        #expect(MemoryStats.text(nil) == "Yeni")
        #expect(MemoryStats.text(0.62) == "%62")
        #expect(MemoryStats.text(0.899) == "%89")
        #expect(MemoryStats.text(1) == "%100")
        #expect(MemoryStats.Level(0.9) == .strong)
        #expect(MemoryStats.Level(0.89) == .fading)
        #expect(MemoryStats.Level(0.7) == .fading)
        #expect(MemoryStats.Level(0.59) == .weak)
        #expect(MemoryStats.Bucket(nil) == .new)
        #expect(MemoryStats.Bucket(0.49) == .below50)
        #expect(MemoryStats.Bucket(0.5) == .below70)
        #expect(MemoryStats.Bucket(0.89) == .below90)
        #expect(MemoryStats.Bucket(0.9) == .below95)
        #expect(MemoryStats.Bucket(0.95) == .top)
        #expect(MemoryStats.average([nil, 0.5, 1]) == 0.75)
        #expect(MemoryStats.average([nil]) == nil)
    }
}
