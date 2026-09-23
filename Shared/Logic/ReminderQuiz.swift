import Foundation
import SwiftData
import UserNotifications

/// Cevaplanabilir hatırlatma: bildirim basılı tutulunca sorunun 4 Türkçe seçeneği düğme olarak çıkar.
///
/// Bildirim içeriği planlandığı anda sabitlenir; soru (kelime, seçenekler, doğru şık) `userInfo`'ya
/// yazılır. Düğme başlıkları kategoriye bağlı olduğundan her hatırlatmanın kendi kategorisi vardır.
/// Cevap, uygulama arka planda uyandırılınca hafızaya yazılır (bkz. `NotificationDelegate`).
nonisolated enum ReminderQuiz {
    static let actionPrefix = "choice-"
    static let categoryPrefix = "quiz-"
    static let questionKey = "glanceQuestion"
    /// Cevaptan sonra gösterilen sonuç bildirimi; her yeni cevap öncekinin yerine geçer.
    static let feedbackID = "quiz-feedback"

    static func userInfo(for question: GlanceQuestion) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(question), let text = String(data: data, encoding: .utf8) else {
            return [:]
        }
        return [questionKey: text]
    }

    static func question(from userInfo: [AnyHashable: Any]) -> GlanceQuestion? {
        guard let text = userInfo[questionKey] as? String, let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(GlanceQuestion.self, from: data)
    }

    static func actionID(for index: Int) -> String { actionPrefix + String(index) }

    /// "choice-2" → 2; başka eylem (bildirime dokunmak, kapatmak) `nil`.
    static func choice(fromAction identifier: String) -> Int? {
        guard identifier.hasPrefix(actionPrefix) else { return nil }
        return Int(identifier.dropFirst(actionPrefix.count))
    }

    /// Seçenekleri düğme yapan kategori. Düğmeler uygulamayı öne getirmez; cevap arka planda yazılır.
    static func category(for question: GlanceQuestion, identifier: String) -> UNNotificationCategory {
        let actions = question.options.indices.map { index in
            UNNotificationAction(identifier: actionID(for: index), title: question.options[index], options: [])
        }
        return UNNotificationCategory(identifier: identifier, actions: actions, intentIdentifiers: [])
    }

    /// Hatırlatmanın alt başlığı: "“idempotent” ne demek?"
    static func prompt(for question: GlanceQuestion) -> String {
        "“\(question.english)” ne demek?"
    }

    /// Gövdenin sonuna eklenen ipucu; seçenekler ancak basılı tutunca görünür.
    static let hint = "Cevaplamak için bildirimi basılı tut."

    /// Bildirimde seçilen şıkkı hafızaya yazar. Bu bir soru cevabı değilse ya da kelime silinmişse `nil`.
    @MainActor @discardableResult
    static func handle(
        actionIdentifier: String, userInfo: [AnyHashable: Any], context: ModelContext, now: Date = .now
    ) -> GlanceFeedback? {
        guard let chosen = choice(fromAction: actionIdentifier),
              let question = question(from: userInfo),
              GlanceQuiz.answer(question, chosen: chosen, context: context, now: now) != nil else { return nil }
        return GlanceFeedback(question: question, chosen: chosen, date: now)
    }

    /// Sonuç bildirimi: "Doğru" / "Yanlış" ve kelimenin doğru anlamı.
    static func feedbackContent(_ feedback: GlanceFeedback) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let question = feedback.question
        content.title = feedback.isCorrect ? "Doğru" : "Yanlış"
        content.body = "\(question.english): \(question.options[question.correctIndex])"
        return content
    }
}
