import Foundation

/// Boşluğu Doldur için cümleyi kelimenin geçtiği yerlerden böler.
///
/// Büyük/küçük harf ve aksan farkı gözetilmez. Kelimenin önünde harf olmamalı ("art" ↔ "start" eşleşmez).
/// Kelimenin tek başına ya da bilinen bir İngilizce ekle geçtiği her yer boşaltılır ("tombstone" ↔
/// "tombstones", "run" ↔ "running") ama başka bir kelime değil ("art" ↔ "artificial"). Kelime cümlede
/// iki kez geçiyorsa ikisi de boşaltılır; yoksa ikincisi cevabı ele verirdi. Boşluk yalnızca kelimenin
/// kendisini kaplar.
///
/// Kalıpta (birden çok kelime) her 3+ harfli kelime ek alabilir ("depend on" ↔ "depends on",
/// "raise an issue" ↔ "raised an issue"); 1–2 harfli kelimeler (in, on, an, of…) ek almaz, olduğu gibi
/// aranır ("depend on" ↔ "depend only" eşleşmez). Kelimeler arasında bir ya da daha çok boşluk olabilir.
/// Son kelimenin eki boşluğun dışında kalır (tek kelimede olduğu gibi); aradakiler boşluğun içindedir.
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
        let words = needle.split(whereSeparator: \.isWhitespace).map(String.init)
        let ranges = words.count > 1
            ? Self.phraseRanges(of: words, in: sentence)
            : Self.wordRanges(of: needle, in: sentence)
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

    private static let searchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    private static func startsWord(_ index: String.Index, in sentence: String) -> Bool {
        index == sentence.startIndex || !sentence[sentence.index(before: index)].isLetter
    }

    /// Tek kelime (ya da tek parça girdi): kelimenin ardından ek gelebilir.
    private static func wordRanges(of needle: String, in sentence: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = sentence.startIndex
        while let range = sentence.range(of: needle, options: searchOptions,
                                         range: searchStart..<sentence.endIndex) {
            searchStart = range.upperBound
            guard startsWord(range.lowerBound, in: sentence) else { continue }
            let tail = sentence[range.upperBound...].prefix { $0.isLetter }.lowercased()
            if tail.isEmpty || isSuffix(tail, after: needle) { ranges.append(range) }
        }
        return ranges
    }

    /// Kalıp: kelimeler sırayla, aralarında boşlukla; 3+ harfli her kelime ek alabilir.
    private static func phraseRanges(of words: [String], in sentence: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = sentence.startIndex
        while let first = sentence.range(of: words[0], options: searchOptions,
                                         range: searchStart..<sentence.endIndex) {
            if startsWord(first.lowerBound, in: sentence),
               let end = phraseEnd(words, firstRange: first, in: sentence) {
                ranges.append(first.lowerBound..<end)
                searchStart = end
            } else {
                searchStart = first.upperBound
            }
        }
        return ranges
    }

    /// İlk kelimesi `firstRange`te olan kalıbın bittiği yer (son kelimenin eki hariç); eşleşmezse nil.
    private static func phraseEnd(_ words: [String], firstRange: Range<String.Index>,
                                  in sentence: String) -> String.Index? {
        var wordEnd = firstRange.upperBound
        for (i, word) in words.enumerated() {
            if i > 0 {
                // En az bir boşluk, sonra kelime tam o noktada.
                let gapEnd = sentence[wordEnd...].firstIndex { !$0.isWhitespace } ?? sentence.endIndex
                guard gapEnd > wordEnd,
                      let range = sentence.range(of: word, options: searchOptions.union(.anchored),
                                                 range: gapEnd..<sentence.endIndex)
                else { return nil }
                wordEnd = range.upperBound
            }
            let tail = sentence[wordEnd...].prefix { $0.isLetter }
            if !tail.isEmpty {
                guard word.count >= 3, isSuffix(tail.lowercased(), after: word) else { return nil }
            }
            if i == words.count - 1 { return wordEnd }
            wordEnd = tail.endIndex
        }
        return nil
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
