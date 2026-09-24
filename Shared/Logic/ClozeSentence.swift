import Foundation

/// Boşluğu Doldur için cümleyi kelimenin geçtiği yerlerden böler.
///
/// Büyük/küçük harf ve aksan farkı gözetilmez. Kelimenin önünde harf olmamalı ("art" ↔ "start" eşleşmez).
/// Kelimenin tek başına ya da bilinen bir İngilizce ekle geçtiği her yer boşaltılır ("tombstone" ↔
/// "tombstones", "run" ↔ "running") ama başka bir kelime değil ("art" ↔ "artificial"). Kelime cümlede
/// iki kez geçiyorsa ikisi de boşaltılır; yoksa ikincisi cevabı ele verirdi. Boşluk yalnızca kelimenin
/// kendisini kaplar.
nonisolated struct ClozeSentence: Equatable {
    /// Sırayla metin, eşleşme, metin, eşleşme, …, metin (tek sayıda parça; en az bir eşleşme).
    /// Çift sıradakiler cümlenin kalan kısmı, tek sıradakiler cümlede yazıldığı hâliyle kelime.
    let pieces: [String]

    /// İlk geçişten önceki metin.
    var before: String { pieces[0] }
    /// Cümlede yazıldığı hâliyle kelime (ilk geçiş).
    var match: String { pieces[1] }
    /// İlk geçişten sonraki metnin tamamı (varsa sonraki geçişler dahil).
    var after: String { pieces.dropFirst(2).joined() }
    /// Cümlede boşaltılan geçiş sayısı.
    var matchCount: Int { pieces.count / 2 }

    /// Kelimenin arkasından gelebilecek ekler; önlerinde son harf ikilenebilir ("running", "stopped").
    static let suffixes = ["s", "es", "d", "ed", "ing", "er", "ers", "ly"]

    init?(sentence: String, word: String) {
        let needle = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        var ranges: [Range<String.Index>] = []
        var searchStart = sentence.startIndex
        while let range = sentence.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive],
                                         range: searchStart..<sentence.endIndex) {
            searchStart = range.upperBound
            let startsWord = range.lowerBound == sentence.startIndex
                || !sentence[sentence.index(before: range.lowerBound)].isLetter
            guard startsWord else { continue }
            let tail = sentence[range.upperBound...].prefix { $0.isLetter }.lowercased()
            if tail.isEmpty || Self.isSuffix(tail, after: needle) { ranges.append(range) }
        }
        guard !ranges.isEmpty else { return nil }
        var pieces: [String] = []
        var cursor = sentence.startIndex
        for range in ranges {
            pieces.append(String(sentence[cursor..<range.lowerBound]))
            pieces.append(String(sentence[range]))
            cursor = range.upperBound
        }
        pieces.append(String(sentence[cursor...]))
        self.pieces = pieces
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
