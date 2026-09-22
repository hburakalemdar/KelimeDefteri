import Foundation

/// Önümüzdeki günlerin hatırlatmalarını planlar: her gün seçilen saatte kaç kelimenin
/// sırada olacağını hesaplar. Sırada kelime olmayan günlere bildirim düşmez.
///
/// Bildirim içeriği planlandığı anda sabitlenir; bu yüzden uygulama her arka plana
/// geçtiğinde plan yeniden kurulur (bkz. `ReminderScheduler`).
nonisolated enum ReminderPlanner {
    struct Reminder: Equatable {
        let fireDate: Date
        let dueCount: Int
    }

    static func plan(
        dueDates: [Date],
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
            let count = dueDates.count { $0 <= fireDate }
            return count > 0 ? Reminder(fireDate: fireDate, dueCount: count) : nil
        }
    }
}
