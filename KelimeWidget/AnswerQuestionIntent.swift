import AppIntents
import SwiftData
import WidgetKit

/// Widget'taki seçeneğe dokunulunca çalışır (widget sürecinde): cevabı hafızaya ve geçmişe yazar,
/// geri bildirimi ve sıradaki soruyu saklar. Ardından sistem widget'ı tazeler.
struct AnswerQuestionIntent: AppIntent {
    static let title: LocalizedStringResource = "Soruyu Cevapla"
    static let isDiscoverable = false

    @Parameter(title: "Soru")
    var questionID: String

    @Parameter(title: "Seçenek")
    var choice: Int

    init() {}

    init(questionID: String, choice: Int) {
        self.questionID = questionID
        self.choice = choice
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let context = SharedStore.container?.mainContext {
            var generator = SystemRandomNumberGenerator()
            GlanceQuizStore.answer(questionID: questionID, chosen: choice, context: context, using: &generator)
            // Kilit ekranı özeti de yeni hafızayı göstersin.
            WidgetCenter.shared.reloadTimelines(ofKind: Glance.summaryKind)
        }
        return .result()
    }
}
