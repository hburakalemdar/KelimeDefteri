import Foundation
import Testing
@testable import KelimeDefteri

struct GameCatalogTests {
    @Test func deckSummary() {
        let deck = GameDeck(entries: [
            ("idempotent", ["No match here.", "Retries are safe only if the operation is Idempotent."], "eşgüçlü"),
            ("stale", [], "bayat, eskimiş"),
            ("eventual consistency", ["Reads rely on eventual consistency."], "nihai tutarlılık"),
            ("internationalization", ["i18n"], "uluslararasılaştırma"),
        ])
        #expect(deck.count == 4)
        #expect(deck.withSentence == 2)
        #expect(deck.shortWords == 2)
        #expect(deck.distinctMeaningCount == 4)
    }

    @Test func requirements() {
        let small = GameDeck(count: 3, withSentence: 3, shortWords: 0)
        #expect(small.distinctMeaningCount == 3)
        #expect(GameMode.quickRound.unavailableReason(for: small) == nil)
        #expect(GameMode.multipleChoice.unavailableReason(for: small) == "Farklı anlamlı 4 kelime gerekli")
        #expect(GameMode.fillBlank.unavailableReason(for: small) != nil)
        #expect(GameMode.letters.unavailableReason(for: small) != nil)
        let big = GameDeck(count: 10, withSentence: 4, shortWords: 1)
        #expect(GameMode.allCases.allSatisfy { $0.unavailableReason(for: big) == nil })
    }

    /// Ortak Türkçe anlamı olan kelimeler tek küme sayılır; 4 kelime ama 3 anlam → seçmeli oyunlar kapalı.
    @Test func distinctMeaningsGateChoiceGames() {
        let deck = GameDeck(entries: [
            ("me", [], "ben"),
            ("you", [], "sen"),
            ("deneme", [], "deneme"),
            ("denemw", [], "Deneme"),
        ])
        #expect(deck.count == 4)
        #expect(deck.distinctMeaningCount == 3)
        #expect(GameMode.multipleChoice.unavailableReason(for: deck) != nil)
        #expect(GameMode.match.unavailableReason(for: deck) != nil)
        #expect(GameMode.quickRound.unavailableReason(for: deck) == nil)
        #expect(GameMode.reverse.unavailableReason(for: deck) == nil)
    }

    /// Kümeleme zincirlemedir: stale–outdated "eskimiş"i, outdated–obsolete "geçersiz"i paylaşır → tek küme.
    @Test func distinctMeaningsAreTransitive() {
        #expect(GameDeck.distinctMeaningCount(["bayat, eskimiş", "eskimiş, geçersiz", "geçersiz", "verim", ""]) == 3)
        #expect(GameDeck.distinctMeaningCount([]) == 0)
    }

    @Test func quickRoundCardShowsRealEstimate() {
        // 5 kelime × 25 sn ≈ 2 dakika.
        #expect(GameMode.quickRound.cardDetail == "5 kelime, ~2 dakika")
    }
}
