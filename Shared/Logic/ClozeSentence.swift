import Foundation

/// Boşluğu Doldur için cümleyi kelimenin geçtiği yerden üçe böler.
///
/// Büyük/küçük harf ve aksan farkı gözetilmez. Kelimenin önünde harf olmamalı ("art" ↔ "start" eşleşmez);
/// arkasından ek gelebilir ("tombstone" ↔ "tombstones"), boşluk yalnızca kelimenin kendisini kaplar.
nonisolated struct ClozeSentence: Equatable {
    let before: String
    /// Cümlede yazıldığı hâliyle kelime.
    let match: String
    let after: String

    init?(sentence: String, word: String) {
        let needle = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        var searchStart = sentence.startIndex
        while let range = sentence.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive],
                                         range: searchStart..<sentence.endIndex) {
            let startsWord = range.lowerBound == sentence.startIndex
                || !sentence[sentence.index(before: range.lowerBound)].isLetter
            if startsWord {
                before = String(sentence[..<range.lowerBound])
                match = String(sentence[range])
                after = String(sentence[range.upperBound...])
                return
            }
            searchStart = range.upperBound
        }
        return nil
    }

    static let blank = "_____"
}
