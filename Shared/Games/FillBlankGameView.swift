import SwiftData
import SwiftUI

/// Boşluğu Doldur: kitaptaki cümlede kelimenin yeri boş; altında Türkçe ipucu, 4 İngilizce seçenek.
/// Doğru/yanlış davranışı Çoktan Seçmeli ile aynı; cevap açılınca boşluk kelimeyle dolar.
struct FillBlankGameView: View {
    static let questionCount = 10

    private struct Question {
        let word: Word
        let cloze: ClozeSentence
        /// Türkçe ipucu: sırası gelen anlam, soru kurulurken bir kez seçilir (cevap kaydı eklenince değişmesin).
        let hint: String
        let options: [String]
        let correctIndex: Int
    }

    /// Mac'te oyun merkezine dönüş; iOS'ta `nil` (tam ekran kapanır).
    var onClose: (() -> Void)? = nil

    @Query private var words: [Word]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var round = GameRound(mode: .fillBlank)
    @State private var questions: [Question] = []
    @State private var didStart = false

    var body: some View {
        GameScaffold(showsBar: !round.isFinished, onClose: close) {
            GameProgressHeader(done: round.index, total: round.count)
        } content: {
            content
        }
        .pausesClock { round.pauseClock() } resume: { round.resumeClock() }
        .onAppear { if !didStart { startRound() } }
        .onChange(of: words.aliveIDs) { skipDeletedWords() }
    }

    @ViewBuilder
    private var content: some View {
        if round.isFinished {
            RoundSummaryView(
                entries: round.entries.map(RoundSummaryView.Entry.init),
                duration: round.finishedAt.timeIntervalSince(round.startedAt),
                roundStartedAt: round.beganAt,
                onAgain: startRound,
                onDone: close
            )
        } else if questions.indices.contains(round.index), !questions[round.index].word.isGone(from: words.aliveIDs) {
            let question = questions[round.index]
            let index = round.index
            ChoiceQuestionView(
                options: question.options,
                correctIndex: question.correctIndex,
                optionFont: .system(.body, design: .serif, weight: .semibold),
                onAnswer: { round.record(question.word, grade: .recognition(correct: $0), meaning: question.hint) },
                onNext: { advance(from: index) }
            ) { revealed in
                ClozeCard(cloze: question.cloze, hint: question.hint, revealed: revealed)
            }
            .id(round.index)
        }
    }

    private func startRound() {
        let playable = words.filter(\.hasClozeSentence)
        round.start(with: playable, count: Self.questionCount)
        questions = round.words.compactMap { word in
            // Cümle sorulan anlamınki öncelikli; ipucu seçilen cümleyle uyuşur (bkz. `Word.cloze(for:)`).
            guard let blank = word.cloze(for: word.askedMeaning) else { return nil }
            // İngilizce seçenekler Türkçe anlamlarıyla karşılaştırılır: ipucuyla aynı anlamı taşıyan
            // başka kelime çeldirici olmaz (iki doğru şık çıkmasın).
            let candidate = { (word: Word) in
                ChoiceQuiz.Candidate(text: word.english, meanings: AnswerChecker.meanings(in: word.turkish))
            }
            let others = words.filter { $0 !== word }.map(candidate)
            let answer = candidate(word)
            let result = round.random { ChoiceQuiz.options(answer: answer, others: others, using: &$0) }
            return Question(
                word: word, cloze: blank.cloze, hint: blank.hint, options: result.options, correctIndex: result.correctIndex
            )
        }
        didStart = true
    }

    /// Soru `index`'teyken sıradakine geçer. Soru bu arada (ör. silinen kelime atlanınca) değiştiyse bir şey yapmaz.
    private func advance(from index: Int) {
        guard round.index == index else { return }
        round.advance()
        skipDeletedWords()
        // Doğru cevaptan sonraki otomatik geçiş arka planda olduysa yeni sorunun saati de dursun.
        if scenePhase != .active { round.pauseClock() }
    }

    /// Tur sürerken silinen kelimenin sorusu atlanır.
    private func skipDeletedWords() {
        let alive = words.aliveIDs
        while let word = round.current, word.isGone(from: alive) { round.advance() }
    }

    private func close() {
        context.saveLogging()
        if let onClose { onClose() } else { dismiss() }
    }
}

/// Boşluğu Doldur kartı: cümle, kelimenin yeri boş; altında Türkçe ipucu ve kitap adı.
/// Cevap açılınca boşluk kelimeyle dolar (vurgu rengi, kalın).
struct ClozeCard: View {
    let cloze: ClozeSentence
    /// Türkçe ipucu: cümlenin anlamı ya da sorulan anlam (`Word.cloze(for:)`, soru kurulurken alınır).
    let hint: String
    let revealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(sentence)
                .font(.system(.title3, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            Label(hint, systemImage: "lightbulb")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .gameCard()
    }

    /// Kelimenin cümledeki bütün geçişleri boş (ya da açılınca vurgulu kelime) gösterilir.
    private var sentence: AttributedString {
        var result = AttributedString("“")
        for (index, piece) in cloze.pieces.enumerated() {
            guard index % 2 == 1 else {
                result += AttributedString(piece)
                continue
            }
            var gap: AttributedString
            if revealed {
                gap = AttributedString(piece)
                gap.foregroundColor = .accentColor
                gap.inlinePresentationIntent = .stronglyEmphasized
            } else {
                gap = AttributedString(ClozeSentence.blank)
                gap.foregroundColor = .secondary
            }
            result += gap
        }
        result += AttributedString("”")
        return result
    }
}
