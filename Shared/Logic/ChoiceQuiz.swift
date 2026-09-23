import Foundation

/// Seçmeli oyunların (Çoktan Seçmeli, Boşluğu Doldur) seçenek üretimi.
nonisolated enum ChoiceQuiz {
    struct Candidate: Equatable {
        /// Seçenekte gösterilecek metin.
        let text: String
        let source: String
    }

    /// Kayıttaki ilk anlam, yazıldığı gibi: "eskimiş, güncel olmayan" → "eskimiş".
    static func firstMeaning(_ turkish: String) -> String {
        turkish.split(whereSeparator: { ",;/".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? turkish.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Doğru cevap ve `count − 1` yanlış seçenek, karışık sırayla.
    ///
    /// Yanlışlar önce doğru cevapla aynı kaynaktan (kitaptan) seçilir; doğru cevapla ya da
    /// birbiriyle aynı (sadeleştirilmiş) metin iki kez çıkmaz. Yeterli farklı seçenek yoksa daha az döner.
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
            guard !key.isEmpty, !used.contains(key) else { continue }
            used.insert(key)
            wrong.append(candidate.text)
        }
        let correctIndex = Int.random(in: 0...wrong.count, using: &generator)
        var options = wrong
        options.insert(answer.text, at: correctIndex)
        return (options, correctIndex)
    }
}
