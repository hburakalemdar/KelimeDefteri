import Foundation
import SwiftData

/// Bir cevabı kelimeye işler: hafıza motorunu uygular, sayaçları artırır, `ReviewLog` yazar.
/// Bütün oyunlar ve Mac'teki çalışma cevaplarını buradan geçirir.
///
/// `updatesMemory` false ise (aynı turda aynı kelimeye verilen ikinci ve sonraki cevaplar) hafıza
/// değişmez; cevap yalnızca sayaçlara ve geçmişe yazılır. Yoksa turda birkaç kez bilinmeyen kelimenin
/// dayanıklılığı her yanlışta yeniden düşerdi.
///
/// Aynı takvim gününde hafızayı yalnızca ilk cevap değiştirir (`lastReviewedAt` bugünse `updatesMemory`
/// yok sayılır): gün içindeki tekrarlar dayanıklılığı şişirmez ya da her yanlışta yeniden düşürmez.
/// Sonraki cevaplar sayaçlara ve geçmişe yazılır; yanlışsa kelime yine zayıf işaretlenir (S/D değişmez).
///
/// `clearsLapse` false ise (yanlış bilinen kelime hemen arkasından, arada başka kart olmadan doğru
/// bilindi) sonraki doğru cevap kelimeyi zayıflıktan çıkarmaz: az önce görülen cevap yazılmıştır.
enum ReviewRecorder {
    @discardableResult
    static func record(
        _ word: Word,
        grade: AnswerGrade,
        mode: GameMode,
        responseTime: Double,
        updatesMemory: Bool = true,
        clearsLapse: Bool = true,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ReviewLog? {
        // Başka yerde (ör. öteki cihazdan) silinmiş kelimeye cevap yazılmaz.
        guard !word.isDeleted else { return nil }
        MemoryMigration.migrate(word)
        let memoryBefore = word.memory(at: now)
        // Bugün zaten cevaplanmış kelimenin hafızası bugün bir daha değişmez.
        let answeredToday = word.lastReviewedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        let updatesMemory = updatesMemory && !answeredToday
        if updatesMemory {
            let result = Memory.review(
                stability: word.stability,
                difficulty: word.difficulty,
                lastReviewedAt: word.lastReviewedAt,
                grade: grade,
                weight: mode.weight,
                now: now
            )
            word.stability = result.stability
            word.difficulty = result.difficulty
            word.dueDate = result.due
            word.lastReviewedAt = now
        }
        if !grade.isCorrect {
            // Yanlış bilinen kelime doğru bilinene kadar zayıf kalır (Günlük Tekrar'a hemen girer).
            word.dueDate = Memory.lapseDue(stability: word.stability, memoryBefore: memoryBefore, now: now)
        } else if !updatesMemory, clearsLapse, let last = word.lastReviewedAt {
            // Bugün önce yanlış sonra doğru bilindi: tekrar zamanı motorun hesabına döner.
            word.dueDate = last.addingTimeInterval(word.stability * Memory.dayLength)
        }
        // Öğrenildiği ilk cevabın tarihi; zayıflayan ya da dayanıklılığı düşen kelimede silinir.
        if !word.isLearned {
            word.learnedAt = nil
        } else if word.learnedAt == nil {
            word.learnedAt = now
        }
        word.reviewCount += 1
        if grade.isCorrect { word.correctCount += 1 }

        // Depoya eklenmemiş kelimeye (yalnızca testlerde olur) kayıt bağlanamaz.
        guard let context = word.modelContext else { return nil }
        let log = ReviewLog(
            date: now, mode: mode.rawValue, correct: grade.isCorrect,
            grade: grade.rawValue, responseTime: max(responseTime, 0)
        )
        context.insert(log)
        log.word = word
        return log
    }
}
