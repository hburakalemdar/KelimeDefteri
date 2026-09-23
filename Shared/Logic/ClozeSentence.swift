import Foundation

/// Boşluğu Doldur için cümleyi kelimenin geçtiği yerden üçe böler.
///
/// Büyük/küçük harf ve aksan farkı gözetilmez. Kelimenin önünde harf olmamalı ("art" ↔ "start" eşleşmez).
/// Önce kelimenin tek başına geçtiği yer aranır; yoksa bilinen bir İngilizce ekle geçtiği yer kabul edilir
/// ("tombstone" ↔ "tombstones", "run" ↔ "running") ama başka bir kelime değil ("art" ↔ "artificial").
/// Boşluk yalnızca kelimenin kendisini kaplar.
nonisolated struct ClozeSentence: Equatable {
    let before: String
    /// Cümlede yazıldığı hâliyle kelime.
    let match: String
    let after: String

    /// Kelimenin arkasından gelebilecek ekler; önlerinde son harf ikilenebilir ("running", "stopped").
    static let suffixes = ["s", "es", "d", "ed", "ing", "er", "ers", "ly"]

    init?(sentence: String, word: String) {
        let needle = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        var found: Range<String.Index>?
        var searchStart = sentence.startIndex
        while let range = sentence.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive],
                                         range: searchStart..<sentence.endIndex) {
            searchStart = range.upperBound
            let startsWord = range.lowerBound == sentence.startIndex
                || !sentence[sentence.index(before: range.lowerBound)].isLetter
            guard startsWord else { continue }
            let tail = sentence[range.upperBound...].prefix { $0.isLetter }.lowercased()
            if tail.isEmpty {
                found = range
                break
            }
            if found == nil, Self.isSuffix(tail, after: needle) { found = range }
        }
        guard let range = found else { return nil }
        before = String(sentence[..<range.lowerBound])
        match = String(sentence[range])
        after = String(sentence[range.upperBound...])
    }

    private static func isSuffix(_ tail: String, after word: String) -> Bool {
        if suffixes.contains(tail) { return true }
        // İkilenen son harf: "run" + "ning", "stop" + "ped".
        guard let last = word.lowercased().last, tail.first == last else { return false }
        let rest = String(tail.dropFirst())
        return ["ed", "ing", "er", "ers"].contains(rest)
    }

    static let blank = "_____"
}
