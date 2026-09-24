import Foundation

/// Kullanıcının yazdığı Türkçe cevabı kayıtlı anlamlarla karşılaştırır.
///
/// Hoşgörülü davranır: büyük/küçük harf, Türkçe karakterler (ş/s, ı/i…) ve
/// noktalama fark etmez. Kayıtta virgülle ayrılmış anlamlardan birini tutturmak
/// yeterlidir. Son kararı yine kullanıcı "Bildim / Bilemedim" ile verir.
///
/// Kullanıcının cevabı tek tahmindir: virgülle birkaç tahmin yazıp birinin tutmasıyla
/// doğru sayılmaz ("ben, sen, deneme"); virgüllü cevapta her parça tutmalıdır.
///
/// Kısmi cevap kelime kelime karşılaştırılır ("değişmeyen" ↔ "etkisi değişmeyen",
/// "kaydet" ↔ "kaydetmek"). Kökle kelime arasındaki fark bilinen bir Türkçe ek olmalı
/// ("kara" "karar"ı karşılamaz); eksik kalan kısım anlamı tersine çeviriyorsa
/// ("mümkün" ↔ "mümkün değil", "kayıt" ↔ "kayıtsız") doğru sayılmaz.
nonisolated enum AnswerChecker {
    private static let turkishLocale = Locale(identifier: "tr_TR")
    private static let meaningSeparators: Set<Character> = [",", ";", "/"]
    private static let minPartialLength = 4

    /// Tek başına olumsuzluk bildiren kelimeler (sadeleştirilmiş hâlleriyle).
    private static let negationWords: Set<String> = ["degil", "yok", "olmayan", "olmaz", "olmadan", "hic", "gayri"]
    /// Kelimeyi olumsuz yapan ekler: -sız, -maz, -mayan, -madan…
    private static let negationSuffixes = ["siz", "suz", "mez", "maz", "meyen", "mayan", "memek", "mamak", "meden", "madan"]

    static func isCorrect(_ answer: String, expected: String) -> Bool {
        let given = meanings(in: answer)
        let valid = meanings(in: expected)
        guard !given.isEmpty else { return false }
        return given.allSatisfy { guess in
            valid.contains { meaning in
                guess == meaning
                    || (min(guess.count, meaning.count) >= minPartialLength
                        && (covers(guess, meaning) || covers(meaning, guess)))
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

    // MARK: - Kısmi eşleşme

    /// `part`ın her kelimesi `whole`da bir kelimeyle eşleşiyor ve `whole`da artakalan
    /// kelimeler anlamı olumsuza çevirmiyorsa true.
    private static func covers(_ part: String, _ whole: String) -> Bool {
        var remaining = whole.split(separator: " ").map(String.init)
        for word in part.split(separator: " ").map(String.init) {
            guard let index = remaining.firstIndex(where: { wordsMatch(word, $0) }) else { return false }
            remaining.remove(at: index)
        }
        return !remaining.contains(where: isNegation)
    }

    /// Aynı kelime ya da biri diğerinin kökü ("kaydet" ↔ "kaydetmek"); fark bilinen Türkçe eklerden
    /// oluşmalı ("kara" ↔ "karar" değil) ve olumsuzluk eki olamaz.
    private static func wordsMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let (short, long) = a.count <= b.count ? (a, b) : (b, a)
        guard short.count >= minPartialLength, long.hasPrefix(short) else { return false }
        let tail = long.dropFirst(short.count)
        let negatingTail = tail.hasPrefix("siz") || tail.hasPrefix("suz")
            || ((tail.hasPrefix("me") || tail.hasPrefix("ma")) && !tail.hasPrefix("mek") && !tail.hasPrefix("mak"))
        return !negatingTail && isSuffixChain(Substring(tail))
    }

    /// Kökün ardına gelebilecek Türkçe ekler, sadeleştirilmiş hâlleriyle (ı→i, ü→u, ş→s…).
    /// Ünlü uyumu ve kaynaştırma ünsüzlü (y, n, s) biçimler ayrı ayrı yazılır.
    static let turkishSuffixes: Set<String> = [
        // Mastar: -mek/-mak
        "mek", "mak",
        // Belirtme: -i/-ı/-u/-ü, -yi, -ni, -si
        "i", "u", "yi", "yu", "ni", "nu", "si", "su",
        // Yönelme: -e/-a, -ye/-ya, -ne/-na
        "e", "a", "ye", "ya", "ne", "na",
        // Bulunma/ayrılma: -de/-da/-te/-ta, -den/-dan/-ten/-tan, -nde/-nda
        "de", "da", "te", "ta", "den", "dan", "ten", "tan", "nde", "nda", "nden", "ndan",
        // Çoğul: -ler/-lar
        "ler", "lar",
        // İlgi: -in/-un, -nin/-nun
        "in", "un", "nin", "nun",
        // Vasıta: -le/-la, -yle/-yla
        "le", "la", "yle", "yla",
        // Yapım: -lik/-lık/-luk/-lük, -li/-lı/-lu/-lü, -ci/-cı/-çi, -ce/-ca/-çe, -sel/-sal
        "lik", "luk", "li", "lu", "ci", "cu", "ce", "ca", "sel", "sal",
        // Sıfat-fiil ve fiil ekleri: -en/-an, -yen/-yan, -mis, -ecek/-acak, -di/-ti, -il/-in (edilgen), -is (iş)
        "en", "an", "yen", "yan", "mis", "mus", "ecek", "acak", "di", "du", "ti", "tu", "il", "ul", "is", "us",
        // Bildirme: -dir/-dır/-tir
        "dir", "dur", "tir", "tur",
        // İyelik: -im, -in, -imiz, -leri/-ları
        "im", "um", "imiz", "umuz", "leri", "lari",
    ]

    /// `tail` en fazla üç bilinen ekin art arda gelmesinden oluşuyor mu ("lerde", "liği", "mek").
    private static func isSuffixChain(_ tail: Substring, depth: Int = 0) -> Bool {
        if tail.isEmpty { return true }
        guard depth < 3 else { return false }
        for length in 1...min(4, tail.count) {
            let head = String(tail.prefix(length))
            if turkishSuffixes.contains(head), isSuffixChain(tail.dropFirst(length), depth: depth + 1) {
                return true
            }
        }
        return false
    }

    private static func isNegation(_ word: String) -> Bool {
        negationWords.contains(word) || negationSuffixes.contains { word.hasSuffix($0) }
    }
}
