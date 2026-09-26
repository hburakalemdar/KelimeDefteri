import Foundation

/// Başka bir uygulamadan paylaşılan metinden kelime taslağı çıkarır.
///
/// Apple Books seçili metni şöyle paylaşır:
///
///     “A follower replica may return stale data.”
///
///     Excerpt From
///     Designing Data-Intensive Applications
///     Martin Kleppmann
///     This material may be protected by copyright.
///
/// Buradan cümleyi ve kitap adını ayırır. Tek kelime ya da kısa bir ifade ("carry out")
/// paylaşıldıysa onu doğrudan kelime yapar.
nonisolated enum SharedTextParser {
    struct Draft: Equatable {
        var english = ""
        var example = ""
    }

    /// Bu kadar kelimeye kadar, cümle gibi bitmeyen seçim ifade sayılır ("on the other hand").
    static let maxPhraseLength = 4
    /// Cümledeki düğmelerle seçilebilecek en uzun ifade.
    static let maxSelectionLength = 6

    /// Apple Kitaplar'ın alıntının altına eklediği kaynak satırı; o satırdan sonrası cümleye girmez.
    private static let sourceMarkers = ["Excerpt From", "Alıntı Kaynağı", "Alıntı:"]
    private static let quoteCharacters = CharacterSet(charactersIn: "“”\"'‘’«»")

    static func draft(from sharedText: String) -> Draft {
        let lines = sharedText.components(separatedBy: .newlines)
        var quoteLines = lines
        if let markerIndex = lines.firstIndex(where: { line in
            sourceMarkers.contains { line.trimmingCharacters(in: .whitespaces).hasPrefix($0) }
        }) {
            quoteLines = Array(lines[..<markerIndex])
        }

        let text = quoteLines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(quoteCharacters))

        let tokens = tokens(in: text)
        let looksLikeSentence = text.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?;:,")) != nil
        if tokens.count == 1 || (tokens.count <= maxPhraseLength && !looksLikeSentence) {
            return Draft(english: tokens.joined(separator: " ").lowercased(), example: "")
        }
        return Draft(english: "", example: text)
    }

    /// Cümledeki kelimeler sırasıyla, tekrarlar dahil ("don't", "read-only" tek kelime sayılır).
    static func tokens(in sentence: String) -> [String] {
        let separators = CharacterSet.letters.union(CharacterSet(charactersIn: "'’-")).inverted
        return sentence.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'’-")) }
            .filter { $0.count > 1 || $0.lowercased() == "a" }
    }

    /// Kelime düğmesine dokununca seçimi günceller. İlk dokunuş kelimeyi seçer; ikinci dokunuş
    /// aradaki kelimelerle birlikte ifadeyi seçer; seçili tek kelimeye yeniden dokunmak seçimi
    /// kaldırır. İfade seçiliyken başka bir kelimeye dokunmak yeni seçime başlar. Cümlede aynı kelime birden çok
    /// kez geçiyorsa (`tokens` verilince) hepsi aynı kelime sayılır: seçili kelimenin başka bir geçişine dokunmak da
    /// seçimi kaldırır, ikisinin arasını ifade olarak seçmez.
    static func select(_ index: Int, current: ClosedRange<Int>?, tokens: [String] = []) -> ClosedRange<Int>? {
        guard let current else { return index...index }
        guard current.count == 1 else { return index...index }
        if current.lowerBound == index || isSameWord(index, current.lowerBound, in: tokens) { return nil }
        let range = min(index, current.lowerBound)...max(index, current.lowerBound)
        return range.count <= maxSelectionLength ? range : index...index
    }

    /// İki düğme cümlede aynı kelime mi (büyük/küçük harf gözetilmez).
    static func isSameWord(_ a: Int, _ b: Int, in tokens: [String]) -> Bool {
        tokens.indices.contains(a) && tokens.indices.contains(b)
            && AnswerChecker.fold(tokens[a]) == AnswerChecker.fold(tokens[b])
    }

    /// Seçili kelimelerden kaydedilecek ifade.
    static func phrase(_ tokens: [String], _ range: ClosedRange<Int>) -> String {
        tokens[range].joined(separator: " ").lowercased()
    }

    /// Cümledeki kelimeler, ilk geçtikleri sırayla ve tekrarsız.
    static func words(in sentence: String) -> [String] {
        var seen = Set<String>()
        return tokens(in: sentence).filter { seen.insert($0.lowercased()).inserted }
    }
}
