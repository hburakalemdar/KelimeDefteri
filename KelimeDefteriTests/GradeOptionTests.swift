import Testing
@testable import KelimeDefteri

struct GradeOptionTests {
    @Test func correctAnswerOnlyContinuesAsKnown() {
        let options = StudySession.Verdict.correct.gradeOptions
        #expect(options.count == 1)
        #expect(options[0].known)
        #expect(options[0].isPrimary)
    }

    @Test func incorrectAnswerContinuesAsUnknownButCanBeOverridden() {
        let options = StudySession.Verdict.incorrect.gradeOptions
        #expect(options.filter(\.isPrimary).map(\.known) == [false])
        #expect(options.contains { $0.known && !$0.isPrimary })
    }

    @Test func peekAsksTheUserWithoutSuggesting() {
        let options = StudySession.Verdict.peeked.gradeOptions
        #expect(Set(options.map(\.known)) == [true, false])
        #expect(options.allSatisfy { !$0.isPrimary })
    }
}
