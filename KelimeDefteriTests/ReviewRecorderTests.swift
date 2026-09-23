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
        #expect(AnswerGrade.recall(verdict: .correct, known: true, responseTime: 13) == .hard)
        #expect(AnswerGrade.recall(verdict: .correct, known: true, responseTime: 12) == .good)
        #expect(AnswerGrade.recall(verdict: .correct, known: true, responseTime: 4.5) == .good)
        #expect(AnswerGrade.recall(verdict: .correct, known: true, responseTime: 4) == .easy)
        #expect(AnswerGrade.recall(verdict: .incorrect, known: true, responseTime: 20) == .good)
        #expect(AnswerGrade.recognition(correct: true) == .good)
        #expect(AnswerGrade.recognition(correct: false) == .again)
    }

    @Test func recordAppliesEngineAndWritesLog() throws {
        let context = try makeContext()
        let word = Word(english: "quorum", turkish: "yeter sayı")
        context.insert(word)

        let log = ReviewRecorder.record(word, grade: .good, mode: .dailyReview, responseTime: 5, now: now)
        #expect(word.stability == 3)
        #expect(word.difficulty == 5)
        #expect(word.dueDate == now.addingTimeInterval(3 * Memory.dayLength))
        #expect(word.lastReviewedAt == now)
        #expect(word.reviewCount == 1)
        #expect(word.correctCount == 1)
        #expect(log?.word === word)
        #expect(log?.mode == GameMode.dailyReview.rawValue)

        let later = now.addingTimeInterval(3 * Memory.dayLength)
        ReviewRecorder.record(word, grade: .again, mode: .multipleChoice, responseTime: 2, now: later)
        #expect(word.stability == 1.5)
        #expect(word.reviewCount == 2)
        #expect(word.correctCount == 1)
        try context.save()
        #expect(word.logs?.count == 2)
        #expect(word.logs?.filter(\.correct).count == 1)
    }

    @Test func memoryTextAndBuckets() {
        #expect(MemoryStats.text(nil) == "Yeni")
        #expect(MemoryStats.text(0.62) == "%62")
        #expect(MemoryStats.text(0.899) == "%89")
        #expect(MemoryStats.text(1) == "%100")
        #expect(MemoryStats.Level(0.85) == .strong)
        #expect(MemoryStats.Level(0.7) == .fading)
        #expect(MemoryStats.Level(0.59) == .weak)
        #expect(MemoryStats.Bucket(nil) == .new)
        #expect(MemoryStats.Bucket(0.49) == .below50)
        #expect(MemoryStats.Bucket(0.5) == .below70)
        #expect(MemoryStats.Bucket(0.84) == .below85)
        #expect(MemoryStats.Bucket(0.9) == .below95)
        #expect(MemoryStats.Bucket(0.95) == .top)
        #expect(MemoryStats.average([nil, 0.5, 1]) == 0.75)
        #expect(MemoryStats.average([nil]) == nil)
    }
}
