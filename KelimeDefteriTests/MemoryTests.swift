import Foundation
import Testing
@testable import KelimeDefteri

struct MemoryTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * Memory.dayLength) }

    private func review(
        _ grade: AnswerGrade, stability: Double = 5, difficulty: Double = 5,
        elapsedDays: Double = 5, weight: Double = 1
    ) -> Memory.Result {
        Memory.review(
            stability: stability, difficulty: difficulty, lastReviewedAt: daysAgo(elapsedDays),
            grade: grade, weight: weight, now: now
        )
    }

    @Test(arguments: [0.5, 3, 21, 100])
    func retrievabilityIsNinetyPercentAfterStabilityDays(stability: Double) {
        #expect(abs(Memory.retrievability(elapsedDays: stability, stability: stability) - 0.9) < 1e-12)
        #expect(Memory.retrievability(elapsedDays: 0, stability: stability) == 1)
    }

    @Test func firstAnswerSetsInitialValues() {
        let expected: [(AnswerGrade, Double, Double)] = [(.again, 0.4, 7), (.hard, 1.2, 6), (.good, 3, 5), (.easy, 8, 3.5)]
        for (grade, stability, difficulty) in expected {
            let result = Memory.review(stability: 0, difficulty: 5, lastReviewedAt: nil, grade: grade, weight: 1, now: now)
            #expect(abs(result.stability - stability) < 1e-12)
            #expect(result.difficulty == difficulty)
            #expect(result.due == now.addingTimeInterval(stability * Memory.dayLength))
        }
        // Tanıma oyunu ilk cevapta da daha az verir ama 0.3'ün altına inmez.
        let recognition = Memory.review(stability: 0, difficulty: 5, lastReviewedAt: nil, grade: .again, weight: 0.6, now: now)
        #expect(recognition.stability == 0.3)
    }

    @Test func correctAnswerGrowsStabilityEasyMostHardLeast() {
        let hard = review(.hard).stability
        let good = review(.good).stability
        let easy = review(.easy).stability
        #expect(hard > 5)
        #expect(easy > good)
        #expect(good > hard)
    }

    @Test func sameDayReviewBarelyGrows() {
        let sameDay = review(.good, stability: 10, elapsedDays: 0.01).stability
        let onTime = review(.good, stability: 10, elapsedDays: 10).stability
        #expect(sameDay < 10.1)
        #expect(onTime > 15)
    }

    @Test func wrongAnswerShrinksButDoesNotReset() {
        #expect(abs(review(.again, stability: 20).stability - 7) < 1e-9)
        #expect(review(.again, stability: 20, weight: 0.6).stability == 10)
        #expect(review(.again, stability: 0.5).stability == 0.3)
    }

    @Test func recognitionGrowsLessThanRecall() {
        let recall = review(.good, weight: GameMode.dailyReview.weight).stability
        let letters = review(.good, weight: GameMode.letters.weight).stability
        let recognition = review(.good, weight: GameMode.multipleChoice.weight).stability
        #expect(recall > letters)
        #expect(letters > recognition)
        #expect(recognition > 5)
    }

    @Test func difficultyStaysInRange() {
        var difficulty = 5.0
        for _ in 0..<100 { difficulty = Memory.nextDifficulty(difficulty, grade: .again) }
        #expect(difficulty <= 10)
        #expect(difficulty > 9)
        for _ in 0..<100 { difficulty = Memory.nextDifficulty(difficulty, grade: .easy) }
        #expect(difficulty >= 1)
        #expect(difficulty < 2)
        // Bir adım: 5 + 1 = 6, sonra 5'e %5 yaklaşır → 5.95.
        #expect(abs(Memory.nextDifficulty(5, grade: .again) - 5.95) < 1e-12)
    }

    @Test func wordMemoryWeakAndLearned() {
        let word = Word(english: "stale", turkish: "eskimiş")
        #expect(word.memory(at: now) == nil)
        #expect(word.isWeak(at: now))

        word.stability = 10
        word.lastReviewedAt = daysAgo(2)
        #expect(word.memory(at: now)! > 0.9)
        #expect(!word.isWeak(at: now))
        word.lastReviewedAt = daysAgo(15)
        #expect(word.isWeak(at: now))

        #expect(!word.isLearned)
        word.stability = 21
        #expect(word.isLearned)
    }
}
