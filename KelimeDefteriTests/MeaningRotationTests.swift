import Foundation
import SwiftData
import Testing
@testable import KelimeDefteri

/// Birden çok anlamlı kelimede doğru şık anlamlar arasında sırayla döner (cevap kaydı sayısına göre).
struct MeaningRotationTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeContext() throws -> ModelContext {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID().uuidString).store")
        let container = try ModelContainer(
            for: SharedStore.schema,
            configurations: ModelConfiguration(schema: SharedStore.schema, url: url, cloudKitDatabase: .none)
        )
        return ModelContext(container)
    }

    @Test func meaningTurnsThroughAllMeanings() {
        let turkish = "o kadar, bu tür; öyle"
        #expect(ChoiceQuiz.meaning(turkish, turn: 0) == "o kadar")
        #expect(ChoiceQuiz.meaning(turkish, turn: 1) == "bu tür")
        #expect(ChoiceQuiz.meaning(turkish, turn: 2) == "öyle")
        #expect(ChoiceQuiz.meaning(turkish, turn: 3) == "o kadar")
        #expect(ChoiceQuiz.meaning("yeter sayı", turn: 5) == "yeter sayı")
        // Sadeleştirilmiş hâli aynı tekrar ayrı anlam sayılmaz; boş parça atlanır.
        #expect(ChoiceQuiz.displayMeanings("bayat, Bayat,, eskimiş") == ["bayat", "eskimiş"])
    }

    /// "such" tek çalışılmış kelime (hep o sorulur); her cevaptan sonra doğru şık sıradaki anlam olur,
    /// yanlış şıklarda kelimenin hiçbir anlamı çıkmaz.
    @Test func consecutiveQuestionsRotateMeaning() throws {
        let context = try makeContext()
        let such = Word(english: "such", turkish: "o kadar, bu tür, öyle", createdAt: now.addingTimeInterval(-40 * 86_400))
        such.stability = 1
        such.lastReviewedAt = now.addingTimeInterval(-10 * 86_400)
        such.dueDate = now.addingTimeInterval(-9 * 86_400)
        context.insert(such)
        // Yeni kelimeler (sorulmaz, yalnızca seçenek olur); ikisi "such" ile ortak anlam taşır.
        let others = [("kind", "tür, bu tür"), ("so", "öyle, böyle"), ("stale", "bayat"), ("quorum", "yeter sayı"),
                      ("latency", "gecikme"), ("throughput", "iş hacmi")]
        for (english, turkish) in others {
            context.insert(Word(english: english, turkish: turkish, createdAt: now.addingTimeInterval(-40 * 86_400)))
        }
        try context.save()
        let words = try context.fetch(FetchDescriptor<Word>())
        let suchMeanings = Set(AnswerChecker.meanings(in: such.turkish))

        var asked: [String] = []
        for step in 0..<4 {
            var generator = SeededGenerator(seed: UInt64(step))
            let question = try #require(GlanceQuiz.question(from: words, now: now, using: &generator))
            #expect(question.english == "such")
            asked.append(question.options[question.correctIndex])
            #expect(question.meanings == ["o kadar", "bu tür", "öyle"])
            for (index, option) in question.options.enumerated() where index != question.correctIndex {
                #expect(!suchMeanings.contains(AnswerChecker.fold(option)))
            }
            let later = now.addingTimeInterval(Double(step) * 60)
            #expect(GlanceQuiz.answer(question, chosen: question.correctIndex, context: context, now: later) == true)
        }
        #expect(asked == ["o kadar", "bu tür", "öyle", "o kadar"])
    }

    @Test func twoMeaningWordAlternates() throws {
        let context = try makeContext()
        let word = Word(english: "stale", turkish: "bayat, eskimiş", createdAt: now)
        context.insert(word)
        #expect(word.askedMeaning == "bayat")
        ReviewRecorder.record(word, grade: .recognition(correct: true), mode: .multipleChoice, responseTime: 0, now: now)
        #expect(word.askedMeaning == "eskimiş")
        #expect(word.askedCandidate.text == "eskimiş")
        #expect(word.askedCandidate.meanings == ["bayat", "eskimis"])
        ReviewRecorder.record(word, grade: .recognition(correct: false), mode: .multipleChoice, responseTime: 0, now: now)
        #expect(word.askedMeaning == "bayat")
    }

    @Test func otherMeaningsTextOnlyForSeveralMeanings() {
        var question = GlanceQuestion(id: "q", english: "such", wordKey: "such",
                                      options: ["bu tür", "bayat"], correctIndex: 0)
        #expect(question.otherMeaningsText == nil)
        question.meanings = ["o kadar"]
        #expect(question.otherMeaningsText == nil)
        question.meanings = ["o kadar", "bu tür", "öyle"]
        #expect(question.otherMeaningsText == "o kadar, bu tür, öyle")
    }

    /// `meanings` alanı eklenmeden önce saklanan widget durumu hâlâ çözülür.
    @Test func legacyGlanceStateDecodes() throws {
        let json = """
        {"question":{"id":"q","english":"stale","wordKey":"stale","options":["bayat","gecikme","yeter sayı","eş etkili"],\
        "correctIndex":0},"questionDate":780000000,"feedback":{"question":{"id":"p","english":"quorum","wordKey":"quorum",\
        "options":["yeter sayı","bayat"],"correctIndex":0},"chosen":1,"date":780000000}}
        """
        let state = try JSONDecoder().decode(GlanceQuizState.self, from: Data(json.utf8))
        #expect(state.question?.english == "stale")
        #expect(state.question?.meanings == nil)
        #expect(state.feedback?.question.options == ["yeter sayı", "bayat"])
        #expect(state.feedback?.isCorrect == false)

        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defaults.set(Data(json.utf8), forKey: GlanceQuizStore.stateKey)
        #expect(GlanceQuizStore.load(defaults).question?.wordKey == "stale")
    }
}
