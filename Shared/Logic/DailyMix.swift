import Foundation

/// Günlük Tekrar'ın soru karışımı (Günlük Tekrar, Tanış ve Yine de Çalış turları): yeni ve zayıf kelime önce
/// Çoktan Seçmeli ile ısınır; araya başka kelimeler girdikten sonra üretimle (harfleri sığıyorsa Harfleri Diz,
/// yoksa yazarak) sorulur. Diğer kelimeler bugünkü gibi yalnız yazarak sorulur. Her kelime turdan üretimle çıkar.
/// Ayrıntı: docs/SPEC-OYUN.md §5.11.
nonisolated enum DailyMix {
    /// Isınma sorusunun türü.
    static let warmupMode = GameMode.multipleChoice

    /// Isınma için defterde gereken farklı anlam sayısı (doğru şık + 3 çeldirici).
    static let minimumMeanings = 4

    /// Isınma sorulur mu: yeni ya da zayıf kelime, bugün ısınması zaten yapılmamışsa ve çeldirici yetiyorsa.
    static func needsWarmup(isNew: Bool, isLapsed: Bool, pendingProduction: Bool, deckMeanings: Int) -> Bool {
        (isNew || isLapsed) && !pendingProduction && deckMeanings >= minimumMeanings
    }

    /// Üretim sorusu Harfleri Diz mi (en fazla 14 harf), yoksa yazarak mı (uzun ifade).
    static func productionUsesLetters(english: String) -> Bool {
        (1...GameDeck.maxLetters).contains(GameDeck.letterCount(english))
    }

    /// Bugün (04:00 sınırıyla) ısınması yapılmış ama üretimi yapılmamış kelime: yarıda bırakılan turdan kalır,
    /// sonraki Günlük Tekrar'a girer ve doğrudan üretimle sorulur. Bugün Çoktan Seçmeli cevabı olup hiç üretim
    /// cevabı olmayan, ısınmaya uygun kelime: bugün yeniydi ya da zayıf. (Çoktan Seçmeli oyunu ve widget da aynı
    /// türle yazdığı için onlarda tanınan yeni/zayıf kelime de üretim için Günlük Tekrar'a gelir.)
    ///
    /// `anchoredToday`: kelimenin çıpası (`Word.lastReviewedAt`) bugün mü. "Bugün yeniydi" bundan okunur, ilk
    /// kaydın tarihinden değil: ilk günün cevabı çıpayı o günün başına koyar, tanıma cevabı çıpayı sonra
    /// ilerletmez; çıpayı bugüne getiren tek şey bugünkü üretim cevabıdır, o da bekleyeni zaten kapatır. Göç etmiş
    /// (tabanı olan, kaydı olmayan) eski kelimenin bugünkü ilk kaydı onu yeni yapmaz; çıpası eski kalır.
    static func isPendingProduction(
        logs: [(date: Date, mode: String)], isLapsed: Bool, anchoredToday: Bool, now: Date, calendar: Calendar = .current
    ) -> Bool {
        guard isLapsed || anchoredToday else { return false }
        let today = logs.filter { DayBoundary.isSameDay($0.date, now, calendar: calendar) }
        return today.contains(where: { $0.mode == warmupMode.rawValue })
            && !today.contains(where: { GameMode(rawValue: $0.mode)?.isProduction == true })
    }

    /// Adımların başlangıç sırası: ısınma adımları mümkünse son iki sıraya düşmez (üretimle arası açılabilsin).
    /// İlk sıraya dokunulmaz (önceki turun ilk kelimesinden kaçınma korunur). Dönen dizi yeni sıradaki eski yerler.
    static func order(warmups: [Bool], tail: Int = 2) -> [Int] {
        var order = Array(warmups.indices)
        let tailStart = max(0, order.count - tail)
        for position in tailStart..<order.count where warmups[order[position]] {
            guard let swap = (1..<max(1, tailStart)).reversed().first(where: { !warmups[order[$0]] }) else { break }
            order.swapAt(position, swap)
        }
        return order
    }

    // MARK: Tahmini süre

    /// Soru başına ortalama süre (saniye): seçmeli kısa, Harfleri Diz orta, yazarak cevap uzun.
    static let choiceSeconds = 8.0
    static let lettersSeconds = 18.0
    static let recallSeconds = RoundText.secondsPerWord

    /// Bir kelimenin turdaki tahmini süresi (yeniden sorma hariç).
    static func seconds(warmup: Bool, pendingProduction: Bool, letters: Bool) -> Double {
        let production = letters ? lettersSeconds : recallSeconds
        if warmup { return choiceSeconds + production }
        return pendingProduction ? production : recallSeconds
    }

    /// Yeni anlam tanıtımıyla giren kelimenin tahmini süresi: tanıtım (seçmeli), ardından zayıf ya da üretim
    /// bekleyen kelimede üretim, vadesi gelmiş kelimede yazarak cevap; yalnız tanıtım için gelmişse başka adım yok.
    static func introSeconds(production: Bool, recall: Bool, letters: Bool) -> Double {
        if production { return choiceSeconds + (letters ? lettersSeconds : recallSeconds) }
        return choiceSeconds + (recall ? recallSeconds : 0)
    }
}
