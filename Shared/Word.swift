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
        source: String = "",
        createdAt: Date = .now
    ) {
        self.english = english
        self.turkish = turkish
        self.definition = definition
        self.example = example
        self.source = source
        self.createdAt = createdAt
    }

    var isLearned: Bool { box >= Leitner.maxBox }

    func isDue(at date: Date = .now) -> Bool { dueDate <= date }
}
