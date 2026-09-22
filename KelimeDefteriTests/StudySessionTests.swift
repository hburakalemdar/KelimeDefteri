import Foundation
import SwiftData
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

    /// `sync` kelimeleri kimlikleriyle eşlediği için gerçek bir (bellek içi) depoya eklenmeleri gerekir.
    private func insert(_ words: Word...) throws -> ModelContext {
        let container = try ModelContainer(for: Word.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        words.forEach(context.insert)
        try context.save()
        return context
    }

    @Test func wordAddedDuringRoundJoinsTheQueue() throws {
        let first = word("first", dueIn: -1)
        let added = word("added", dueIn: -1)
        let context = try insert(first)
        let session = StudySession()
        session.start(with: [first], practiceAll: false)

        context.insert(added)
        try context.save()
        session.sync(with: [first, added])

        #expect(session.current?.english == "first")
        #expect(session.remaining == 1)
        session.grade(known: true)
        #expect(session.current?.english == "added")
    }

    @Test func finishedRoundContinuesWithNewDueWord() throws {
        let first = word("first", dueIn: -1)
        let added = word("added", dueIn: -1)
        let later = word("later", dueIn: 3)
        let context = try insert(first, later)
        let session = StudySession()
        session.start(with: [first, later], practiceAll: false)
        session.grade(known: true)
        #expect(session.current == nil)

        context.insert(added)
        try context.save()
        session.sync(with: [first, later, added])

        // "first" bilindiği için tarihi ileri alındı; "later" henüz zamanı gelmedi.
        #expect(session.current?.english == "added")
        #expect(session.remaining == 0)
    }

    @Test func syncDropsDeletedWords() throws {
        let first = word("first", dueIn: -2)
        let second = word("second", dueIn: -1)
        let context = try insert(first, second)
        let session = StudySession()
        session.start(with: [first, second], practiceAll: false)

        context.delete(first)
        try context.save()
        session.sync(with: [second])

        #expect(session.current?.english == "second")
        #expect(session.remaining == 0)
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
