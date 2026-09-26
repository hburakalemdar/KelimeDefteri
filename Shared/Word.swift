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
    /// İngilizce tanım. Artık kullanılmıyor (elle yazılması gerekiyordu, pratikte boş kalıyordu);
    /// CloudKit şemasından alan silinemediği için duruyor.
    var definition: String = ""
    /// İlk cümlenin aynası: eski sürümler yalnızca bu alanı görür. Asıl cümleler `sentences`te
    /// (bkz. `WordSentences.swift`, `docs/SPEC-CUMLE.md`).
    var example: String = ""
    /// Yeni sürümün `example`'a en son yazdığı değer; `nil` = eski `example` henüz cümle kaydına alınmadı.
    /// `example` bundan farklıysa onu eski bir sürüm yazmıştır ve yeni cümle olarak alınır.
    var exampleMirror: String? = nil
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
    /// Motorun çıpası (büyüme hesabının başlangıç günü, 04:00). Tanıma cevabıyla ilerlemez;
    /// "son görülme" için kelimenin en güncel cevap kaydına bakılır.
    var lastReviewedAt: Date?
    /// Kelimenin öğrenilmiş sayılmaya başladığı günün başı (04:00); hiç öğrenilmediyse `nil`.
    var learnedAt: Date? = nil
    /// Zayıflık günü (yanlış bilinen gün, 04:00); zayıf değilse `nil`.
    var lapsedAt: Date? = nil

    // Hafıza alanları (`stability` … `lapsedAt`) `Memory.replay`in önbelleğidir; asıl kaynak bu taban
    // ve ondan sonraki cevap kayıtlarıdır (bkz. `MemoryCache`, `MemoryMigration.migrateBaseIfNeeded`).
    var baseStability: Double = 0
    var baseDifficulty: Double = 5
    var baseDueDate: Date = Date.distantPast
    var baseLapsedAt: Date? = nil
    var baseAnchorAt: Date? = nil
    var baseLearnedAt: Date? = nil
    /// Tabanın geçerli olduğu an; `nil` = henüz taban göçünden geçmedi, `.distantPast` = boş taban.
    var baseAt: Date? = nil
    /// Kelime ilk çalışıldığında `turkish`'in kopyası; `nil` = henüz alınmadı. Yalnız `nil` iken bir kez yazılır
    /// (`fillMeaningBaselineIfNeeded`). Sonradan eklenen anlam bunda yoksa "bekleyen anlam"dır (docs/SPEC-ANLAM.md).
    var meaningBaseline: String? = nil
    @Relationship(deleteRule: .cascade, inverse: \ReviewLog.word)
    var logs: [ReviewLog]?
    @Relationship(deleteRule: .cascade, inverse: \WordSentence.word)
    var sentences: [WordSentence]?

    init(
        english: String,
        turkish: String,
        example: String = "",
        createdAt: Date = .now
    ) {
        self.english = english
        self.turkish = turkish
        self.example = example
        self.createdAt = createdAt
    }

    func isDue(at date: Date = .now) -> Bool { dueDate <= date }
}

// MARK: - Hafıza

extension Word {
    /// Hiç çalışılmamış kelime; hafıza yüzdesi yerine "Yeni" gösterilir.
    var isNew: Bool { stability <= 0 }

    /// Şu anki hatırlama ihtimali (0…1); yeni kelimede `nil`. Çıpadan gerçek (kesirli) zamanla sayılır;
    /// zayıf kelimede en fazla %50.
    func memory(at date: Date = .now) -> Double? {
        guard !isNew else { return nil }
        let start = lastReviewedAt ?? createdAt
        let elapsed = date.timeIntervalSince(start) / Memory.dayLength
        let memory = Memory.retrievability(elapsedDays: elapsed, stability: stability)
        return isLapsed ? min(memory, Memory.lapseMemory) : memory
    }

    /// Yanlış bilinip henüz toparlanmamış kelime (turuncu halka, "Tekrar edilecek").
    var isLapsed: Bool { lapsedAt != nil }

    /// Dayanıklılığı üç haftayı geçen ve zayıf olmayan kelime öğrenilmiş sayılır (canlı; `learnedAt`ten ayrı).
    var isLearned: Bool { stability >= Memory.learnedStability && !isLapsed }
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
