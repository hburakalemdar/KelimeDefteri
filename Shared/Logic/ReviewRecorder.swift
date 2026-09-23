import Foundation
import SwiftData

/// Bir cevabı kelimeye işler: hafıza motorunu uygular, sayaçları artırır, `ReviewLog` yazar.
/// Bütün oyunlar ve Mac'teki çalışma cevaplarını buradan geçirir.
enum ReviewRecorder {
    @discardableResult
    static func record(
        _ word: Word,
        grade: AnswerGrade,
        mode: GameMode,
        responseTime: Double,
        now: Date = .now
    ) -> ReviewLog? {
        MemoryMigration.migrate(word)
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
