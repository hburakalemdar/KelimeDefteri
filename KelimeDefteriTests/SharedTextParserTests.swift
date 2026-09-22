import Testing
@testable import KelimeDefteri

struct SharedTextParserTests {
    @Test func appleBooksExcerptGivesSentenceAndBookTitle() {
        let shared = """
        “A follower replica may return stale data.”

        Excerpt From
        Designing Data-Intensive Applications
        Martin Kleppmann
        This material may be protected by copyright.
        """
        let draft = SharedTextParser.draft(from: shared)
        #expect(draft.example == "A follower replica may return stale data.")
        #expect(draft.source == "Designing Data-Intensive Applications")
        #expect(draft.english.isEmpty)
    }

    @Test func singleWordBecomesTheWord() {
        let draft = SharedTextParser.draft(from: "  “Idempotent” ")
        #expect(draft.english == "idempotent")
        #expect(draft.example.isEmpty)
        #expect(draft.source == nil)
    }

    @Test func plainSentenceWithoutSource() {
        let draft = SharedTextParser.draft(from: "Retries are safe only\nif the operation is idempotent.")
        #expect(draft.example == "Retries are safe only if the operation is idempotent.")
        #expect(draft.source == nil)
    }

    @Test func sourceOnSameLineAsMarker() {
        let draft = SharedTextParser.draft(from: "\"Throughput matters.\"\n\nAlıntı: Sistem Tasarımı")
        #expect(draft.source == "Sistem Tasarımı")
    }

    @Test func wordsAreUniqueOrderedAndKeepContractions() {
        let words = SharedTextParser.words(in: "The read-only replica doesn't lag; the replica is read-only.")
        #expect(words == ["The", "read-only", "replica", "doesn't", "lag", "is"])
    }
}
