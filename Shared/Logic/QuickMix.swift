import Foundation

/// Karışık Hızlı Tur: her soru için oynanabilir oyun türlerinden biri rastgele seçilir;
/// aynı tür art arda en fazla iki kez gelir.
nonisolated enum QuickMix {
    /// Tek soruluk oyun türleri. Eşleştir bir tahta oyunu olduğu için karışık tura girmez.
    static let questionModes: [GameMode] = [.quickRound, .multipleChoice, .fillBlank, .letters, .reverse]
    static let maxRepeat = 2

    /// `allowed[i]`: i. kelime için oynanabilir türler (boş olmamalı). Dönen dizi her soru için tür.
    static func modes<G: RandomNumberGenerator>(allowed: [[GameMode]], using generator: inout G) -> [GameMode] {
        var result: [GameMode] = []
        for options in allowed {
            let fallback = options.isEmpty ? [GameMode.quickRound] : options
            let blocked: GameMode? = result.count >= maxRepeat
                && Set(result.suffix(maxRepeat)).count == 1 ? result.last : nil
            let choices = fallback.filter { $0 != blocked }
            result.append((choices.isEmpty ? fallback : choices).randomElement(using: &generator)!)
        }
        return result
    }

    /// Kelimenin hangi türlerde sorulabileceği.
    static func allowedModes(english: String, example: String, deckCount: Int) -> [GameMode] {
        var modes: [GameMode] = [.quickRound, .reverse]
        if deckCount >= 4 { modes.append(.multipleChoice) }
        if deckCount >= 4, ClozeSentence(sentence: example, word: english) != nil { modes.append(.fillBlank) }
        if (1...GameDeck.maxLetters).contains(GameDeck.letterCount(english)) { modes.append(.letters) }
        return modes
    }
}
