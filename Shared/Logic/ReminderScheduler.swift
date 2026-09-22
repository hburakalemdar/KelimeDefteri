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

    /// Bekleyen hatırlatmaları siler, güncel kelime durumuna göre yeniden kurar ve ikon rozetini günceller.
    static func refresh(context: ModelContext, now: Date = .now) async {
        let words = (try? context.fetch(FetchDescriptor<Word>())) ?? []
        let dueDates = words.map(\.dueDate)
        let center = UNUserNotificationCenter.current()

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
        )

        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: ReminderSettings.enabledKey)
        let authorized = await center.notificationSettings().authorizationStatus == .authorized

        try? await center.setBadgeCount(enabled && authorized ? dueDates.count { $0 <= now } : 0)
        guard enabled, authorized else { return }

        let hour = defaults.object(forKey: ReminderSettings.hourKey) as? Int ?? ReminderSettings.defaultHour
        let minute = defaults.object(forKey: ReminderSettings.minuteKey) as? Int ?? ReminderSettings.defaultMinute
        let reminders = ReminderPlanner.plan(dueDates: dueDates, hour: hour, minute: minute, now: now)

        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = "Kelime Defteri"
            content.body = reminder.dueCount == 1
                ? "Bugün 1 kelime seni bekliyor. Birkaç saniyeni alır."
                : "Bugün \(reminder.dueCount) kelime seni bekliyor. Birkaç dakikanı alır."
            content.sound = .default
            content.badge = NSNumber(value: reminder.dueCount)

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
