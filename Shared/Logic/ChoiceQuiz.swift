import Foundation

/// Seçmeli oyunların (Çoktan Seçmeli, Boşluğu Doldur) seçenek üretimi.
nonisolated enum ChoiceQuiz {
    struct Candidate: Equatable {
        /// Seçenekte gösterilecek metin.
        let text: String
        /// Kelimenin bütün anlamları (sadeleştirilmiş). Doğru cevapla ortak bir anlamı olan kelime
        /// yanlış seçenek olmaz: "stale: bayat, eskimiş" sorulurken "outdated: eskimiş" çıkmaz.
        let meanings: Set<String>

        /// `meanings` verilmezse yalnızca gösterilen metin kullanılır (ör. İngilizce seçenekler).
        init(text: String, meanings: [String] = []) {
            self.text = text
            self.meanings = Set(meanings + [AnswerChecker.fold(text)]).subtracting([""])
        }

        /// Türkçe anlamı seçenek olan kelime: `turn`. anlamı gösterilir (bkz. `meaning(_:turn:)`; yanlış
        /// seçeneklerde 0, yani ilk anlam), bütün anlamları karşılaştırılır.
        init(turkish: String, turn: Int = 0) {
            self.init(text: ChoiceQuiz.meaning(turkish, turn: turn), meanings: AnswerChecker.meanings(in: turkish))
        }
    }

    /// İki kelimenin ortak bir anlamı var mı (Eşleştir'de aynı tahtaya düşmesinler diye).
    static func shareMeaning(_ a: String, _ b: String) -> Bool {
        !Set(AnswerChecker.meanings(in: a)).isDisjoint(with: AnswerChecker.meanings(in: b))
    }

    /// Kayıttaki ilk anlam, yazıldığı gibi: "eskimiş, güncel olmayan" → "eskimiş".
    static func firstMeaning(_ turkish: String) -> String {
        meaning(turkish, turn: 0)
    }

    /// Kayıttaki anlamlar yazıldığı gibi, sırayla; sadeleştirilmiş hâli aynı olan tekrarlar bir kez.
    static func displayMeanings(_ turkish: String) -> [String] {
        var seen: Set<String> = []
        return turkish.split(whereSeparator: { ",;/".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(AnswerChecker.fold($0)).inserted }
    }

    /// Anlamlar arasında `turn` sırasındaki (anlam sayısına göre dönerek): "o kadar, bu tür, öyle" için
    /// 0 → "o kadar", 1 → "bu tür", 3 → yine "o kadar". Anlam ayrılamazsa kaydın kendisi.
    static func meaning(_ turkish: String, turn: Int) -> String {
        let meanings = displayMeanings(turkish)
        guard !meanings.isEmpty else { return turkish.trimmingCharacters(in: .whitespacesAndNewlines) }
        let count = meanings.count
        return meanings[((turn % count) + count) % count]
    }

    /// Doğru cevap ve `count − 1` yanlış seçenek, karışık sırayla.
    ///
    /// Yanlışlar defterdeki diğer kelimelerden rastgele seçilir; doğru cevabın herhangi bir
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

        var wrong: [String] = []
        for candidate in shuffled where wrong.count < count - 1 {
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

extension Word {
    /// Birden çok anlamlı kelimede sorulacak anlamın sırası: cevap kaydı sayısı. Her cevapta bir artar, böylece
    /// aynı anlam art arda sorulmaz; kayıtlar iCloud'la eşitlendiği için her cihazda aynıdır, ek alan gerekmez.
    /// (`answerCount` değil: Leitner döneminden kalan büyük sayaç kayıt sayısını geçene dek sabit kalırdı.)
    var meaningTurn: Int { logs?.count ?? 0 }

    /// Oyunlarda ve widget'ta gösterilecek anlam: sırası gelen (`meaningTurn`).
    var askedMeaning: String { ChoiceQuiz.meaning(turkish, turn: meaningTurn) }

    /// Sorulan kelimenin doğru cevabı: sırası gelen anlamı gösterilir, bütün anlamları karşılaştırılır.
    var askedCandidate: ChoiceQuiz.Candidate { ChoiceQuiz.Candidate(turkish: turkish, turn: meaningTurn) }
}
