import Foundation
import Testing
@testable import KelimeDefteri

struct QuickMixTests {
    @Test func neverThreeOfTheSameInARow() {
        for seed in 0..<200 as Range<UInt64> {
            var generator = SeededGenerator(seed: seed)
            let modes = QuickMix.modes(allowed: Array(repeating: [.quickRound, .reverse], count: 12), using: &generator)
            for index in 2..<modes.count {
                #expect(!(modes[index] == modes[index - 1] && modes[index] == modes[index - 2]))
            }
        }
    }

    @Test func onlyAllowedModesAreUsed() {
        var generator = SeededGenerator(seed: 3)
        let allowed: [[GameMode]] = [[.letters], [.letters], [.letters, .reverse], [.multipleChoice]]
        let modes = QuickMix.modes(allowed: allowed, using: &generator)
        #expect(modes == [.letters, .letters, .reverse, .multipleChoice])
    }

    @Test func singleOptionMayRepeatWhenNothingElseFits() {
        var generator = SeededGenerator(seed: 1)
        #expect(QuickMix.modes(allowed: [[.reverse], [.reverse], [.reverse]], using: &generator) == [.reverse, .reverse, .reverse])
    }

    @Test func allowedModesFollowGameRules() {
        let small = QuickMix.allowedModes(english: "stale", sentences: ["Fresh data.", "Stale data."], deckCount: 3)
        #expect(Set(small) == [.quickRound, .reverse, .letters])
        let full = QuickMix.allowedModes(english: "stale", sentences: ["Fresh data.", "Stale data."], deckCount: 8)
        #expect(Set(full) == Set(QuickMix.questionModes))
        let long = QuickMix.allowedModes(english: "internationalization", sentences: [], deckCount: 8)
        #expect(Set(long) == [.quickRound, .reverse, .multipleChoice])
    }
}
