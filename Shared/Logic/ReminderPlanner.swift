import Foundation

/// Önümüzdeki günlerin hatırlatmalarını planlar: her gün seçilen saatte Günlük Tekrar'ın kaç
/// kelime soracağını hesaplar (vadesi gelmiş çalışılmış kelimelerin hepsi, güvenlik tavanı 100; üstüne günlük
/// yeni hakkı kadar tanışma, bkz. `StudySession.dailyCount`). Sorulacak kelime olmayan günlere bildirim düşmez.
///
/// Bildirim içeriği planlandığı anda sabitlenir; bu yüzden uygulama her arka plana
/// geçtiğinde plan yeniden kurulur (bkz. `ReminderScheduler`).
nonisolated enum ReminderPlanner {
    struct Reminder: Equatable {
        let fireDate: Date
        let dueCount: Int
    }

    /// `studiedDueDates`: çalışılmış kelimelerin tekrar zamanları (o andan sonra sorulurlar).
    /// `newCount`: hiç çalışılmamış kelime sayısı. `introDueDates`: yalnız yeni anlam tanıtımı için gelecek kelimelerin
    /// (`StudySession.introOnlyWords`) tekrar zamanları; bildirim anında vadesi gelmemişler tanışma havuzuna eklenir,
    /// vadesi gelenler zaten `studiedDueDates` içinde sayılır (iki kez sayılmasın). `introducedToday`: bugün tanışılan kelime sayısı (`StudySession.introducedToday`);
    /// yalnızca bugünün bildirimini kısar. İleri günlerde o günün henüz kelime tanıtmadığı
    /// varsayılır (`min(newAllowance, newCount)` tahmini); plan her arka plana geçişte yeniden kurulur.
    /// `newAllowance`: günlük yeni hakkı (`DailyNewAllowance`). `reviewedToday`: bugün tekrar olarak cevaplanmış
    /// kelimeler (`StudySession.reviewedToday`); yalnız bugünün "tekrar yükü 100'ü aştı, yeni yok" kuralında sayılır.
    /// İleri günlerde yük o gün vadesi gelenlerle yaklaşıklanır (o günün cevapları önceden bilinemez).
    /// `pendingDueDates`: bugün üretimi bekleyen kelimelerin tekrar zamanları (`Word.isPendingProduction`);
    /// bugünün (04:00 sınırıyla) bildiriminde vadesine bakılmadan sayılır, sonraki günlerde vadesiyle.
    static func plan(
        studiedDueDates: [Date],
        pendingDueDates: [Date] = [],
        newCount: Int,
        introDueDates: [Date] = [],
        introducedToday: Int,
        newAllowance: Int,
        reviewedToday: Int = 0,
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
            let pendingToday = DayBoundary.isSameDay(fireDate, now, calendar: calendar)
            let count = dailyCount(
                studiedDueDates: studiedDueDates + (pendingToday ? [] : pendingDueDates),
                newCount: newCount + introDueDates.count { $0 > fireDate },
                introducedToday: introducedToday, newAllowance: newAllowance, reviewedToday: reviewedToday,
                at: fireDate, offset: offset,
                pending: pendingToday ? pendingDueDates.count : 0
            )
            return count > 0 ? Reminder(fireDate: fireDate, dueCount: count) : nil
        }
    }

    /// Günlük Tekrar'ın `date` anında soracağı kelime sayısı; `offset` bugünden kaç gün sonra olduğu.
    static func dailyCount(
        studiedDueDates: [Date], newCount: Int, introducedToday: Int, newAllowance: Int, reviewedToday: Int = 0,
        at date: Date, offset: Int, pending: Int = 0
    ) -> Int {
        let count = StudySession.dailyCount(
            weak: studiedDueDates.count { $0 <= date } + pending, new: newCount,
            introducedToday: offset == 0 ? introducedToday : 0, newAllowance: newAllowance,
            reviewedToday: offset == 0 ? reviewedToday : 0
        )
        return count.weak + count.new
    }
}
