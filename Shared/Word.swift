import Foundation
import SwiftData

/// Kitapta karşılaşılan bir kelime ve tekrar durumu.
///
/// Tüm alanların varsayılan değeri var; ileride iCloud (CloudKit) eşitlemesi
/// açıldığında model değişikliği gerekmesin diye.
@Model
final class Word {
    var english: String = ""
    var turkish: String = ""
    var definition: String = ""
    var example: String = ""
    /// Kaynak kitap. Artık kullanılmıyor (kitaplar çoğunlukla PDF'ten okunuyor, ad hiç dolmuyordu);
    /// CloudKit şemasından alan silinemediği için duruyor.
    var source: String = ""

    /// Eski Leitner kutusu. Artık yazılmaz; yalnızca hafıza değerlerine tek seferlik geçişte okunur.
    var box: Int = 0
    /// Sıradaki tekrar zamanı; hatırlatma ve sıralama bunu kullanır.
    var dueDate: Date = Date.distantPast
    var createdAt: Date = Date.now
    var reviewCount: Int = 0
    var correctCount: Int = 0

    /// Hafıza dayanıklılığı (gün). 0 = hiç çalışılmamış.
    var stability: Double = 0
    /// Zorluk: 1 (kolay) … 10 (zor).
    var difficulty: Double = 5
    var lastReviewedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \ReviewLog.word)
    var logs: [ReviewLog]?

    init(
        english: String,
        turkish: String,
        definition: String = "",
        example: String = "",
        createdAt: Date = .now
    ) {
        self.english = english
        self.turkish = turkish
        self.definition = definition
        self.example = example
        self.createdAt = createdAt
    }

    func isDue(at date: Date = .now) -> Bool { dueDate <= date }
}

// MARK: - Hafıza

extension Word {
    /// Hiç çalışılmamış kelime; hafıza yüzdesi yerine "Yeni" gösterilir.
    var isNew: Bool { stability <= 0 }

    /// Şu anki hatırlama ihtimali (0…1); yeni kelimede `nil`.
    /// Son tekrar zamanı bilinmiyorsa eklendiği andan sayılır.
    ///
    /// Yanlış cevaptan sonra tekrar zamanı son tekrarın da gerisine konur (`Memory.lapseDue`);
    /// hafıza doğru bilinene kadar oradan sayılır ve düşük görünür.
    func memory(at date: Date = .now) -> Double? {
        guard !isNew else { return nil }
        let start = isLapsed ? dueDate.addingTimeInterval(-stability * Memory.dayLength) : (lastReviewedAt ?? createdAt)
        let elapsed = date.timeIntervalSince(start) / Memory.dayLength
        return Memory.retrievability(elapsedDays: elapsed, stability: stability)
    }

    /// Son cevap yanlıştı ve kelime henüz doğru bilinmedi. Normalde sıradaki tekrar son tekrardan
    /// sonradır; yanlış cevaptan sonra ondan önceye konur.
    var isLapsed: Bool {
        guard let lastReviewedAt, dueDate > .distantPast else { return false }
        return dueDate < lastReviewedAt
    }

    /// Tekrara ihtiyacı olan kelime: yeni ya da hatırlama ihtimali %90'ın altına inmiş.
    func isWeak(at date: Date = .now) -> Bool {
        guard let memory = memory(at: date) else { return true }
        return memory < Memory.targetRetention
    }

    var isWeak: Bool { isWeak() }

    /// Üç haftadan uzun süre akılda kalan kelime öğrenilmiş sayılır; yanlış bilinip henüz doğru
    /// bilinmemiş kelime (zayıf) öğrenilmiş sayılmaz.
    var isLearned: Bool { stability >= 21 && !isLapsed }
}

// MARK: - Sayılar

extension Word {
    /// Toplam cevap sayısı. İki cihazda aynı anda artan sayaçta biri kaybolabilir (iCloud'da son yazan
    /// kazanır) ama cevap kayıtları kaybolmaz; kayıtlardan önceki (Leitner dönemi) cevaplar ise yalnızca
    /// sayaçta var. Bu yüzden hangisi büyükse o alınır.
    var answerCount: Int { max(reviewCount, logs?.count ?? 0) }

    /// Doğru cevap sayısı; `answerCount` ile aynı kural.
    var correctAnswerCount: Int { max(correctCount, logs?.count(where: \.correct) ?? 0) }
}
