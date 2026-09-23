import Foundation

/// Seçmeli oyunların (Çoktan Seçmeli, Boşluğu Doldur) seçenek üretimi.
nonisolated enum ChoiceQuiz {
    struct Candidate: Equatable {
        /// Seçenekte gösterilecek metin.
        let text: String
        let source: String
        /// Kelimenin bütün anlamları (sadeleştirilmiş). Doğru cevapla ortak bir anlamı olan kelime
        /// yanlış seçenek olmaz: "stale: bayat, eskimiş" sorulurken "outdated: eskimiş" çıkmaz.
        let meanings: Set<String>

        /// `meanings` verilmezse yalnızca gösterilen metin kullanılır (ör. İngilizce seçenekler).
        init(text: String, source: String, meanings: [String] = []) {
            self.text = text
            self.source = source
            self.meanings = Set(meanings + [AnswerChecker.fold(text)]).subtracting([""])
        }

        /// Türkçe anlamı seçenek olan kelime: ilk anlamı gösterilir, bütün anlamları karşılaştırılır.
        init(turkish: String, source: String) {
            self.init(text: ChoiceQuiz.firstMeaning(turkish), source: source, meanings: AnswerChecker.meanings(in: turkish))
        }
    }

    /// İki kelimenin ortak bir anlamı var mı (Eşleştir'de aynı tahtaya düşmesinler diye).
    static func shareMeaning(_ a: String, _ b: String) -> Bool {
        !Set(AnswerChecker.meanings(in: a)).isDisjoint(with: AnswerChecker.meanings(in: b))
    }

    /// Kayıttaki ilk anlam, yazıldığı gibi: "eskimiş, güncel olmayan" → "eskimiş".
    static func firstMeaning(_ turkish: String) -> String {
        turkish.split(whereSeparator: { ",;/".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? turkish.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Doğru cevap ve `count − 1` yanlış seçenek, karışık sırayla.
    ///
    /// Yanlışlar önce doğru cevapla aynı kaynaktan (kitaptan) seçilir; doğru cevabın herhangi bir
    /// anlamını taşıyan kelime ya da birbiriyle aynı (sadeleştirilmiş) metin çıkmaz.
    /// Yeterli farklı seçenek yoksa daha az döner.
    static func options<G: RandomNumberGenerator>(
        answer: Candidate,
        others: [Candidate],
        count: Int = 4,
        using generator: inout G
    ) -> (options: [String], correctIndex: Int) {
        var used: Set<String> = [AnswerChecker.fold(answer.text)]
        let shuffled = others.shuffled(using: &generator)
        let sameSource = answer.source.isEmpty ? [] : shuffled.filter { $0.source == answer.source }
        let rest = shuffled.filter { answer.source.isEmpty || $0.source != answer.source }

        var wrong: [String] = []
        for candidate in sameSource + rest where wrong.count < count - 1 {
            let key = AnswerChecker.fold(candidate.text)
            guard !key.isEmpty, !used.contains(key), candidate.meanings.isDisjoint(with: answer.meanings) else { continue }
            used.insert(key)
            wrong.append(candidate.text)
        }
        let correctIndex = Int.random(in: 0...wrong.count, using: &generator)
        var options = wrong
        options.insert(answer.text, at: correctIndex)
        return (options, correctIndex)
    }
}
