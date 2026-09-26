import Foundation
import Testing
@testable import KelimeDefteri

struct WordMatcherTests {
    @Test func sameIgnoresCaseAccentsAndPunctuation() {
        #expect(WordMatcher.isSame("Take into account", "take  into account."))
        #expect(!WordMatcher.isSame("take", "take into account"))
        #expect(!WordMatcher.isSame("", ""))
    }

    @Test func wordAndItsPhraseAreRelatedBothWays() {
        #expect(WordMatcher.isRelated("take", "take into account"))
        #expect(WordMatcher.isRelated("take into account", "account"))
        #expect(WordMatcher.isRelated("into account", "take into account"))
    }

    @Test func partialWordsAndSameEntryAreNotRelated() {
        #expect(!WordMatcher.isRelated("art", "start"))
        #expect(!WordMatcher.isRelated("take account", "take into account"))
        #expect(!WordMatcher.isRelated("stale", "Stale"))
    }

    @Test func mergeAddsOnlyNewMeanings() {
        #expect(WordMatcher.mergedMeanings(existing: "eskimiş, bayat", adding: "Eskimiş, güncel olmayan") == "eskimiş, bayat, güncel olmayan")
        #expect(WordMatcher.mergedMeanings(existing: "eskimiş", adding: "eskimis") == "eskimiş")
        #expect(WordMatcher.mergedMeanings(existing: "", adding: "bayat") == "bayat")
    }

    @Test func newMeaningsAreThoseNotInRecord() {
        let word = Word(english: "stale", turkish: "eskimiş, bayat")
        #expect(word.newMeanings(in: "Eskimiş, güncel olmayan, bayat") == ["güncel olmayan"])
        #expect(word.newMeanings(in: "") == [])
    }
}
