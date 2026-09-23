import Foundation
import Testing
@testable import KelimeDefteri

struct ClozeSentenceTests {
    @Test func splitsAroundWordIgnoringCase() {
        let cloze = ClozeSentence(sentence: "Retries are safe only if the operation is Idempotent.", word: "idempotent")
        #expect(cloze?.before == "Retries are safe only if the operation is ")
        #expect(cloze?.match == "Idempotent")
        #expect(cloze?.after == ".")
    }

    @Test func allowsSuffixButNotPrefix() {
        let plural = ClozeSentence(sentence: "Deletions are recorded as tombstones.", word: "tombstone")
        #expect(plural?.match == "tombstone")
        #expect(plural?.after == "s.")
        #expect(ClozeSentence(sentence: "Let's start again.", word: "art") == nil)
        // İlk geçiş kelimenin içindeyse sonraki tam geçiş bulunur.
        #expect(ClozeSentence(sentence: "Restart the art show.", word: "art")?.before == "Restart the ")
    }

    @Test func phrasesAndDiacritics() {
        #expect(ClozeSentence(sentence: "Reads rely on eventual consistency.", word: "eventual consistency")?.after == ".")
        #expect(ClozeSentence(sentence: "A café opened.", word: "cafe")?.match == "café")
        #expect(ClozeSentence(sentence: "", word: "x") == nil)
    }
}
