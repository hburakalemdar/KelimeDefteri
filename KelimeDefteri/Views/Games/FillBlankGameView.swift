import SwiftData
import SwiftUI

/// Boşluğu Doldur: kitaptaki cümlede kelimenin yeri boş; altında Türkçe ipucu, 4 İngilizce seçenek.
/// Doğru/yanlış davranışı Çoktan Seçmeli ile aynı; cevap açılınca boşluk kelimeyle dolar.
struct FillBlankGameView: View {
    static let questionCount = 10

    private struct Question {
        let word: Word
        let cloze: ClozeSentence
        let options: [String]
        let correctIndex: Int
    }

    @Query private var words: [Word]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var round = GameRound(mode: .fillBlank)
    @State private var questions: [Question] = []
    @State private var selected: Int?
    @State private var didStart = false

    var body: some View {
        NavigationStack {
            content
                .background(Color(.systemGroupedBackground))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !round.isFinished {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(role: .close) { close() }
                                .accessibilityLabel("Kapat")
                        }
                        ToolbarItem(placement: .principal) {
                            GameProgressHeader(done: round.index, total: round.count)
                        }
                    }
                }
        }
        .onAppear { if !didStart { startRound() } }
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
        } else if questions.indices.contains(round.index) {
            let question = questions[round.index]
            ScrollView {
                VStack(spacing: 20) {
                    sentenceCard(question)
                    ChoiceButtons(
                        options: question.options,
                        correctIndex: question.correctIndex,
                        selected: selected,
                        font: .system(.body, design: .serif, weight: .semibold)
                    ) { choose($0, in: question) }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let selected, selected != question.correctIndex {
                    ContinueButton { next() }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: selected)
            .id(round.index)
        }
    }

    private func sentenceCard(_ question: Question) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(sentence(question))
                .font(.system(.title3, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            Label(ChoiceQuiz.firstMeaning(question.word.turkish), systemImage: "lightbulb")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !question.word.source.isEmpty {
                Label(question.word.source, systemImage: "book.closed")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26, style: .continuous))
    }

    /// Cevap açılmadan boşluk, açılınca kelime (vurgu rengi, kalın).
    private func sentence(_ question: Question) -> AttributedString {
        var result = AttributedString("“" + question.cloze.before)
        var gap: AttributedString
        if selected == nil {
            gap = AttributedString(ClozeSentence.blank)
            gap.foregroundColor = .secondary
        } else {
            gap = AttributedString(question.cloze.match)
            gap.foregroundColor = .accentColor
            gap.inlinePresentationIntent = .stronglyEmphasized
        }
        result += gap
        result += AttributedString(question.cloze.after + "”")
        return result
    }

    private func startRound() {
        let playable = words.filter { ClozeSentence(sentence: $0.example, word: $0.english) != nil }
        round.start(with: playable, count: Self.questionCount)
        questions = round.words.compactMap { word in
            guard let cloze = ClozeSentence(sentence: word.example, word: word.english) else { return nil }
            let others = words.filter { $0 !== word }.map { ChoiceQuiz.Candidate(text: $0.english, source: $0.source) }
            let answer = ChoiceQuiz.Candidate(text: word.english, source: word.source)
            let result = round.random { ChoiceQuiz.options(answer: answer, others: others, using: &$0) }
            return Question(word: word, cloze: cloze, options: result.options, correctIndex: result.correctIndex)
        }
        selected = nil
        didStart = true
    }

    private func choose(_ index: Int, in question: Question) {
        guard selected == nil else { return }
        selected = index
        let correct = index == question.correctIndex
        round.record(question.word, grade: .recognition(correct: correct))
        if correct {
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                next()
            }
        }
    }

    private func next() {
        selected = nil
        round.advance()
    }

    private func close() {
        try? context.save()
        dismiss()
    }
}
