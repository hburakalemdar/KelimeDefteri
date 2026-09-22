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
        var source: String?
    }

    /// Bu kadar kelimeye kadar, cümle gibi bitmeyen seçim ifade sayılır ("on the other hand").
    static let maxPhraseLength = 4
    /// Cümledeki düğmelerle seçilebilecek en uzun ifade.
    static let maxSelectionLength = 6

    private static let sourceMarkers = ["Excerpt From", "Alıntı Kaynağı", "Alıntı:"]
    private static let quoteCharacters = CharacterSet(charactersIn: "“”\"'‘’«»")

    static func draft(from sharedText: String) -> Draft {
        let lines = sharedText.components(separatedBy: .newlines)
        var quoteLines = lines
        var source: String?

        if let markerIndex = lines.firstIndex(where: { line in
            sourceMarkers.contains { line.trimmingCharacters(in: .whitespaces).hasPrefix($0) }
        }) {
            quoteLines = Array(lines[..<markerIndex])
            let markerLine = lines[markerIndex].trimmingCharacters(in: .whitespaces)
            let sameLine = sourceMarkers
                .first { markerLine.hasPrefix($0) }
                .map { markerLine.dropFirst($0.count).trimmingCharacters(in: .whitespaces) } ?? ""
            source = sameLine.isEmpty
                ? lines[(markerIndex + 1)...].map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
                : sameLine
        }

        let text = quoteLines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(quoteCharacters))

        let tokens = tokens(in: text)
        let looksLikeSentence = text.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?;:,")) != nil
        if tokens.count == 1 || (tokens.count <= maxPhraseLength && !looksLikeSentence) {
            return Draft(english: tokens.joined(separator: " ").lowercased(), example: "", source: source)
        }
        return Draft(english: "", example: text, source: source)
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
    /// kaldırır. İfade seçiliyken başka bir kelimeye dokunmak yeni seçime başlar.
    static func select(_ index: Int, current: ClosedRange<Int>?) -> ClosedRange<Int>? {
        guard let current else { return index...index }
        guard current.count == 1 else { return index...index }
        if current.lowerBound == index { return nil }
        let range = min(index, current.lowerBound)...max(index, current.lowerBound)
        return range.count <= maxSelectionLength ? range : index...index
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
