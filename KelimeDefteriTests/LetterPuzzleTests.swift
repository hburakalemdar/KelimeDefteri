import Foundation
import Testing
@testable import KelimeDefteri

struct LetterPuzzleTests {
    private func puzzle(_ word: String, seed: UInt64 = 1) -> LetterPuzzle {
        var generator = SeededGenerator(seed: seed)
        return LetterPuzzle(word: word, using: &generator)
    }

    /// Doğru harfleri sırayla yerleştirir (aynı harften birden fazla varsa ilk boştakini alır).
    private func solve(_ puzzle: inout LetterPuzzle) {
        for letter in puzzle.answer {
            let tile = puzzle.freeTiles.first { LetterPuzzle.fold(puzzle.tiles[$0]) == LetterPuzzle.fold(letter) }!
            puzzle.place(tile: tile)
        }
    }

    @Test func phraseKeepsSpacesFixed() {
        let p = puzzle("take off")
        #expect(p.answer.count == 7)
        #expect(p.layout[4] == .fixed(" "))
        #expect(p.tiles.count == 7)
        #expect(p.tiles.map(String.init).joined() != "takeoff")
    }

    @Test func placingAndRemovingTiles() {
        var p = puzzle("stale")
        let first = p.freeTiles[0]
        p.place(tile: first)
        #expect(p.slots[0] == first)
        p.place(tile: first)
        #expect(p.slots.compactMap { $0 }.count == 1)
        p.remove(slot: 0)
        #expect(p.freeTiles.count == 5)
    }

    @Test func correctSolutionGetsGood() {
        var p = puzzle("quorum")
        solve(&p)
        let solved = p.check()
        #expect(solved)
        #expect(p.grade == .good)
    }

    @Test func mistakesLowerTheGrade() {
        var p = puzzle("stale", seed: 7)
        for tile in p.freeTiles { p.place(tile: tile) }  // karışık sırayla: yanlış
        let firstTry = p.check()
        #expect(!firstTry)
        #expect(p.mistakes == 1)
        #expect(p.grade == .hard)
        for slot in 0..<5 { p.remove(slot: slot) }
        solve(&p)
        let secondTry = p.check()
        #expect(secondTry)
        #expect(p.grade == .hard)
    }

    @Test func revealCountsAsAgain() {
        var p = puzzle("idempotent")
        p.reveal()
        #expect(p.isCorrect)
        #expect(p.grade == .again)
    }

    @Test func caseAndRepeatedLetters() {
        var p = puzzle("API")
        solve(&p)
        #expect(p.isCorrect)
        var q = puzzle("aaa")
        for tile in q.freeTiles { q.place(tile: tile) }
        let sameLetters = q.check()
        #expect(sameLetters)
    }

    @Test func typingPicksMatchingFreeTile() {
        var p = puzzle("Naïve")
        // Büyük harf ve aksan fark etmez.
        let tile = p.freeTile(matching: "i")
        #expect(tile.map { LetterPuzzle.fold(p.tiles[$0]) } == "i")
        p.place(tile: tile!)
        // Tek i vardı; ikinci kez yazılınca serbest taş kalmaz.
        #expect(p.freeTile(matching: "I") == nil)
        #expect(p.freeTile(matching: "x") == nil)
        let n = p.freeTile(matching: "n")
        #expect(n != nil)
    }

    @Test func lastFilledSlotForBackspace() {
        var p = puzzle("stale")
        #expect(p.lastFilledSlot == nil)
        p.place(tile: p.freeTiles[0])
        p.place(tile: p.freeTiles[0])
        #expect(p.lastFilledSlot == 1)
        p.remove(slot: 1)
        #expect(p.lastFilledSlot == 0)
        // Ortadaki yuva boşalırsa en sağdaki dolu yuva döner.
        p.place(tile: p.freeTiles[0])
        p.place(tile: p.freeTiles[0])
        p.remove(slot: 1)
        #expect(p.lastFilledSlot == 2)
    }
}
