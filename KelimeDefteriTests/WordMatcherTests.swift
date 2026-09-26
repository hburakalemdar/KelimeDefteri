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

        #expect(word.wouldAbsorb(turkish: "bayat", example: ""))
        #expect(!word.wouldAbsorb(turkish: "Eskimiş", example: "New sentence."))

        word.absorb(turkish: "bayat", example: "New sentence.")
        #expect(word.turkish == "eskimiş, bayat")
        #expect(word.example == "Old cache.")
        #expect(word.box == 3)
        #expect(word.dueDate == due)
    }

    @Test func differentSentenceCanReplaceOnlyWhenChosen() {
        let word = Word(english: "such", turkish: "böyle", example: "Such a case.")
        #expect(word.hasDifferentExample("  Such is life. "))
        #expect(!word.hasDifferentExample("Such a case."))
        #expect(!word.hasDifferentExample(""))

        // Yalnızca cümle farklı: seçilince ekleme eylemi açılır.
        #expect(word.wouldAbsorb(turkish: "böyle", example: "Such is life.", replacingExample: true))
        #expect(!word.wouldAbsorb(turkish: "böyle", example: "Such is life.", replacingExample: false))
        #expect(!word.wouldAbsorb(turkish: "böyle", example: "Such a case.", replacingExample: true))

        word.absorb(turkish: "böyle", example: "Such is life. ", replacingExample: false)
        #expect(word.example == "Such a case.")
        word.absorb(turkish: "öyle", example: " Such is life.", replacingExample: true)
        #expect(word.example == "Such is life.")
        #expect(word.turkish == "böyle, öyle")
    }

    @Test func emptySentenceIsFilledAndEmptyIncomingKeepsOld() {
        let empty = Word(english: "such", turkish: "böyle")
        #expect(!empty.hasDifferentExample("Such is life."))
        #expect(empty.takesExample("Such is life.", replacing: false))
        empty.absorb(turkish: "böyle", example: "Such is life.")
        #expect(empty.example == "Such is life.")

        // Boş gelen cümle, "yeni" seçili olsa da kayıttakini silmez.
        #expect(!empty.wouldAbsorb(turkish: "böyle", example: "", replacingExample: true))
        empty.absorb(turkish: "böyle", example: "", replacingExample: true)
        #expect(empty.example == "Such is life.")
    }

    @Test func mergedExamplesKeepsBoth() {
        #expect(WordMatcher.mergedExamples("A.", "B.") == "A.\nB.")
        #expect(WordMatcher.mergedExamples("A.", " A. ") == "A.")
        #expect(WordMatcher.mergedExamples("", "B.") == "B.")
        #expect(WordMatcher.mergedExamples("A.", "") == "A.")
        #expect(WordMatcher.mergedExamples("A.\nB.", "B.") == "A.\nB.")
    }
}
