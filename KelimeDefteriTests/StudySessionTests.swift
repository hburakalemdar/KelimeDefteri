import Foundation
import Testing
@testable import KelimeDefteri

struct StudySessionTests {
    private func word(_ english: String, dueIn days: Double) -> Word {
        let word = Word(english: english, turkish: "anlam")
        word.dueDate = Date.now.addingTimeInterval(days * 86_400)
        return word
    }

    @Test func dueModeAsksOnlyDueWordsOldestFirst() {
        let session = StudySession()
        let later = word("later", dueIn: 2)
        let older = word("older", dueIn: -3)
        let recent = word("recent", dueIn: -1)

        session.start(with: [later, recent, older], practiceAll: false)

        #expect(session.current?.english == "older")
        #expect(session.remaining == 1)
    }

    @Test func practiceAllIncludesNotYetDueWords() {
        let session = StudySession()
        session.start(with: [word("a", dueIn: 5), word("b", dueIn: 9)], practiceAll: true)
        #expect(session.current != nil)
        #expect(session.remaining == 1)
    }

    @Test func correctAnswerIsDetectedAndKnownWordLeavesQueue() {
        let session = StudySession()
        let target = word("stale", dueIn: -1)
        target.turkish = "eskimiş, güncel olmayan"
        session.start(with: [target], practiceAll: false)

        session.reveal(answer: "eskimis")
        #expect(session.phase == .revealed(.correct))

        session.grade(known: true)
        #expect(target.box == 1)
        #expect(target.correctCount == 1)
        #expect(session.current == nil)
    }

    @Test func unknownWordIsAskedAgainAtEndOfRound() {
        let session = StudySession()
        let first = word("first", dueIn: -2)
        let second = word("second", dueIn: -1)
        session.start(with: [first, second], practiceAll: false)

        session.reveal(answer: nil)
        #expect(session.phase == .revealed(.peeked))
        session.grade(known: false)

        #expect(session.current?.english == "second")
        session.grade(known: true)
        #expect(session.current?.english == "first")
    }
}
