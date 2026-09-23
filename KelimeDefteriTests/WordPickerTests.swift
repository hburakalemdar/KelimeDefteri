import Foundation
import Testing
@testable import KelimeDefteri

struct WordPickerTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func candidates(_ count: Int, weight: Double = 1) -> [WordPicker.Candidate<Int>] {
        (0..<count).map { WordPicker.Candidate(id: $0, weight: weight) }
    }

    @Test func sameSeedGivesSameOrder() {
        var a = SeededGenerator(seed: 7), b = SeededGenerator(seed: 7)
        let first = WordPicker.order(candidates(20), using: &a)
        let second = WordPicker.order(candidates(20), using: &b)
        #expect(first == second)
        #expect(Set(first) == Set(0..<20))
    }

    @Test func orderHasNoRepeats() {
        var generator = SeededGenerator(seed: 3)
        let ids = WordPicker.order(candidates(50), using: &generator)
        #expect(ids.count == Set(ids).count)
        for index in ids.indices.dropFirst() {
            #expect(ids[index] != ids[index - 1])
        }
    }

    @Test func heavierWordsTendToComeFirst() {
        var generator = SeededGenerator(seed: 11)
        var heavyFirst = 0
        for _ in 0..<500 {
            let pool = [
                WordPicker.Candidate(id: "light", weight: 0.1),
                WordPicker.Candidate(id: "heavy", weight: 1.1),
            ]
            if WordPicker.order(pool, using: &generator).first == "heavy" { heavyFirst += 1 }
        }
        // Beklenen oran 1.1 / 1.2 ≈ %92.
        #expect(heavyFirst > 400)
        #expect(heavyFirst < 500)
    }

    @Test func firstDiffersFromPreviousRoundsFirst() {
        var generator = SeededGenerator(seed: 5)
        var previous: Int?
        for _ in 0..<50 {
            let ids = WordPicker.order(candidates(4), avoidingFirst: previous, using: &generator)
            #expect(ids.first != previous)
            #expect(ids.count == 4)
            previous = ids.first
        }
    }

    @Test func singleWordDeckStillStarts() {
        var generator = SeededGenerator(seed: 1)
        #expect(WordPicker.order(candidates(1), avoidingFirst: 0, using: &generator) == [0])
    }

    @Test func limitAndNewWordCap() {
        var generator = SeededGenerator(seed: 9)
        let pool = (0..<30).map { WordPicker.Candidate(id: $0, weight: 1, isNew: $0 < 15) }
        let ids = WordPicker.order(pool, limit: 20, maxNew: 5, using: &generator)
        #expect(ids.count == 20)
        #expect(ids.filter { $0 < 15 }.count == 5)
    }

    @Test func delayWeightGrowsWithOverdueDays() {
        let day = 86_400.0
        #expect(WordPicker.delayWeight(dueDate: now, isNew: true, now: now) == 1)
        #expect(WordPicker.delayWeight(dueDate: now.addingTimeInterval(day), isNew: false, now: now) == 0.1)
        #expect(abs(WordPicker.delayWeight(dueDate: now.addingTimeInterval(-3.5 * day), isNew: false, now: now) - 0.6) < 1e-9)
        #expect(WordPicker.delayWeight(dueDate: now.addingTimeInterval(-30 * day), isNew: false, now: now) == 1.1)
    }

    @Test func missedWordReturnsAfterTwoOthers() {
        #expect(WordPicker.reinsertionIndex(queueCount: 10) == 2)
        #expect(WordPicker.reinsertionIndex(queueCount: 1) == 1)
        #expect(WordPicker.reinsertionIndex(queueCount: 0) == 0)
    }
}
