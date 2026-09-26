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

    /// Aynı kelime yeniden eklenirken yeni bilgileri bu kayda katar: yeni anlamlar eklenir, yeni cümleler de tutulur
    /// (zaten olan cümle yeniden eklenmez). Anlamı belirtilmemiş yeni cümle, bu eklemede tam olarak bir yeni anlam
    /// geldiyse ona bağlanır; yoksa belirsiz kalır. İlerleme (hafıza, sıradaki tekrar) değişmez.
    func absorb(turkish: String, sentences incoming: [(text: String, meaning: String)], now: Date = .now) {
        let added = newMeanings(in: turkish)
        // Taban eski anlamlarla alınır; eklenen anlam bekleyen olur (docs/SPEC-ANLAM.md §3).
        fillMeaningBaselineIfNeeded()
        self.turkish = WordMatcher.mergedMeanings(existing: self.turkish, adding: turkish)
        var inserted = false
        for (offset, sentence) in incoming.enumerated() where !hasSentence(sentence.text) {
            let meaning = sentence.meaning.isEmpty && added.count == 1 ? added[0] : sentence.meaning
            // Aynı anda eklenenler yazıldıkları sırada kalsın.
            inserted = insertSentence(sentence.text, meaning: meaning, createdAt: now.addingTimeInterval(Double(offset) / 1000)) != nil || inserted
        }
        // Kayda alınmamış eski cümle varsa ayna ona dokunmaz (eklenti göç yapmaz; bkz. `refreshExampleMirror`).
        if inserted { refreshExampleMirror() }
    }

    func absorb(turkish: String, example: String, now: Date = .now) {
        absorb(turkish: turkish, sentences: [(example, "")], now: now)
    }

    /// `absorb` bu kayıtta bir şey değiştirir mi.
    func wouldAbsorb(turkish: String, sentences: [String]) -> Bool {
        addsMeanings(turkish) || sentences.contains(where: addsSentence)
    }

    /// `absorb` bu kayda yeni bir anlam ekler mi.
    func addsMeanings(_ turkish: String) -> Bool {
        WordMatcher.mergedMeanings(existing: self.turkish, adding: turkish) != self.turkish.trimmingCharacters(in: .whitespaces)
    }

    /// `absorb` bu cümleyi ekler mi: dolu ve kelimede henüz yok.
    func addsSentence(_ text: String) -> Bool {
        !WordSentence.key(text).isEmpty && !hasSentence(text)
    }

    /// Kayıtta olmayan anlamlar, yazıldığı gibi (tekrarsız).
    func newMeanings(in turkish: String) -> [String] {
        let known = Set(AnswerChecker.meanings(in: self.turkish))
        return ChoiceQuiz.displayMeanings(turkish).filter { !known.contains(AnswerChecker.fold($0)) }
    }
}
