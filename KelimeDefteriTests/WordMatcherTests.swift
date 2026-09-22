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

    @Test func absorbAddsInfoAndKeepsProgress() {
        let word = Word(english: "stale", turkish: "eskimiş", example: "Old cache.")
        word.box = 3
        let due = Date.now.addingTimeInterval(86_400 * 5)
        word.dueDate = due

        #expect(word.wouldAbsorb(turkish: "bayat", definition: "", example: "", source: ""))
        #expect(!word.wouldAbsorb(turkish: "Eskimiş", definition: "", example: "New sentence.", source: ""))

        word.absorb(turkish: "bayat", definition: "not fresh", example: "New sentence.", source: "DDIA")
        #expect(word.turkish == "eskimiş, bayat")
        #expect(word.definition == "not fresh")
        #expect(word.example == "Old cache.")
        #expect(word.source == "DDIA")
        #expect(word.box == 3)
        #expect(word.dueDate == due)
    }
}
