import Foundation
import Testing
@testable import KelimeDefteri

struct ChoiceQuizTests {
    private typealias C = ChoiceQuiz.Candidate

    @Test func firstMeaningKeepsOriginalSpelling() {
        #expect(ChoiceQuiz.firstMeaning("eskimiş, güncel olmayan") == "eskimiş")
        #expect(ChoiceQuiz.firstMeaning("  iş hacmi ; verim") == "iş hacmi")
        #expect(ChoiceQuiz.firstMeaning("yeter sayı") == "yeter sayı")
    }

    @Test func fourOptionsWithCorrectOneInPlace() {
        var generator = SeededGenerator(seed: 1)
        let others = ["a", "b", "c", "d", "e"].map { C(text: $0, source: "") }
        let result = ChoiceQuiz.options(answer: C(text: "doğru", source: ""), others: others, using: &generator)
        #expect(result.options.count == 4)
        #expect(result.options[result.correctIndex] == "doğru")
        #expect(Set(result.options).count == 4)
    }

    @Test func sameMeaningNeverAppearsAsWrongOption() {
        for seed in 0..<50 as Range<UInt64> {
            var generator = SeededGenerator(seed: seed)
            let others = [C(text: "Eskimiş", source: ""), C(text: "eskimis", source: ""), C(text: "verim", source: ""),
                          C(text: "yeter sayı", source: ""), C(text: "verim", source: ""), C(text: "silinme", source: "")]
            let result = ChoiceQuiz.options(answer: C(text: "eskimiş", source: ""), others: others, using: &generator)
            let folded = result.options.map(AnswerChecker.fold)
            #expect(folded.filter { $0 == "eskimis" }.count == 1)
            #expect(Set(folded).count == result.options.count)
            #expect(result.options.count == 4)
        }
    }

    @Test func sameSourceIsPreferred() {
        for seed in 0..<30 as Range<UInt64> {
            var generator = SeededGenerator(seed: seed)
            let others = [C(text: "x1", source: "DDIA"), C(text: "x2", source: "DDIA"), C(text: "x3", source: "DDIA"),
                          C(text: "y1", source: "Other"), C(text: "y2", source: "Other")]
            let result = ChoiceQuiz.options(answer: C(text: "doğru", source: "DDIA"), others: others, using: &generator)
            #expect(Set(result.options) == ["doğru", "x1", "x2", "x3"])
        }
    }

    @Test func fewerOptionsWhenNotEnoughDistinctMeanings() {
        var generator = SeededGenerator(seed: 2)
        let result = ChoiceQuiz.options(answer: C(text: "a", source: ""), others: [C(text: "b", source: ""), C(text: "A", source: "")], using: &generator)
        #expect(result.options.count == 2)
    }
}
