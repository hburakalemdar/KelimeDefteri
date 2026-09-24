import Foundation
import Testing
@testable import KelimeDefteri

struct ReverseCheckerTests {
    @Test func exactIgnoresCaseAndPunctuation() {
        #expect(ReverseChecker.check("Idempotent", expected: "idempotent") == .exact)
        #expect(ReverseChecker.check("take  off!", expected: "take off") == .exact)
    }

    @Test func oneLetterOffIsTypoForLongWords() {
        #expect(ReverseChecker.check("idempotant", expected: "idempotent") == .typo)
        #expect(ReverseChecker.check("idmpotent", expected: "idempotent") == .typo)
        #expect(ReverseChecker.check("quorumm", expected: "quorum") == .typo)
        #expect(ReverseChecker.check("idempotnt", expected: "idempotent") == .typo)
    }

    @Test func shortWordsAndBigDifferencesAreWrong() {
        #expect(ReverseChecker.check("stal", expected: "stale") == .typo)
        #expect(ReverseChecker.check("cat", expected: "car") == .wrong)
        #expect(ReverseChecker.check("idempo", expected: "idempotent") == .wrong)
        #expect(ReverseChecker.check("", expected: "stale") == .wrong)
    }

    /// Defterdeki eşanlamlı kelime (ortak Türkçe anlam) yazılırsa `.synonymOf`; anlamı ortak olmayan
    /// kelime yanlış kalır, aranan kelimenin kendisi tam doğru.
    @Test func synonymFromTheNotebook() {
        let words = [
            Word(english: "stale", turkish: "bayat, eskimiş"),
            Word(english: "outdated", turkish: "eskimiş, modası geçmiş"),
            Word(english: "quorum", turkish: "yeter sayı"),
        ]
        #expect(ReverseChecker.check("Outdated", expected: "stale", in: words) == .synonymOf("outdated"))
        #expect(ReverseChecker.check("stale", expected: "outdated", in: words) == .synonymOf("stale"))
        #expect(ReverseChecker.check("quorum", expected: "stale", in: words) == .wrong)
        #expect(ReverseChecker.check("stale", expected: "stale", in: words) == .exact)
        #expect(ReverseChecker.check("stalle", expected: "stale", in: words) == .typo)
        // Defterde olmayan kelime eşanlamlı sayılmaz.
        #expect(ReverseChecker.check("old", expected: "stale", in: words) == .wrong)
    }

    @Test func levenshtein() {
        #expect(ReverseChecker.distance("kitten", "sitting") == 3)
        #expect(ReverseChecker.distance("", "abc") == 3)
        #expect(ReverseChecker.distance("abc", "abc") == 0)
        #expect(ReverseChecker.distance("abcdef", "a", limit: 1) == 2)
    }
}
