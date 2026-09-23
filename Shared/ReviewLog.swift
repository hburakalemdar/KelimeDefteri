import Foundation
import SwiftData

/// Bir kelimeye verilen tek bir cevabın kaydı: ne zaman, hangi oyunda, nasıl.
///
/// Kelime istatistiği ve geçmiş bu kayıtlardan çıkar. Tüm alanların varsayılan değeri var;
/// CloudKit yalnızca ekleme kabul ettiği için.
@Model
final class ReviewLog {
    var date: Date = Date.now
    /// Oyun türü (`GameMode.rawValue`).
    var mode: String = ""
    var correct: Bool = false
    /// Cevaptan çıkarılan not (`AnswerGrade.rawValue`, 1…4).
    var grade: Int = 0
    /// Kartın gösterilmesinden cevabın açılmasına kadar geçen süre (saniye).
    var responseTime: Double = 0
    var word: Word?

    init(date: Date = .now, mode: String, correct: Bool, grade: Int, responseTime: Double) {
        self.date = date
        self.mode = mode
        self.correct = correct
        self.grade = grade
        self.responseTime = responseTime
    }
}
