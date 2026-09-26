import Foundation

/// Kelimeler arasındaki ilişkiler: aynı kayıt mı, biri ötekinin kalıbı mı.
///
/// Karşılaştırma `AnswerChecker.fold` ile yapılır; büyük/küçük harf, Türkçe karakter ve
/// noktalama fark etmez. İlişki tam kelimeler üzerinden kurulur: "take" ile
/// "take into account" ilişkilidir, "art" ile "start" değildir.
nonisolated enum WordMatcher {
    static func isSame(_ a: String, _ b: String) -> Bool {
        let key = AnswerChecker.fold(a)
        return !key.isEmpty && key == AnswerChecker.fold(b)
    }

    /// Biri ötekinin içinde ardışık kelimeler olarak geçiyorsa (aynı değillerse) true.
    static func isRelated(_ a: String, _ b: String) -> Bool {
        let first = tokens(a), second = tokens(b)
        guard !first.isEmpty, !second.isEmpty, first != second else { return false }
        let (short, long) = first.count <= second.count ? (first, second) : (second, first)
        guard short.count < long.count else { return false }
        return (0...(long.count - short.count)).contains { start in
            Array(long[start..<(start + short.count)]) == short
        }
    }

    /// Mevcut Türkçe anlamların sonuna yenilerini ekler; aynı anlam iki kez yazılmaz.
    static func mergedMeanings(existing: String, adding: String) -> String {
        let known = Set(AnswerChecker.meanings(in: existing))
        var seen = known
        let new = adding
            .split(whereSeparator: { ",;/".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert(AnswerChecker.fold($0)).inserted }
        let base = existing.trimmingCharacters(in: .whitespaces)
        return ([base].filter { !$0.isEmpty } + new).joined(separator: ", ")
    }

    /// Kopya kayıtlar birleşirken iki cümleyi de korur: aynıysa (ya da biri boşsa) tek cümle, farklıysa
    /// kalan kaydınki önce olmak üzere alt alta. Şemada tek cümle alanı olduğu için ikisi de burada durur;
    /// kullanıcı düzenlerken istemediğini siler. Zaten içinde geçen cümle yeniden eklenmez.
    static func mergedExamples(_ kept: String, _ other: String) -> String {
        let first = kept.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = other.trimmingCharacters(in: .whitespacesAndNewlines)
        if second.isEmpty || first.contains(second) { return first }
        if first.isEmpty { return second }
        return first + "\n" + second
    }

    private static func tokens(_ text: String) -> [String] {
        AnswerChecker.fold(text).split(separator: " ").map(String.init)
    }
}

extension Word {
    /// Defterdeki, bu kelimenin kalıbı olan ya da bu kalıbın içinde geçen kayıtlar.
    func related(in words: [Word]) -> [Word] {
        words.filter { $0.persistentModelID != persistentModelID && WordMatcher.isRelated($0.english, english) }
            .sorted { $0.english.count < $1.english.count }
    }

    /// Aynı kelime yeniden eklenirken yeni bilgileri bu kayda katar: yeni anlamlar eklenir, boş cümle
    /// doldurulur; kayıtta başka bir cümle varsa yenisi yalnızca `replacingExample` ile yazılır.
    /// İlerleme (hafıza, sıradaki tekrar) değişmez.
    func absorb(turkish: String, example: String, replacingExample: Bool = false) {
        self.turkish = WordMatcher.mergedMeanings(existing: self.turkish, adding: turkish)
        if takesExample(example, replacing: replacingExample) {
            self.example = example.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// `absorb` bu kayıtta bir şey değiştirir mi.
    func wouldAbsorb(turkish: String, example: String, replacingExample: Bool = false) -> Bool {
        addsMeanings(turkish) || takesExample(example, replacing: replacingExample)
    }

    /// `absorb` bu kayda yeni bir anlam ekler mi.
    func addsMeanings(_ turkish: String) -> Bool {
        WordMatcher.mergedMeanings(existing: self.turkish, adding: turkish) != self.turkish.trimmingCharacters(in: .whitespaces)
    }

    /// Kayıtta dolu bir cümle var ve gelen cümle ondan farklı: hangisinin kalacağı seçilmeli.
    func hasDifferentExample(_ example: String) -> Bool {
        let current = self.example.trimmingCharacters(in: .whitespacesAndNewlines)
        let incoming = example.trimmingCharacters(in: .whitespacesAndNewlines)
        return !current.isEmpty && !incoming.isEmpty && current != incoming
    }

    /// `absorb` gelen cümleyi bu kayda yazar mı: kayıt boşsa ya da farklı cümlenin yerine geçmesi seçildiyse.
    func takesExample(_ example: String, replacing: Bool) -> Bool {
        let incoming = example.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else { return false }
        return self.example.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (replacing && hasDifferentExample(incoming))
    }
}
