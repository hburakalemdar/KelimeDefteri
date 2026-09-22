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
/// Buradan cümleyi ve kitap adını ayırır. Tek kelime paylaşıldıysa onu doğrudan kelime yapar.
nonisolated enum SharedTextParser {
    struct Draft: Equatable {
        var english = ""
        var example = ""
        var source: String?
    }

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

        let tokens = words(in: text)
        if tokens.count == 1 {
            return Draft(english: tokens[0].lowercased(), example: "", source: source)
        }
        return Draft(english: "", example: text, source: source)
    }

    /// Cümledeki kelimeler, ilk geçtikleri sırayla ve tekrarsız ("don't", "read-only" tek kelime sayılır).
    static func words(in sentence: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        let separators = CharacterSet.letters.union(CharacterSet(charactersIn: "'’-")).inverted
        for raw in sentence.components(separatedBy: separators) {
            let word = raw.trimmingCharacters(in: CharacterSet(charactersIn: "'’-"))
            guard word.count > 1 || word.lowercased() == "a" else { continue }
            if seen.insert(word.lowercased()).inserted {
                result.append(word)
            }
        }
        return result
    }
}
