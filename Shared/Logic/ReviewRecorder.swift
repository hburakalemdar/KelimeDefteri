import Foundation
import SwiftData

/// Bir cevabı kelimeye işler: `ReviewLog` yazar, sonra kelimenin hafızasını bütün cevaplarından yeniden
/// hesaplar (`MemoryCache.refresh`, SPEC-MOTOR2 §2.1). Bütün oyunlar, widget, bildirim ve Mac'teki çalışma
/// cevaplarını buradan geçirir.
///
/// Aynı gün birden çok cevap motorda birlikte değerlendirilir (günün notu, §2.4); bu yüzden "turdaki ilk
/// cevap" ya da "aynı gün" gibi korumalar burada yok. Sayaçlar (`reviewCount`, `correctCount`) artık
/// artırılmaz; `Word.answerCount` cevap kayıtlarından okur. `meaning`: cevabın gösterdiği anlam (seçmelide doğru
/// şık, soru kurulurken alınan); bekleyen anlamı gösteren tanıma cevabı tanıtım sayılır (docs/SPEC-ANLAM.md §4).
enum ReviewRecorder {
    @discardableResult
    static func record(
        _ word: Word,
        grade: AnswerGrade,
        mode: GameMode,
        responseTime: Double,
        meaning: String = "",
        now: Date = .now
    ) -> ReviewLog? {
        // Başka yerde (ör. öteki cihazdan) silinmiş kelimeye cevap yazılmaz.
        guard !word.isDeleted else { return nil }
        // Göç, kayıt eklenmeden önce: hiç cevaplanmamış kelimenin tabanı boş olur, bu cevap oynatılır.
        MemoryMigration.migrateBaseIfNeeded(word, now: now)
        // Depoya eklenmemiş kelimeye (yalnızca testlerde olur) kayıt bağlanamaz.
        guard let context = word.modelContext else { return nil }
        // Anlam tabanı ilk kayıttan önce (yeni kelimede de): taban = o anki anlamlar (docs/SPEC-ANLAM.md §3).
        if word.meaningBaseline == nil { word.meaningBaseline = word.turkish }
        // Tanıtım: tanıma sorusunda bekleyen anlam gösterildi. Motor bu kaydı oynatmaz (`MemoryCache`).
        let key = AnswerChecker.fold(meaning)
        let isIntro = !mode.isProduction && !key.isEmpty
            && word.pendingMeanings.contains { AnswerChecker.fold($0) == key }
        let log = ReviewLog(
            date: now, mode: mode.rawValue, correct: grade.isCorrect,
            grade: grade.rawValue, responseTime: max(responseTime, 0)
        )
        log.meaning = meaning
        log.isIntro = isIntro
        context.insert(log)
        log.word = word
        MemoryCache.refresh(word, now: now)
        return log
    }

    /// Kaydı geri alır: kayıt silinir, kelimenin hafızası kalan cevaplardan yeniden hesaplanır.
    static func undo(_ log: ReviewLog, now: Date = .now) {
        let word = log.word
        log.word = nil
        log.modelContext?.delete(log)
        if let word { MemoryCache.refresh(word, now: now) }
    }
}
