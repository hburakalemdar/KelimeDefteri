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
        let others = ["a", "b", "c", "d", "e"].map { C(text: $0) }
        let result = ChoiceQuiz.options(answer: C(text: "doğru"), others: others, using: &generator)
        #expect(result.options.count == 4)
        #expect(result.options[result.correctIndex] == "doğru")
        #expect(Set(result.options).count == 4)
    }

    @Test func sameMeaningNeverAppearsAsWrongOption() {
        for seed in 0..<50 as Range<UInt64> {
            var generator = SeededGenerator(seed: seed)
            let others = [C(text: "Eskimiş"), C(text: "eskimis"), C(text: "verim"),
                          C(text: "yeter sayı"), C(text: "verim"), C(text: "silinme")]
            let result = ChoiceQuiz.options(answer: C(text: "eskimiş"), others: others, using: &generator)
            let folded = result.options.map(AnswerChecker.fold)
            #expect(folded.filter { $0 == "eskimis" }.count == 1)
            #expect(Set(folded).count == result.options.count)
            #expect(result.options.count == 4)
        }
    }

    @Test func fewerOptionsWhenNotEnoughDistinctMeanings() {
        var generator = SeededGenerator(seed: 2)
        let result = ChoiceQuiz.options(answer: C(text: "a"), others: [C(text: "b"), C(text: "A")], using: &generator)
        #expect(result.options.count == 2)
    }
}
