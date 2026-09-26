import Foundation

/// Yeni anlam tanıtımı (docs/SPEC-ANLAM.md): çalışılmış kelimeye sonradan eklenen anlam "bekleyen anlam"dır; hiçbir
/// yere yazılmaz, anlam tabanından (`meaningBaseline`) ve cevap kayıtlarından çıkarılır.
extension Word {
    /// Tabanı bir kez alır: kelime çalışılmışsa ve taban henüz yoksa o anki anlamlar. `turkish`'i değiştiren her yol
    /// bunu değiştirmeden önce çağırır; böylece tabansız eski kelimeye eklenen anlam tabana yutulmaz.
    func fillMeaningBaselineIfNeeded() {
        guard meaningBaseline == nil, !isNew else { return }
        meaningBaseline = turkish
    }

    /// Tabanda olmayan ve aynı anlamla hiç doğru cevaplanmamış anlamlar, kayıttaki sırayla. Yeni ya da tabansız
    /// kelimede boş. Metin kimliğiyle karşılaştırılır (sadeleştirilmiş): yazımı düzeltilen anlam yeniden bekleyen olur.
    var pendingMeanings: [String] {
        guard !isNew, let meaningBaseline else { return [] }
        let base = Set(AnswerChecker.meanings(in: meaningBaseline))
        let added = ChoiceQuiz.displayMeanings(turkish).filter { !base.contains(AnswerChecker.fold($0)) }
        // Kayıtlara ancak tabanda olmayan anlam varsa bakılır (defter taranırken ucuz kalsın).
        guard !added.isEmpty else { return [] }
        let known = Set((logs ?? []).filter { !$0.isDeleted && $0.correct }.map { AnswerChecker.fold($0.meaning) })
        return added.filter { !known.contains(AnswerChecker.fold($0)) }
    }

    /// Günlük Tekrar'da tanıtıma uygun mu: bekleyen anlam var ve bugün (04:00) tanıtım cevabı verilmemiş (yanlış
    /// tanıtım aynı gün tekrarlanmaz). Defterde yeterli çeldirici olup olmadığına çağıran bakar (`DailyMix.minimumMeanings`).
    func needsMeaningIntro(now: Date = .now) -> Bool {
        guard !pendingMeanings.isEmpty else { return false }
        return !(logs ?? []).contains { !$0.isDeleted && $0.isIntro && DayBoundary.isSameDay($0.date, now) }
    }

    /// Yazarak cevap sorusunun anlamı: sırası gelen (`meaningTurn`), bekleyen anlamlar hariç; hepsi bekleyense bütün
    /// anlamlar arasından. Üretim sorusu bilinen bir anlamla sorulur.
    var productionMeaning: String {
        let all = ChoiceQuiz.displayMeanings(turkish)
        let pending = Set(pendingMeanings.map(AnswerChecker.fold))
        let known = all.filter { !pending.contains(AnswerChecker.fold($0)) }
        let pool = known.isEmpty ? all : known
        guard !pool.isEmpty else { return turkish.trimmingCharacters(in: .whitespacesAndNewlines) }
        return pool[((meaningTurn % pool.count) + pool.count) % pool.count]
    }

    /// Yazılan cevabın tuttuğu anlam, yazıldığı gibi: önce `preferred` (sorulan anlam), sonra kayıttaki sırayla.
    /// Hiçbiri tutmuyorsa `nil`.
    func matchedMeaning(for answer: String, preferring preferred: String) -> String? {
        let meanings = ChoiceQuiz.displayMeanings(turkish)
        let key = AnswerChecker.fold(preferred)
        let ordered = meanings.filter { AnswerChecker.fold($0) == key } + meanings.filter { AnswerChecker.fold($0) != key }
        return ordered.first { AnswerChecker.isCorrect(answer, expected: $0) }
    }
}
