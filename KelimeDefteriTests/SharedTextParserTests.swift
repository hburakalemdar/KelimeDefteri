import Testing
@testable import KelimeDefteri

struct SharedTextParserTests {
    @Test func appleBooksExcerptKeepsOnlyTheSentence() {
        let shared = """
        “A follower replica may return stale data.”

        Excerpt From
        Designing Data-Intensive Applications
        Martin Kleppmann
        This material may be protected by copyright.
        """
        let draft = SharedTextParser.draft(from: shared)
        #expect(draft.example == "A follower replica may return stale data.")
        #expect(draft.english.isEmpty)
    }

    @Test func singleWordBecomesTheWord() {
        let draft = SharedTextParser.draft(from: "  “Idempotent” ")
        #expect(draft.english == "idempotent")
        #expect(draft.example.isEmpty)
    }

    @Test func plainSentenceWithoutSource() {
        let draft = SharedTextParser.draft(from: "Retries are safe only\nif the operation is idempotent.")
        #expect(draft.example == "Retries are safe only if the operation is idempotent.")
    }

    @Test func markerOnSameLineIsDropped() {
        let draft = SharedTextParser.draft(from: "\"Throughput matters.\"\n\nAlıntı: Sistem Tasarımı")
        #expect(draft.example == "Throughput matters.")
    }

    @Test func wordsAreUniqueOrderedAndKeepContractions() {
        let words = SharedTextParser.words(in: "The read-only replica doesn't lag; the replica is read-only.")
        #expect(words == ["The", "read-only", "replica", "doesn't", "lag", "is"])
    }

    @Test func shortSelectionBecomesPhrase() {
        #expect(SharedTextParser.draft(from: "“Carry out”").english == "carry out")
        #expect(SharedTextParser.draft(from: "on the other hand").english == "on the other hand")
    }

    @Test func shortSentenceStaysSentence() {
        let draft = SharedTextParser.draft(from: "Latency matters.")
        #expect(draft.english.isEmpty)
        #expect(draft.example == "Latency matters.")
    }

    @Test func tokensKeepOrderAndRepeats() {
        #expect(SharedTextParser.tokens(in: "the cache, the disk") == ["the", "cache", "the", "disk"])
    }

    @Test func secondTapSelectsPhraseInEitherDirection() {
        let first = SharedTextParser.select(3, current: nil)
        #expect(first == 3...3)
        #expect(SharedTextParser.select(1, current: first) == 1...3)
        #expect(SharedTextParser.select(5, current: first) == 3...5)
    }

    @Test func tappingSelectedWordClearsAndPhraseRestarts() {
        #expect(SharedTextParser.select(2, current: 2...2) == nil)
        #expect(SharedTextParser.select(4, current: 1...3) == 4...4)
    }

    @Test func tooLongPhraseRestartsSelection() {
        #expect(SharedTextParser.select(9, current: 0...0) == 9...9)
    }

    @Test func phraseJoinsSelectedWords() {
        let tokens = SharedTextParser.tokens(in: "We must Take Into Account the cost.")
        #expect(SharedTextParser.phrase(tokens, 2...4) == "take into account")
    }
}
