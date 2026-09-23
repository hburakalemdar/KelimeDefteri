import SwiftData
import SwiftUI

/// Hızlı Tur (karışık): 5 soru, her biri oynanabilir oyun türlerinden rastgele biri;
/// aynı tür art arda en fazla iki kez gelir. Her cevap kendi oyununun adıyla ve ağırlığıyla kaydedilir.
struct QuickMixGameView: View {
    private enum Question {
        case recall(Word, reverse: Bool)
        case choice(Word, options: [String], correct: Int)
        case blank(Word, cloze: ClozeSentence, options: [String], correct: Int)
        case letters(Word, LetterPuzzle)

        var word: Word {
            switch self {
            case .recall(let word, _), .choice(let word, _, _), .blank(let word, _, _, _), .letters(let word, _): word
            }
        }
    }

    /// Hatırlama sorularının oturumu önceki turun ilk kelimesini değiştirmesin diye ayrı ayar deposu kullanır.
    private static let scratchDefaults = UserDefaults(suiteName: "QuickMix.scratch") ?? .standard

    /// Mac'te oyun merkezine dönüş; iOS'ta `nil` (tam ekran kapanır).
    var onClose: (() -> Void)? = nil

    @Query private var words: [Word]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var round = GameRound(mode: .quickRound)
    @State private var questions: [Question] = []
    @State private var recallSession: StudySession?
    @State private var didStart = false

    var body: some View {
        GameScaffold(showsBar: !round.isFinished, onClose: close) {
            GameProgressHeader(done: round.index, total: round.count)
        } content: {
            content
        }
        .pausesClock {
            round.pauseClock()
            recallSession?.pauseClock()
            // Uygulama arka planda kapatılabilir; açık cevap kaybolmasın.
            recallSession?.commitPendingAnswer()
            context.saveLogging()
        } resume: {
            round.resumeClock()
            recallSession?.resumeClock()
        }
        .onAppear { if !didStart { startRound() } }
        .onChange(of: words.aliveIDs) {
            if skipDeletedWords() { prepareRecall() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if round.isFinished {
            RoundSummaryView(
                entries: round.entries.map { .init(word: $0.word, before: $0.memoryBefore, correct: $0.firstCorrect) },
                duration: round.finishedAt.timeIntervalSince(round.startedAt),
                onAgain: startRound,
                onDone: close
            )
        } else if questions.indices.contains(round.index), !questions[round.index].word.isGone(from: words.aliveIDs) {
            question(questions[round.index], at: round.index)
                .id(round.index)
        }
    }

    @ViewBuilder
    private func question(_ question: Question, at index: Int) -> some View {
        switch question {
        case .recall:
            if let recallSession {
                RecallQuestionView(session: recallSession, words: words) {
                    if let entry = recallSession.roundEntries.first { round.adopt(entry) }
                    next(from: index)
                }
            }
        case .choice(let word, let options, let correct):
            ChoiceQuestionView(
                options: options,
                correctIndex: correct,
                onAnswer: { round.record(word, grade: .recognition(correct: $0), mode: .multipleChoice) },
                onNext: { next(from: index) }
            ) { _ in
                GameWordCard(word: word)
            }
        case .blank(let word, let cloze, let options, let correct):
            ChoiceQuestionView(
                options: options,
                correctIndex: correct,
                optionFont: .system(.body, design: .serif, weight: .semibold),
                onAnswer: { round.record(word, grade: .recognition(correct: $0), mode: .fillBlank) },
                onNext: { next(from: index) }
            ) { revealed in
                ClozeCard(word: word, cloze: cloze, revealed: revealed)
            }
        case .letters(let word, let puzzle):
            LettersQuestionView(
                word: word,
                puzzle: puzzle,
                onAnswer: { round.record(word, grade: $0, mode: .letters) },
                onNext: { next(from: index) }
            )
        }
    }

    // MARK: - Akış

    private func startRound() {
        round.start(with: words, count: StudySession.quickCount)
        let allowed = round.words.map {
            QuickMix.allowedModes(english: $0.english, example: $0.example, deckCount: words.count)
        }
        let modes = round.random { QuickMix.modes(allowed: allowed, using: &$0) }
        questions = zip(round.words, modes).map { word, mode in makeQuestion(word, mode: mode) }
        didStart = true
        prepareRecall()
    }

    private func makeQuestion(_ word: Word, mode: GameMode) -> Question {
        switch mode {
        case .multipleChoice:
            let result = options(for: word) { ChoiceQuiz.Candidate(turkish: $0.turkish) }
            return .choice(word, options: result.options, correct: result.correctIndex)
        case .fillBlank:
            if let cloze = ClozeSentence(sentence: word.example, word: word.english) {
                let result = options(for: word) { ChoiceQuiz.Candidate(text: $0.english) }
                return .blank(word, cloze: cloze, options: result.options, correct: result.correctIndex)
            }
            return .recall(word, reverse: false)
        case .letters:
            return .letters(word, round.random { LetterPuzzle(word: word.english, using: &$0) })
        case .reverse:
            return .recall(word, reverse: true)
        default:
            return .recall(word, reverse: false)
        }
    }

    private func options(for word: Word, candidate: (Word) -> ChoiceQuiz.Candidate) -> (options: [String], correctIndex: Int) {
        let others = words.filter { $0 !== word }.map(candidate)
        let answer = candidate(word)
        return round.random { ChoiceQuiz.options(answer: answer, others: others, using: &$0) }
    }

    /// Sıradaki soru hatırlama sorusuysa, cevap süresi o an başlasın diye oturumu şimdi kurar.
    private func prepareRecall() {
        guard questions.indices.contains(round.index), case .recall(let word, let reverse) = questions[round.index] else {
            recallSession = nil
            return
        }
        let session = StudySession(defaults: Self.scratchDefaults)
        session.mode = reverse ? .reverse : .quickRound
        session.start(with: [word], plan: reverse ? .reverse : .quick)
        // Doğru cevaptan sonraki otomatik geçiş arka planda olduysa oturum duraklatılmış başlasın;
        // öne gelince `resumeClock` sürdürür.
        if scenePhase != .active { session.pauseClock() }
        recallSession = session
    }

    /// Soru `index`'teyken sıradakine geçer. Soru bu arada (ör. silinen kelime atlanınca) değiştiyse bir şey yapmaz.
    private func next(from index: Int) {
        guard round.index == index else { return }
        round.advance()
        skipDeletedWords()
        if scenePhase != .active { round.pauseClock() }
        prepareRecall()
    }

    /// Tur sürerken silinen kelimenin sorusu atlanır. Soru değiştiyse `true`.
    @discardableResult
    private func skipDeletedWords() -> Bool {
        let alive = words.aliveIDs
        var skipped = false
        while questions.indices.contains(round.index), questions[round.index].word.isGone(from: alive) {
            round.advance()
            skipped = true
        }
        return skipped
    }

    private func close() {
        recallSession?.gradePendingAnswer()
        context.saveLogging()
        if let onClose { onClose() } else { dismiss() }
    }
}
