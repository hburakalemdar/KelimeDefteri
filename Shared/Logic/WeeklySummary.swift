import Foundation

/// Son 7 günün özeti: kaç cevap, doğruluk, kaç kelime güçlendi, en çok zorlanılan kelimeler.
/// Cevap kayıtlarından hesaplanır; `ID` kelimeyi ayırt eden herhangi bir değer (ör. `PersistentIdentifier`).
///
/// "Güçlendi": son 7 günde en az bir kez doğru bilinen ve o haftaki son cevabı doğru olan kelime.
/// Doğru cevap hafıza dayanıklılığını artırır; son cevabı yanlış olan kelime zayıf kaldığı için sayılmaz.
nonisolated struct WeeklySummary<ID: Hashable> {
    struct Answer {
        let word: ID
        let date: Date
        let correct: Bool
    }

    struct HardWord: Equatable {
        let word: ID
        let wrong: Int
        let total: Int
    }

    static var dayCount: Int { 7 }
    static var hardestLimit: Int { 5 }

    /// Pencerenin ilk günü (6 gün önce, gün başı).
    let start: Date
    let answerCount: Int
    let correctCount: Int
    let strengthenedCount: Int
    /// En çok yanlış bilinen kelimeler (en fazla 5); hiç yanlışı olmayan kelime girmez.
    let hardest: [HardWord]
    /// Eskiden yeniye 7 gün: gün başı ve o günkü cevap sayısı.
    let days: [(day: Date, count: Int)]

    /// Doğru bilme oranı; hiç cevap yoksa `nil`.
    var accuracy: Double? { answerCount > 0 ? Double(correctCount) / Double(answerCount) : nil }

    init(answers: [Answer], now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(Self.dayCount - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let week = answers.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }

        self.start = start
        answerCount = week.count
        correctCount = week.count { $0.correct }

        var last: [ID: Bool] = [:]
        var wrong: [ID: Int] = [:]
        var total: [ID: Int] = [:]
        var lastSeen: [ID: Date] = [:]
        for answer in week {
            last[answer.word] = answer.correct
            total[answer.word, default: 0] += 1
            lastSeen[answer.word] = answer.date
            if !answer.correct { wrong[answer.word, default: 0] += 1 }
        }
        strengthenedCount = last.values.count { $0 }
        // Önce yanlış sayısı, sonra yanlış oranı, eşitse en son görülen önde (kararlı sıra).
        hardest = wrong
            .map { HardWord(word: $0.key, wrong: $0.value, total: total[$0.key] ?? $0.value) }
            .sorted { lhs, rhs in
                if lhs.wrong != rhs.wrong { return lhs.wrong > rhs.wrong }
                let lhsRate = Double(lhs.wrong) / Double(lhs.total)
                let rhsRate = Double(rhs.wrong) / Double(rhs.total)
                if lhsRate != rhsRate { return lhsRate > rhsRate }
                return (lastSeen[lhs.word] ?? .distantPast) > (lastSeen[rhs.word] ?? .distantPast)
            }
            .prefix(Self.hardestLimit)
            .map { $0 }

        let counts = DailyGoal.dayCounts(week.map(\.date), calendar: calendar)
        days = (0 ..< Self.dayCount).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start).map { (day: $0, count: counts[$0] ?? 0) }
        }
    }
}
