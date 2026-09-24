import Foundation
import SwiftData

/// Uygulama dışında (ana ekran widget'ı, hatırlatma bildirimi) sorulan tek soru: İngilizce kelime
/// ve 4 Türkçe seçenek (Çoktan Seçmeli). Soru değer olarak saklanır; kelimeye İngilizcesinin
/// sadeleştirilmiş hâliyle (`wordKey`) ulaşılır, çünkü soru başka bir süreçte kurulup saklanır.
nonisolated struct GlanceQuestion: Codable, Equatable, Hashable, Sendable {
    var id: String
    var english: String
    var wordKey: String
    var options: [String]
    var correctIndex: Int
}

/// Cevaplanan soru ve seçilen şık; widget kısa bir süre doğru/yanlış olarak gösterir.
nonisolated struct GlanceFeedback: Codable, Equatable, Sendable {
    var question: GlanceQuestion
    var chosen: Int
    var date: Date

    var isCorrect: Bool { chosen == question.correctIndex }
}

/// Kilit ekranındaki özet: "Hafıza %78 · 6 kelime zayıfladı".
/// Sayılar Çalış ekranındaki Günlük Tekrar kartıyla aynı hesaptan gelir.
nonisolated struct GlanceSummary: Equatable, Sendable {
    /// Çalışılmış kelimelerin ortalama hafızası; hiç çalışılmamışsa `nil`.
    var average: Double?
    /// Günlük Tekrar'ın soracağı çalışılmış zayıf kelime sayısı (en fazla 20).
    var weak: Int
    /// Günlük Tekrar'ın soracağı yeni kelime sayısı (en fazla 5).
    var new: Int
    var total: Int

    /// "Hafıza %78"; çalışılmış kelime yoksa "Hafıza yeni".
    var memoryText: String {
        average.map { "Hafıza \(MemoryStats.text($0))" } ?? "Hafıza yeni"
    }

    /// "6 kelime zayıfladı", "2 yeni kelime", "Bütün kelimeler güçlü" ya da "Defterin boş".
    var detailText: String {
        if total == 0 { return "Defterin boş" }
        if weak > 0 { return "\(weak) kelime zayıfladı" }
        if new > 0 { return "\(new) yeni kelime" }
        return "Bütün kelimeler güçlü"
    }

    /// Tek satır: "Hafıza %78 · 6 kelime zayıfladı".
    var line: String {
        total == 0 ? detailText : "\(memoryText) · \(detailText)"
    }
}

enum GlanceQuiz {
    /// Seçenek üretmek için gereken en az kelime (Çoktan Seçmeli ile aynı).
    static let minimumWords = 4
    /// Cevaplar Çoktan Seçmeli adına (ve onun ağırlığıyla) kaydedilir: soru tam olarak odur.
    static let mode = GameMode.multipleChoice

    static func key(for word: Word) -> String { AnswerChecker.fold(word.english) }

    /// Soru hiçbir zaman yeni kelimeden değildir (yeni kelime Günlük Tekrar'da tanıtılır): önce `now` anında
    /// vadesi gelmiş çalışılmış kelimeler, yoksa bütün çalışılmış kelimeler arasından ağırlıklı rastgele.
    /// `avoiding` (önceki sorunun kelimesi) mümkünse gelmez. Defterde 4'ten az kelime ya da hiç çalışılmış
    /// kelime yoksa, yeterli farklı seçenek çıkmazsa `nil`.
    static func question<G: RandomNumberGenerator>(
        from words: [Word], avoiding previousKey: String? = nil, now: Date = .now, using generator: inout G
    ) -> GlanceQuestion? {
        let words = words.filter { !$0.isDeleted && !key(for: $0).isEmpty }
        guard words.count >= minimumWords else { return nil }
        let studied = words.filter { !$0.isNew }
        let due = studied.filter { $0.isDue(at: now) }
        let pool = due.isEmpty ? studied : due
        let candidates = pool.indices.map { index in
            WordPicker.Candidate(id: index, weight: WordPicker.weight(memory: pool[index].memory(at: now)))
        }
        let avoided = previousKey.flatMap { key in pool.firstIndex { Self.key(for: $0) == key } }
        guard let index = WordPicker.order(candidates, limit: 1, avoidingFirst: avoided, using: &generator).first else {
            return nil
        }
        let word = pool[index]
        let others = words.filter { $0 !== word }.map { ChoiceQuiz.Candidate(turkish: $0.turkish) }
        let result = ChoiceQuiz.options(answer: ChoiceQuiz.Candidate(turkish: word.turkish), others: others, using: &generator)
        // Yanlış seçenek çıkmadıysa (bütün kelimeler aynı anlamda) soru sorulmaz.
        guard result.options.count >= 2 else { return nil }
        return GlanceQuestion(
            id: UUID().uuidString, english: word.english, wordKey: key(for: word),
            options: result.options, correctIndex: result.correctIndex
        )
    }

    /// Sorunun kelimesi depoda hâlâ duruyorsa o kelime.
    static func word(for question: GlanceQuestion, in words: [Word]) -> Word? {
        words.first { !$0.isDeleted && key(for: $0) == question.wordKey }
    }

    /// Cevabı hafıza motoruna ve `ReviewLog`'a yazar (oyunların kullandığı yol) ve kaydeder.
    /// Kelime silinmişse ya da şık geçersizse hiçbir şey yazılmaz ve `nil` döner; yoksa doğru mu.
    @discardableResult
    static func answer(
        _ question: GlanceQuestion, chosen: Int, context: ModelContext, now: Date = .now
    ) -> Bool? {
        guard question.options.indices.contains(chosen) else { return nil }
        let words = (try? context.fetch(FetchDescriptor<Word>())) ?? []
        guard let word = word(for: question, in: words) else { return nil }
        let correct = chosen == question.correctIndex
        ReviewRecorder.record(word, grade: .recognition(correct: correct), mode: mode, responseTime: 0, now: now)
        context.saveLogging()
        return correct
    }

    /// Kilit ekranı özeti; `now` ileri bir an da olabilir (widget zaman çizelgesi için).
    static func summary(_ words: [Word], now: Date = .now) -> GlanceSummary {
        let count = StudySession.dailyCount(words, now: now)
        return GlanceSummary(
            average: MemoryStats.average(words.map { $0.memory(at: now) }),
            weak: count.weak, new: count.new, total: words.count
        )
    }
}

/// Ana ekran widget'ının durumu: gösterilen soru ve son cevabın geri bildirimi.
/// App Group ayarlarında durur; widget süreci her açılışta buradan okur.
nonisolated struct GlanceQuizState: Codable, Equatable, Sendable {
    var question: GlanceQuestion?
    var feedback: GlanceFeedback?
}

enum GlanceQuizStore {
    static let stateKey = "GlanceQuiz.state"
    /// Cevaptan sonra doğru/yanlışın gösterildiği süre; sonra sıradaki soru gelir.
    static let feedbackDuration: TimeInterval = 2

    static var sharedDefaults: UserDefaults { UserDefaults(suiteName: SharedStore.appGroupID) ?? .standard }

    static func load(_ defaults: UserDefaults = sharedDefaults) -> GlanceQuizState {
        guard let data = defaults.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(GlanceQuizState.self, from: data) else { return GlanceQuizState() }
        return state
    }

    static func save(_ state: GlanceQuizState, to defaults: UserDefaults = sharedDefaults) {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: stateKey) }
    }

    /// Gösterilecek soru: saklı soru kelimesi hâlâ duruyorsa o, yoksa yenisi kurulup saklanır.
    /// Böylece widget her tazelendiğinde soru değişmez; yalnızca cevaplanınca değişir.
    static func currentQuestion<G: RandomNumberGenerator>(
        words: [Word], defaults: UserDefaults = sharedDefaults, now: Date = .now, using generator: inout G
    ) -> GlanceQuestion? {
        var state = load(defaults)
        if let question = state.question, words.count >= GlanceQuiz.minimumWords,
           GlanceQuiz.word(for: question, in: words) != nil {
            return question
        }
        state.question = GlanceQuiz.question(from: words, avoiding: state.question?.wordKey, now: now, using: &generator)
        save(state, to: defaults)
        return state.question
    }

    /// Widget'ta seçeneğe dokunulunca: cevabı yazar, geri bildirimi ve sıradaki soruyu saklar.
    /// Dokunulan soru artık gösterilen soru değilse (eski görünüm, çift dokunuş) hiçbir şey yapmaz.
    @discardableResult
    static func answer<G: RandomNumberGenerator>(
        questionID: String, chosen: Int, context: ModelContext,
        defaults: UserDefaults = sharedDefaults, now: Date = .now, using generator: inout G
    ) -> Bool? {
        var state = load(defaults)
        guard let question = state.question, question.id == questionID else { return nil }
        let correct = GlanceQuiz.answer(question, chosen: chosen, context: context, now: now)
        if correct != nil {
            state.feedback = GlanceFeedback(question: question, chosen: chosen, date: now)
        }
        let words = (try? context.fetch(FetchDescriptor<Word>())) ?? []
        state.question = GlanceQuiz.question(from: words, avoiding: question.wordKey, now: now, using: &generator)
        save(state, to: defaults)
        return correct
    }

    /// `now` anında hâlâ gösterilmesi gereken geri bildirim.
    static func activeFeedback(in state: GlanceQuizState, now: Date = .now) -> GlanceFeedback? {
        guard let feedback = state.feedback else { return nil }
        let age = now.timeIntervalSince(feedback.date)
        return age >= 0 && age < feedbackDuration ? feedback : nil
    }
}
