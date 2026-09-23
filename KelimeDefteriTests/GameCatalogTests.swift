import Foundation
import Testing
@testable import KelimeDefteri

struct GameCatalogTests {
    @Test func deckSummary() {
        let deck = GameDeck(entries: [
            ("idempotent", "Retries are safe only if the operation is Idempotent."),
            ("stale", ""),
            ("eventual consistency", "Reads rely on eventual consistency."),
            ("internationalization", "i18n"),
        ])
        #expect(deck.count == 4)
        #expect(deck.withSentence == 2)
        #expect(deck.shortWords == 2)
    }

    @Test func requirements() {
        let small = GameDeck(count: 3, withSentence: 3, shortWords: 0)
        #expect(GameMode.quickRound.unavailableReason(for: small) == nil)
        #expect(GameMode.multipleChoice.unavailableReason(for: small) == "En az 4 kelime gerekli")
        #expect(GameMode.fillBlank.unavailableReason(for: small) != nil)
        #expect(GameMode.letters.unavailableReason(for: small) != nil)
        let big = GameDeck(count: 10, withSentence: 4, shortWords: 1)
        #expect(GameMode.allCases.allSatisfy { $0.unavailableReason(for: big) == nil })
    }
}
