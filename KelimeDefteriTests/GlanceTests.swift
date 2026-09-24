import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

/// Uygulama dışındaki sorular (widget, bildirim) ve kilit ekranı özeti.
struct GlanceTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "test-\(UUID().uuidString)")! }

    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    /// Dört farklı anlamlı kelime; `weak` çalışılmış ve zayıflamış, diğerleri güçlü.
    private func deck(in context: ModelContext, weak: Set<String> = []) -> [Word] {
        let pairs = [("idempotent", "eş etkili"), ("stale", "bayat, eskimiş"), ("quorum", "yeter sayı"),
                     ("latency", "gecikme"), ("throughput", "iş hacmi")]
        return pairs.map { english, turkish in
            let word = Word(english: english, turkish: turkish, createdAt: now.addingTimeInterval(-40 * 86_400))
            word.stability = weak.contains(english) ? 1 : 60
            word.lastReviewedAt = now.addingTimeInterval(weak.contains(english) ? -10 * 86_400 : -86_400)
            word.dueDate = word.lastReviewedAt!.addingTimeInterval(word.stability * 86_400)
            word.reviewCount = 1
            context.insert(word)
            return word
        }
    }

    // MARK: - Soru

    @Test func questionNeedsFourWords() throws {
        let context = try makeContext()
        let words = Array(deck(in: context).prefix(3))
        var generator = SeededGenerator(seed: 1)
        #expect(GlanceQuiz.question(from: words, now: now, using: &generator) == nil)
    }

    @Test func questionHasFourOptionsWithFirstMeaningCorrect() throws {
        let context = try makeContext()
        let words = deck(in: context)
        for seed in 0..<30 as Range<UInt64> {
            var generator = SeededGenerator(seed: seed)
            let question = try #require(GlanceQuiz.question(from: words, now: now, using: &generator))
            #expect(question.options.count == 4)
            let word = try #require(words.first { $0.english == question.english })
            #expect(question.options[question.correctIndex] == ChoiceQuiz.firstMeaning(word.turkish))
            #expect(question.wordKey == AnswerChecker.fold(word.english))
        }
    }

    @Test func questionAvoidsPreviousWord() throws {
        let context = try makeContext()
        let words = deck(in: context)
        for seed in 0..<30 as Range<UInt64> {
            var generator = SeededGenerator(seed: seed)
            let question = GlanceQuiz.question(from: words, avoiding: "quorum", now: now, using: &generator)
            #expect(question?.wordKey != "quorum")
        }
    }

    @Test func weakWordsAreAskedMoreOften() throws {
        let context = try makeContext()
        let words = deck(in: context, weak: ["stale"])
        var staleCount = 0
        for seed in 0..<400 as Range<UInt64> {
            var generator = SeededGenerator(seed: seed)
            if GlanceQuiz.question(from: words, now: now, using: &generator)?.english == "stale" { staleCount += 1 }
        }
        // Vadesi gelmiş tek kelime o: hep o sorulur.
        #expect(staleCount == 400)
    }

    @Test func dueWordsComeFirstAndNewWordsAreNeverAsked() throws {
        let context = try makeContext()
        var words = deck(in: context, weak: ["stale", "quorum"])
        for index in 0..<5 {
            let fresh = Word(english: "fresh\(index)", turkish: "yeni \(index)")
            context.insert(fresh)
            words.append(fresh)
        }
        for seed in 0..<60 as Range<UInt64> {
            var generator = SeededGenerator(seed: seed)
            let question = try #require(GlanceQuiz.question(from: words, now: now, using: &generator))
            #expect(["stale", "quorum"].contains(question.english))
        }
    }

    @Test func questionFallsBackToStudiedWordsWhenNothingIsDue() throws {
        let context = try makeContext()
        var words = deck(in: context)
        let fresh = Word(english: "shard", turkish: "parça")
        context.insert(fresh)
        words.append(fresh)
        var asked = Set<String>()
        for seed in 0..<60 as Range<UInt64> {
            var generator = SeededGenerator(seed: seed)
            // Widget boş kalmaz: vadesi gelen yoksa bütün çalışılmış kelimelerden.
            let question = try #require(GlanceQuiz.question(from: words, now: now, using: &generator))
            asked.insert(question.english)
        }
        #expect(!asked.contains("shard"))
        #expect(asked.count > 1)

        // Hiç çalışılmış kelime yoksa soru yok.
        let onlyNew = (0..<5).map { Word(english: "n\($0)", turkish: "anlam \($0)") }
        var generator = SeededGenerator(seed: 1)
        #expect(GlanceQuiz.question(from: onlyNew, now: now, using: &generator) == nil)
    }

    // MARK: - Cevap

    @Test func correctAnswerGoesThroughEngineAsMultipleChoice() throws {
        let context = try makeContext()
        let words = deck(in: context, weak: ["idempotent"])
        let word = words[0]
        let question = GlanceQuestion(id: "q", english: word.english, wordKey: "idempotent",
                                      options: ["bayat", "eş etkili", "gecikme", "yeter sayı"], correctIndex: 1)
        let stabilityBefore = word.stability
        let anchorBefore = word.lastReviewedAt
        #expect(GlanceQuiz.answer(question, chosen: 1, context: context, now: now) == true)
        // Tanıma genç kelimeyi büyütür ama çıpayı ilerletmez.
        #expect(word.stability > stabilityBefore)
        #expect(word.stability <= Memory.recognitionCap)
        #expect(word.lastReviewedAt == anchorBefore)
        let log = try #require(word.logs?.first)
        #expect(log.mode == GameMode.multipleChoice.rawValue)
        #expect(log.correct)
        #expect(log.grade == AnswerGrade.good.rawValue)
        #expect(!context.hasChanges)
    }

    @Test func wrongAnswerMakesWordWeak() throws {
        let context = try makeContext()
        let word = deck(in: context)[0]
        let question = GlanceQuestion(id: "q", english: word.english, wordKey: "idempotent",
                                      options: ["bayat", "eş etkili", "gecikme", "yeter sayı"], correctIndex: 1)
        #expect(GlanceQuiz.answer(question, chosen: 0, context: context, now: now) == false)
        #expect(word.isLapsed)
        #expect(!word.isDue(at: now))
        #expect(word.logs?.first?.grade == AnswerGrade.again.rawValue)
    }

    @Test func answerForDeletedWordWritesNothing() throws {
        let context = try makeContext()
        let words = deck(in: context)
        context.delete(words[0])
        try context.save()
        let question = GlanceQuestion(id: "q", english: "idempotent", wordKey: "idempotent",
                                      options: ["a", "b"], correctIndex: 0)
        #expect(GlanceQuiz.answer(question, chosen: 0, context: context, now: now) == nil)
        #expect(try context.fetchCount(FetchDescriptor<ReviewLog>()) == 0)
    }

    // MARK: - Widget durumu

    @Test func currentQuestionStaysUntilAnswered() throws {
        let context = try makeContext()
        let words = deck(in: context)
        let store = defaults()
        var generator = SeededGenerator(seed: 7)
        let first = try #require(GlanceQuizStore.currentQuestion(words: words, defaults: store, now: now, using: &generator))
        let again = GlanceQuizStore.currentQuestion(words: words, defaults: store, now: now, using: &generator)
        #expect(again == first)
    }

    @Test func currentQuestionChangesWhenItsWordIsDeleted() throws {
        let context = try makeContext()
        var words = deck(in: context)
        let store = defaults()
        var generator = SeededGenerator(seed: 7)
        let first = try #require(GlanceQuizStore.currentQuestion(words: words, defaults: store, now: now, using: &generator))
        words.removeAll { AnswerChecker.fold($0.english) == first.wordKey }
        let next = try #require(GlanceQuizStore.currentQuestion(words: words, defaults: store, now: now, using: &generator))
        #expect(next.wordKey != first.wordKey)
    }

    @Test func answeringStoresFeedbackAndNextQuestion() throws {
        let context = try makeContext()
        let words = deck(in: context)
        let store = defaults()
        var generator = SeededGenerator(seed: 3)
        let question = try #require(GlanceQuizStore.currentQuestion(words: words, defaults: store, now: now, using: &generator))

        let result = GlanceQuizStore.answer(
            questionID: question.id, chosen: question.correctIndex, context: context,
            defaults: store, now: now, using: &generator
        )
        #expect(result == true)
        let state = GlanceQuizStore.load(store)
        #expect(state.feedback?.question == question)
        #expect(state.feedback?.isCorrect == true)
        #expect(state.question != nil)
        #expect(state.question?.wordKey != question.wordKey)

        // Geri bildirim kısa süre görünür, sonra sıradaki soru.
        #expect(GlanceQuizStore.activeFeedback(in: state, now: now.addingTimeInterval(1)) != nil)
        #expect(GlanceQuizStore.activeFeedback(in: state, now: now.addingTimeInterval(GlanceQuizStore.feedbackDuration)) == nil)
    }

    @Test func staleTapIsIgnored() throws {
        let context = try makeContext()
        let words = deck(in: context)
        let store = defaults()
        var generator = SeededGenerator(seed: 3)
        let question = try #require(GlanceQuizStore.currentQuestion(words: words, defaults: store, now: now, using: &generator))
        GlanceQuizStore.answer(questionID: question.id, chosen: 0, context: context, defaults: store, now: now, using: &generator)
        // Aynı soruya ikinci dokunuş (eski görünüm) yeni bir kayıt yazmaz.
        let second = GlanceQuizStore.answer(questionID: question.id, chosen: 0, context: context, defaults: store, now: now, using: &generator)
        #expect(second == nil)
        #expect(try context.fetchCount(FetchDescriptor<ReviewLog>()) == 1)
    }

    // MARK: - Özet

    @Test func summaryMatchesDailyCard() throws {
        let context = try makeContext()
        var words = deck(in: context, weak: ["stale", "quorum"])
        let fresh = Word(english: "shard", turkish: "parça")
        context.insert(fresh)
        words.append(fresh)

        let summary = GlanceQuiz.summary(words, now: now)
        let daily = StudySession.dailyCount(words, now: now)
        #expect(summary.weak == daily.weak)
        #expect(summary.weak == 2)
        #expect(summary.new == 1)
        #expect(summary.average == MemoryStats.average(words.map { $0.memory(at: now) }))
        #expect(summary.detailText == "2 kelime zayıfladı")
        #expect(summary.line.hasPrefix("Hafıza %"))
        #expect(summary.line.hasSuffix(" · 2 kelime zayıfladı"))
    }

    @Test func summaryTexts() {
        #expect(GlanceSummary(average: 0.78, weak: 6, new: 2, total: 30).line == "Hafıza %78 · 6 kelime zayıfladı")
        #expect(GlanceSummary(average: 0.95, weak: 0, new: 2, total: 30).line == "Hafıza %95 · 2 yeni kelime")
        #expect(GlanceSummary(average: 0.95, weak: 0, new: 0, total: 30).line == "Hafıza %95 · Bütün kelimeler güçlü")
        #expect(GlanceSummary(average: nil, weak: 0, new: 3, total: 3).line == "Hafıza yeni · 3 yeni kelime")
        #expect(GlanceSummary(average: nil, weak: 0, new: 0, total: 0).line == "Defterin boş")
    }

    // MARK: - Bildirim

    @Test func notificationQuestionRoundTrips() throws {
        let question = GlanceQuestion(id: "q", english: "stale", wordKey: "stale",
                                      options: ["bayat", "gecikme", "yeter sayı", "eş etkili"], correctIndex: 0)
        #expect(ReminderQuiz.question(from: ReminderQuiz.userInfo(for: question)) == question)
        #expect(ReminderQuiz.choice(fromAction: ReminderQuiz.actionID(for: 3)) == 3)
        #expect(ReminderQuiz.choice(fromAction: "com.apple.UNNotificationDefaultActionIdentifier") == nil)

        let category = ReminderQuiz.category(for: question, identifier: "quiz-0")
        #expect(category.actions.map(\.title) == question.options)
        #expect(category.actions.allSatisfy { !$0.options.contains(.foreground) })
    }

    @Test func notificationAnswerIsRecorded() throws {
        let context = try makeContext()
        let word = deck(in: context)[1]
        let question = GlanceQuestion(id: "q", english: "stale", wordKey: "stale",
                                      options: ["gecikme", "bayat", "yeter sayı", "eş etkili"], correctIndex: 1)
        let feedback = try #require(ReminderQuiz.handle(
            actionIdentifier: ReminderQuiz.actionID(for: 2), userInfo: ReminderQuiz.userInfo(for: question),
            context: context, now: now
        ))
        #expect(!feedback.isCorrect)
        #expect(word.logs?.count == 1)
        #expect(word.logs?.first?.mode == GameMode.multipleChoice.rawValue)
        let content = ReminderQuiz.feedbackContent(feedback)
        #expect(content.title == "Yanlış")
        #expect(content.body == "stale: bayat")

        // Bildirime dokunmak (seçenek değil) cevap sayılmaz.
        #expect(ReminderQuiz.handle(
            actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier",
            userInfo: ReminderQuiz.userInfo(for: question), context: context, now: now
        ) == nil)
        #expect(word.logs?.count == 1)
    }

    @Test func quickRoundLink() {
        #expect(Glance.isQuickRound(Glance.quickRoundURL))
        #expect(!Glance.isQuickRound(URL(string: "kelimedefteri://add")!))
        #expect(!Glance.isQuickRound(URL(string: "https://quick")!))
    }
}
