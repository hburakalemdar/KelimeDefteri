import SwiftData
import UIKit
import UserNotifications

/// Hatırlatma bildiriminden verilen cevabı karşılar. Seçenek düğmesine basılınca iOS uygulamayı
/// arka planda uyandırır; cevap hafızaya yazılır, widget'lar ve hatırlatmalar tazelenir,
/// sonuç kısa bir bildirimle gösterilir.
final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Arka planda uyandırılınca cevabın gelmesi için temsilci açılışta kurulmalı.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        guard ReminderQuiz.choice(fromAction: action) != nil,
              let question = ReminderQuiz.question(from: response.notification.request.content.userInfo) else { return }
        await Self.record(action: action, question: question)
    }

    /// Uygulama öndeyken yalnızca cevabın sonucu gösterilir; hatırlatmanın kendisi gösterilmez (eskisi gibi).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        notification.request.identifier == ReminderQuiz.feedbackID ? [.banner, .list] : []
    }

    @MainActor
    private static func record(action: String, question: GlanceQuestion) async {
        guard let context = SharedStore.container?.mainContext,
              let feedback = ReminderQuiz.handle(
                  actionIdentifier: action, userInfo: ReminderQuiz.userInfo(for: question), context: context
              ) else { return }
        Glance.reloadWidgets()
        let request = UNNotificationRequest(
            identifier: ReminderQuiz.feedbackID, content: ReminderQuiz.feedbackContent(feedback), trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
        // Rozet ve sonraki hatırlatmalar yeni hafızaya göre kurulsun.
        await ReminderScheduler.refresh(context: context)
    }
}
