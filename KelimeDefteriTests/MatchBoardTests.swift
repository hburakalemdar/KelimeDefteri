import Foundation
import Testing
@testable import KelimeDefteri

struct MatchBoardTests {
    @Test func rightColumnIsShuffledPermutation() {
        for seed in 0..<20 as Range<UInt64> {
            var generator = SeededGenerator(seed: seed)
            let board = MatchBoard(count: 5, using: &generator)
            #expect(Set(board.right) == Set(0..<5))
            #expect(board.right != board.left)
        }
    }

    @Test func wrongPairMarksOnlyTheChosenWordAndCountsError() {
        var generator = SeededGenerator(seed: 1)
        var board = MatchBoard(count: 4, using: &generator)
        #expect(board.pick(left: 0, right: 2) == .mismatched(left: 0, right: 2))
        #expect(board.errors == 1)
        #expect(board.pick(left: 1, right: 1) == .matched(1))
        #expect(board.grade(for: 0) == .again)
        // 2'nin anlamı yanlış kelimeye verildi; 2'yi yanlış bilmiş sayılmaz.
        #expect(board.grade(for: 2) == .good)
        #expect(board.grade(for: 1) == .good)
        #expect(!board.isComplete)
        for id in [0, 2, 3] { _ = board.pick(left: id, right: id) }
        #expect(board.isComplete)
        #expect(board.grade(for: 3) == .good)
    }
}
