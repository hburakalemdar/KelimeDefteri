import Foundation
import SwiftData
import UserNotifications

/// Hatırlatma ayarları ve iOS bildirimleriyle konuşan katman.
enum ReminderSettings {
    static let enabledKey = "reminderEnabled"
    static let hourKey = "reminderHour"
    static let minuteKey = "reminderMinute"
    static let defaultHour = 20
    static let defaultMinute = 0
}

enum ReminderScheduler {
    private static let idPrefix = "daily-review-"

    /// Bildirim izni ister. Kullanıcı daha önce reddettiyse sessizce false döner.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Günlük Tekrar'ın şu an soracağı kelime sayısı; simge rozeti bunu gösterir.
    static func dailyTotal(_ words: [Word], now: Date = .now) -> Int {
        let count = StudySession.dailyCount(words, now: now)
        return count.weak + count.new
    }

    /// Bekleyen hatırlatmaları siler, güncel kelime durumuna göre yeniden kurar ve ikon rozetini günceller.
    static func refresh(context: ModelContext, now: Date = .now) async {
        let words = (try? context.fetch(FetchDescriptor<Word>())) ?? []
        // Rozet ve bildirim Günlük Tekrar'ın soracağı sayıyı gösterir (20 sınırı, en fazla 5 yeni).
        let studiedDueDates = words.filter { !$0.isNew }.map(\.dueDate)
        let newCount = words.count(where: \.isNew)
        let introducedToday = StudySession.introducedToday(words, now: now)
        let center = UNUserNotificationCenter.current()

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        )

        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: ReminderSettings.enabledKey)
        let authorized = await center.notificationSettings().authorizationStatus == .authorized

        try? await center.setBadgeCount(enabled && authorized ? dailyTotal(words, now: now) : 0)
        guard enabled, authorized else { return }

        let hour = defaults.object(forKey: ReminderSettings.hourKey) as? Int ?? ReminderSettings.defaultHour
        let minute = defaults.object(forKey: ReminderSettings.minuteKey) as? Int ?? ReminderSettings.defaultMinute
        let reminders = ReminderPlanner.plan(
            studiedDueDates: studiedDueDates, newCount: newCount, introducedToday: introducedToday,
            hour: hour, minute: minute, now: now
        )

        #if os(iOS)
        // Her hatırlatmaya bir soru: seçenekler basılı tutunca düğme olarak çıkar (bkz. `ReminderQuiz`).
        var categories = Set<UNNotificationCategory>()
        var generator = SystemRandomNumberGenerator()
        var previousKey: String?
        // Hatırlatmanın gününde (04:00 sınırı) zaten cevaplanmış kelimeler sorulmaz; gün başına bir sorgu.
        var answeredByDay: [Date: Set<String>] = [:]
        defer { center.setNotificationCategories(categories) }
        #endif

        for (offset, reminder) in reminders.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Kelime Defteri"
            content.body = reminder.dueCount == 1
                ? "Bugün 1 kelime seni bekliyor. Birkaç saniyeni alır."
                : "Bugün \(reminder.dueCount) kelime seni bekliyor. Birkaç dakikanı alır."
            content.sound = .default
            content.badge = NSNumber(value: reminder.dueCount)
            #if os(iOS)
            let day = DayBoundary.start(of: reminder.fireDate)
            let answered = answeredByDay[day] ?? GlanceQuiz.answeredKeys(in: context, on: reminder.fireDate)
            answeredByDay[day] = answered
            if let question = GlanceQuiz.question(
                from: words, answered: answered, avoiding: previousKey, now: reminder.fireDate, using: &generator
            ) {
                let category = ReminderQuiz.category(for: question, identifier: ReminderQuiz.categoryPrefix + String(offset))
                categories.insert(category)
                content.categoryIdentifier = category.identifier
                content.userInfo = ReminderQuiz.userInfo(for: question)
                content.subtitle = ReminderQuiz.prompt(for: question)
                content.body += "\n" + ReminderQuiz.hint
                previousKey = question.wordKey
            }
            #endif

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let request = UNNotificationRequest(
                identifier: idPrefix + ISO8601DateFormatter().string(from: reminder.fireDate),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }
}
