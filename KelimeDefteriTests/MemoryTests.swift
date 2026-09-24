import Foundation
import Testing
@testable import KelimeDefteri

/// Hafıza formülleri ve `Word` üzerindeki okuyucular (`isLapsed`, `memory(at:)`, `isLearned`, `isDue`).
/// Günlerin oynatılması `MotorReplayTests`te.
struct MemoryTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * Memory.dayLength) }

    @Test(arguments: [0.5, 3, 21, 100])
    func retrievabilityIsNinetyPercentAfterStabilityDays(stability: Double) {
        #expect(abs(Memory.retrievability(elapsedDays: stability, stability: stability) - 0.9) < 1e-12)
        #expect(Memory.retrievability(elapsedDays: 0, stability: stability) == 1)
    }

    @Test func difficultyStaysInRange() {
        var difficulty = 5.0
        for _ in 0..<100 { difficulty = Memory.nextDifficulty(difficulty, grade: .again) }
        #expect(difficulty <= 10)
        #expect(difficulty > 9)
        for _ in 0..<100 { difficulty = Memory.nextDifficulty(difficulty, grade: .easy) }
        #expect(difficulty >= 1)
        #expect(difficulty < 2)
        // Bir adım: 5 + 1 = 6, sonra 5'e %15 yaklaşır → 5.85; "good" zorluğu değiştirmez.
        #expect(abs(Memory.nextDifficulty(5, grade: .again) - 5.85) < 1e-12)
        #expect(Memory.nextDifficulty(5, grade: .good) == 5)
    }

    @Test func wordReaders() {
        let word = Word(english: "stale", turkish: "eskimiş")
        #expect(word.memory(at: now) == nil)
        #expect(word.isDue(at: now))
        #expect(!word.isLapsed)

        word.stability = 10
        word.lastReviewedAt = daysAgo(2)
        word.dueDate = daysAgo(2).addingTimeInterval(10 * Memory.dayLength)
        #expect(word.memory(at: now)! > 0.9)
        #expect(!word.isDue(at: now))
        #expect(word.isDue(at: now.addingTimeInterval(8 * Memory.dayLength)))

        // Zayıf kelime: hafıza en fazla %50, öğrenilmiş sayılmaz; seçim yine vadeye bakar.
        word.stability = 30
        #expect(word.isLearned)
        word.lapsedAt = daysAgo(2)
        #expect(word.isLapsed)
        #expect(word.memory(at: now) == Memory.lapseMemory)
        #expect(!word.isLearned)
        #expect(!word.isDue(at: now))
    }
}
