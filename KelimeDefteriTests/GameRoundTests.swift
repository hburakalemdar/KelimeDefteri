import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

struct GameRoundTests {
    private func makeRound(_ mode: GameMode = .multipleChoice) -> GameRound {
        GameRound(mode: mode, seed: 4, defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    }

    @Test func picksRequestedCountWithoutRepeats() {
        let words = (0..<15).map { Word(english: "w\($0)", turkish: "anlam \($0)") }
        let round = makeRound()
        round.start(with: words, count: 10)
        #expect(round.count == 10)
        #expect(Set(round.words.map(\.english)).count == 10)
        let small = makeRound()
        small.start(with: Array(words.prefix(4)), count: 10)
        #expect(small.count == 4)
    }

    @Test func recordsGradeWithGameWeightAndKeepsFirstAnswer() throws {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let word = Word(english: "quorum", turkish: "yeter sayı")
        context.insert(word)
        let round = makeRound()
        let start = Date.now
        round.start(with: [word], count: 10, now: start)
        round.record(word, grade: .again, now: start.addingTimeInterval(3))
        round.record(word, grade: .good, now: start.addingTimeInterval(9))
        round.advance()

        #expect(round.isFinished)
        #expect(round.entries.count == 1)
        #expect(round.entries.first?.firstCorrect == false)
        // İlk cevap (again, ağırlık 0.6): 0.4 × 0.6 = 0.24 → en az 0.3.
        let logs = try context.fetch(FetchDescriptor<ReviewLog>(sortBy: [SortDescriptor(\.date)]))
        #expect(logs.map(\.mode) == ["choice", "choice"])
        #expect(logs.first?.responseTime == 3)
        #expect(word.reviewCount == 2)
    }
}
