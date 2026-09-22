import Foundation

/// Kullanıcının yazdığı Türkçe cevabı kayıtlı anlamlarla karşılaştırır.
///
/// Hoşgörülü davranır: büyük/küçük harf, Türkçe karakterler (ş/s, ı/i…) ve
/// noktalama fark etmez. Kayıtta virgülle ayrılmış anlamlardan birini tutturmak
/// yeterlidir. Son kararı yine kullanıcı "Bildim / Bilemedim" ile verir.
nonisolated enum AnswerChecker {
    private static let turkishLocale = Locale(identifier: "tr_TR")
    private static let meaningSeparators: Set<Character> = [",", ";", "/"]
    private static let minPartialLength = 4

    static func isCorrect(_ answer: String, expected: String) -> Bool {
        let given = meanings(in: answer)
        let valid = meanings(in: expected)
        return given.contains { guess in
            valid.contains { meaning in
                guess == meaning
                    || (min(guess.count, meaning.count) >= minPartialLength
                        && (meaning.contains(guess) || guess.contains(meaning)))
            }
        }
    }

    /// Karşılaştırma ve arama için metni sadeleştirir: "Değişmeyen!" → "degismeyen".
    static func fold(_ text: String) -> String {
        let lowered = text.lowercased(with: turkishLocale).replacingOccurrences(of: "ı", with: "i")
        let folded = lowered.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: turkishLocale)
        let allowed = CharacterSet.letters.union(.decimalDigits)
        let spaced = String(folded.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " })
        return spaced.split(separator: " ").joined(separator: " ")
    }

    static func meanings(in text: String) -> [String] {
        text.split(whereSeparator: { meaningSeparators.contains($0) })
            .map { fold(String($0)) }
            .filter { !$0.isEmpty }
    }
}
