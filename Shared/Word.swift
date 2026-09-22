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

    /// Leitner kutusu: 0 = yeni/bilinmiyor, `Leitner.maxBox` = öğrenildi.
    var box: Int = 0
    var dueDate: Date = Date.distantPast
    var createdAt: Date = Date.now
    var reviewCount: Int = 0
    var correctCount: Int = 0

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
