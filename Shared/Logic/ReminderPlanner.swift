import Foundation

/// Önümüzdeki günlerin hatırlatmalarını planlar: her gün seçilen saatte Günlük Tekrar'ın kaç
/// kelime soracağını hesaplar (vadesi gelmiş çalışılmış kelimeler en fazla 20, yeniler günde en fazla 5,
/// toplam en fazla 20). Sorulacak kelime olmayan günlere bildirim düşmez.
///
/// Bildirim içeriği planlandığı anda sabitlenir; bu yüzden uygulama her arka plana
/// geçtiğinde plan yeniden kurulur (bkz. `ReminderScheduler`).
nonisolated enum ReminderPlanner {
    struct Reminder: Equatable {
        let fireDate: Date
        let dueCount: Int
    }

    /// `studiedDueDates`: çalışılmış kelimelerin tekrar zamanları (o andan sonra sorulurlar).
    /// `newCount`: hiç çalışılmamış kelime sayısı. `introducedToday`: ilk cevabı bugün verilen kelime
    /// sayısı; yalnızca bugünün bildirimini kısar. İleri günlerde o günün henüz kelime tanıtmadığı
    /// varsayılır (`min(günlük sınır, newCount)` tahmini); plan her arka plana geçişte yeniden kurulur.
    static func plan(
        studiedDueDates: [Date],
        newCount: Int,
        introducedToday: Int,
        hour: Int,
        minute: Int,
        now: Date,
        days: Int = 7,
        calendar: Calendar = .current
    ) -> [Reminder] {
        guard let todayAtTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else {
            return []
        }
        let firstDay = todayAtTime > now ? 0 : 1
        return (firstDay..<(firstDay + days)).compactMap { offset in
            guard let fireDate = calendar.date(byAdding: .day, value: offset, to: todayAtTime) else { return nil }
            let count = dailyCount(
                studiedDueDates: studiedDueDates, newCount: newCount, introducedToday: introducedToday,
                at: fireDate, offset: offset
            )
            return count > 0 ? Reminder(fireDate: fireDate, dueCount: count) : nil
        }
    }

    /// Günlük Tekrar'ın `date` anında soracağı kelime sayısı; `offset` bugünden kaç gün sonra olduğu.
    static func dailyCount(studiedDueDates: [Date], newCount: Int, introducedToday: Int, at date: Date, offset: Int) -> Int {
        let count = StudySession.dailyCount(
            weak: studiedDueDates.count { $0 <= date }, new: newCount,
            introducedToday: offset == 0 ? introducedToday : 0
        )
        return count.weak + count.new
    }
}
