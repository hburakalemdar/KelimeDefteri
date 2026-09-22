import Testing
@testable import KelimeDefteri

struct AnswerCheckerTests {
    @Test func exactMatch() {
        #expect(AnswerChecker.isCorrect("verim", expected: "verim"))
    }

    @Test func anyOfCommaSeparatedMeanings() {
        #expect(AnswerChecker.isCorrect("verim", expected: "iş hacmi, verim"))
        #expect(AnswerChecker.isCorrect("iş hacmi", expected: "iş hacmi; verim"))
    }

    @Test func ignoresCaseAndTurkishCharacters() {
        #expect(AnswerChecker.isCorrect("IS HACMI", expected: "iş hacmi"))
        #expect(AnswerChecker.isCorrect("isik", expected: "ışık"))
        #expect(AnswerChecker.isCorrect("Eskimiş!", expected: "eskimis"))
    }

    @Test func acceptsLongEnoughPartialAnswer() {
        #expect(AnswerChecker.isCorrect("değişmeyen", expected: "etkisi değişmeyen"))
    }

    @Test func acceptsWordStemAndExtraWords() {
        #expect(AnswerChecker.isCorrect("kaydet", expected: "kaydetmek"))
        #expect(AnswerChecker.isCorrect("yüksek verim", expected: "verim"))
    }

    @Test func rejectsPartialAnswerWithOppositeMeaning() {
        #expect(!AnswerChecker.isCorrect("mümkün", expected: "mümkün değil, uygulanamaz"))
        #expect(!AnswerChecker.isCorrect("güncel", expected: "güncel olmayan"))
        #expect(!AnswerChecker.isCorrect("kayıt", expected: "kayıtsız"))
        #expect(!AnswerChecker.isCorrect("etkisi", expected: "etkisi değişmeyen"))
        #expect(!AnswerChecker.isCorrect("verim değil", expected: "verim"))
        #expect(!AnswerChecker.isCorrect("kaydet", expected: "kaydetmemek"))
    }

    @Test func rejectsShortPartialAnswer() {
        #expect(!AnswerChecker.isCorrect("iş", expected: "iş hacmi"))
    }

    @Test func rejectsWrongOrEmptyAnswer() {
        #expect(!AnswerChecker.isCorrect("hız", expected: "iş hacmi, verim"))
        #expect(!AnswerChecker.isCorrect("   ", expected: "verim"))
    }
}
