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

    @Test func phraseWordsTakeSuffixes() {
        let depends = ClozeSentence(sentence: "It depends on the cache.", word: "depend on")
        #expect(depends?.match == "depends on")
        #expect(depends?.after == " the cache.")
        #expect(ClozeSentence(sentence: "She raised an issue yesterday.", word: "raise an issue")?.match
            == "raised an issue")
        let last = ClozeSentence(sentence: "He raises issues often.", word: "raise issue")
        #expect(last?.match == "raises issue")
        #expect(last?.after == "s often.")
        #expect(ClozeSentence(sentence: "It  Depends   on cafés.", word: "depend on")?.match == "Depends   on")
        #expect(ClozeSentence(sentence: "It stopped in time.", word: "stop in")?.match == "stopped in")
        // Birden çok geçişin hepsi boşaltılır.
        #expect(ClozeSentence(sentence: "A depends on B, B depended on C.", word: "depend on")?.matchCount == 2)
    }

    @Test func phraseShortWordsAndOtherWordsDoNotMatch() {
        #expect(ClozeSentence(sentence: "They depend only on X.", word: "depend on") == nil)
        #expect(ClozeSentence(sentence: "Raise and issue a refund.", word: "raise an issue") == nil)
        #expect(ClozeSentence(sentence: "It will rain on Monday.", word: "depend on") == nil)
        #expect(ClozeSentence(sentence: "We rely on it.", word: "lie on") == nil)
        #expect(ClozeSentence(sentence: "Independent on paper.", word: "depend on") == nil)
        // Sonraki geçiş bulunur.
        #expect(ClozeSentence(sentence: "Depend only on me; depend on you.", word: "depend on")?.before
            == "Depend only on me; ")
    }
}
