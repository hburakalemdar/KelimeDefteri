import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

/// SPEC-MOTOR2 §3.2 / §7.2 B: tur içi oyun mantığı, cevap kontrolü ve çeldiriciler.
struct RoundLogicTests {
    // MARK: - Anlam-tabanlı çeldirici (Boşluğu Doldur)

    /// İngilizce seçenekler Türkçe anlamlarıyla kurulunca ipucuyla aynı anlamı taşıyan kelime çeldirici olmaz.
    @Test func fillBlankDistractorsSkipSameMeaning() {
        let entries = [("deneme", "deneme"), ("denemw", "deneme"), ("me", "ben"), ("you", "sen"), ("stale", "bayat")]
        let candidates = entries.map { ChoiceQuiz.Candidate(text: $0.0, meanings: AnswerChecker.meanings(in: $0.1)) }
        for seed in 0..<40 as Range<UInt64> {
            var generator = SeededGenerator(seed: seed)
            let result = ChoiceQuiz.options(answer: candidates[0], others: Array(candidates.dropFirst()), using: &generator)
            #expect(!result.options.contains("denemw"))
            #expect(result.options[result.correctIndex] == "deneme")
            #expect(result.options.count == 4)
        }
    }

    // MARK: - AnswerChecker

    @Test func partialMatchNeedsKnownTurkishSuffix() {
        #expect(!AnswerChecker.isCorrect("kara", expected: "karar"))
        #expect(!AnswerChecker.isCorrect("kale", expected: "kalem"))
        #expect(AnswerChecker.isCorrect("kaydet", expected: "kaydetmek"))
        #expect(AnswerChecker.isCorrect("kaydetmek", expected: "kaydet"))
        #expect(AnswerChecker.isCorrect("verim", expected: "verimlilik"))
        #expect(AnswerChecker.isCorrect("sunucu", expected: "sunucular"))
        #expect(AnswerChecker.isCorrect("sunucu", expected: "sunucularda"))
        #expect(!AnswerChecker.isCorrect("kayıt", expected: "kayıtsız"))
    }

    @Test func answerIsNotSplitIntoSeveralGuesses() {
        #expect(!AnswerChecker.isCorrect("ben, sen, deneme", expected: "deneme"))
        #expect(!AnswerChecker.isCorrect("hız; verim", expected: "verim"))
        // Virgüllü cevabın her parçası tutuyorsa doğru.
        #expect(AnswerChecker.isCorrect("bayat, eskimiş", expected: "bayat, eskimiş, güncel olmayan"))
    }

    // MARK: - MatchBoard

    /// Önce sağdaki anlam seçilirse (soru o), yanlış çiftte hata o anlamın kelimesine yazılır.
    @Test func matchMistakeGoesToQuestionSide() {
        var generator = SeededGenerator(seed: 3)
        var board = MatchBoard(count: 4, using: &generator)
        #expect(board.pick(left: 0, right: 2, questionIsLeft: false) == .mismatched(left: 0, right: 2))
        #expect(board.errors == 1)
        #expect(board.grade(for: 2) == .again)
        #expect(board.grade(for: 0) == .good)
        // Soldan başlanırsa hata soldaki kelimeye.
        _ = board.pick(left: 1, right: 3, questionIsLeft: true)
        #expect(board.grade(for: 1) == .again)
        #expect(board.grade(for: 3) == .good)
        // Eşleşmiş kelimeye sonradan hata yazılmaz.
        _ = board.pick(left: 3, right: 3)
        _ = board.pick(left: 0, right: 3, questionIsLeft: false)
        #expect(board.grade(for: 3) == .good)
    }

    // MARK: - LetterPuzzle

    @Test func lettersShownLowercase() {
        var generator = SeededGenerator(seed: 5)
        let puzzle = LetterPuzzle(word: "PostgreSQL", using: &generator)
        let shown = puzzle.tiles.map(LetterPuzzle.display)
        #expect(shown.allSatisfy { $0 == $0.lowercased() })
        #expect(Set(shown) == Set("postgresql".map(String.init)))
    }

    @Test func letterGradeThresholds() {
        func solved(after mistakes: Int) -> AnswerGrade {
            var generator = SeededGenerator(seed: 7)
            var puzzle = LetterPuzzle(word: "stale", using: &generator)
            let wrong = puzzle.freeTiles
            for _ in 0..<mistakes {
                for tile in wrong { puzzle.place(tile: tile) }
                _ = puzzle.check()
                for slot in puzzle.slots.indices { puzzle.remove(slot: slot) }
            }
            for letter in puzzle.answer {
                puzzle.place(tile: puzzle.freeTiles.first { LetterPuzzle.fold(puzzle.tiles[$0]) == LetterPuzzle.fold(letter) }!)
            }
            let solved = puzzle.check()
            #expect(solved)
            return puzzle.grade
        }
        #expect(solved(after: 0) == .good)
        #expect(solved(after: 1) == .hard)
        #expect(solved(after: 2) == .hard)
        #expect(solved(after: 3) == .again)
        #expect(!solved(after: 3).isCorrect)
    }

    // MARK: - ClozeSentence

    @Test func clozeBlanksEveryOccurrence() throws {
        let cloze = try #require(ClozeSentence(sentence: "A quorum is needed; without quorum, writes stop.", word: "quorum"))
        #expect(cloze.matchCount == 2)
        #expect(cloze.pieces == ["A ", "quorum", " is needed; without ", "quorum", ", writes stop."])
        #expect(cloze.before == "A ")
        #expect(cloze.match == "quorum")
        #expect(cloze.after == " is needed; without quorum, writes stop.")
        // Ekli geçiş de boşaltılır, başka kelimenin içi değil.
        let mixed = try #require(ClozeSentence(sentence: "Tombstones mark a tombstone, not a tombstonery.", word: "tombstone"))
        #expect(mixed.matchCount == 2)
        #expect(mixed.pieces[1] == "Tombstone")
        #expect(mixed.pieces[2] == "s mark a ")
    }

    // MARK: - Seçim: bugün yanlış yapılan kelime ağırlıklı oyunlarda da seçilebilir (§2.8)

    @Test func wrongTodayStillPickedByWeightedGames() throws {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        let words = (0..<6).map { Word(english: "w\($0)", turkish: "anlam \($0)") }
        words.forEach(context.insert)
        let missed = words[0]
        let now = Date.now
        let first = GameRound(mode: .multipleChoice, seed: 1, defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        first.start(with: [missed], count: 1, now: now)
        first.record(missed, grade: .again, now: now)
        #expect(missed.isLapsed)
        #expect(!missed.isDue(at: now.addingTimeInterval(60)))

        for mode in [GameMode.multipleChoice, .match, .fillBlank, .quickRound] {
            for seed in 0..<5 as Range<UInt64> {
                let round = GameRound(mode: mode, seed: seed, defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
                round.start(with: words, count: words.count, now: now.addingTimeInterval(60))
                #expect(round.words.contains { $0 === missed }, "\(mode)")
            }
        }
    }
}
