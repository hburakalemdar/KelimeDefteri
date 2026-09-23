import SwiftData
import SwiftUI

/// Çoktan Seçmeli: İngilizce kelime, 4 Türkçe anlam. Doğru seçim kendiliğinden geçer;
/// yanlışta doğrusu gösterilir ve kullanıcı "Devam"a basar.
struct ChoiceGameView: View {
    static let questionCount = 10

    private struct Question {
        let word: Word
        let options: [String]
        let correctIndex: Int
    }

    @Query private var words: [Word]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var round = GameRound(mode: .multipleChoice)
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
                    GameWordCard(word: question.word)
                    ChoiceButtons(
                        options: question.options,
                        correctIndex: question.correctIndex,
                        selected: selected,
                        font: .body.weight(.semibold)
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

    private func startRound() {
        round.start(with: words, count: Self.questionCount)
        questions = round.words.map { word in
            let others = words.filter { $0 !== word }.map {
                ChoiceQuiz.Candidate(text: ChoiceQuiz.firstMeaning($0.turkish), source: $0.source)
            }
            let answer = ChoiceQuiz.Candidate(text: ChoiceQuiz.firstMeaning(word.turkish), source: word.source)
            let result = round.random { ChoiceQuiz.options(answer: answer, others: others, using: &$0) }
            return Question(word: word, options: result.options, correctIndex: result.correctIndex)
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

// MARK: - Ortak parçalar

/// Oyunlarda sorulan İngilizce kelimenin kartı: serif kelime, telaffuz, varsa kitaptaki cümle.
struct GameWordCard: View {
    let word: Word
    var showsSentence = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(word.english)
                    .font(.system(.largeTitle, design: .serif, weight: .semibold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                Spacer(minLength: 12)
                Button("Telaffuzu dinle", systemImage: "speaker.wave.2.fill") {
                    Speaker.shared.speak(word.english)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            if showsSentence && !word.example.isEmpty {
                Text(AttributedString(quoting: word.example, highlighting: word.english))
                    .font(.system(.subheadline, design: .serif).italic())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26, style: .continuous))
    }
}

/// Tam genişlik cam seçenek düğmeleri. Seçimden sonra doğru yeşil, yanlış seçilen kırmızı olur.
struct ChoiceButtons: View {
    let options: [String]
    let correctIndex: Int
    let selected: Int?
    var font: Font = .body
    var onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(options.indices, id: \.self) { index in
                button(index)
            }
        }
        .sensoryFeedback(trigger: selected) { _, new in
            guard let new else { return nil }
            return new == correctIndex ? .success : .warning
        }
    }

    @ViewBuilder
    private func button(_ index: Int) -> some View {
        let state = state(of: index)
        let label = HStack(spacing: 8) {
            Text(options[index])
                .font(font)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let icon = state.icon {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)

        let button = Button { onSelect(index) } label: { label }
            .controlSize(.large)
            .allowsHitTesting(selected == nil)
            .accessibilityAddTraits(state == .correct ? .isSelected : [])
        switch state {
        case .idle:
            button.buttonStyle(.glass)
        case .faded:
            button.buttonStyle(.glass).opacity(0.45)
        case .correct:
            button.buttonStyle(.glassProminent).tint(.green)
        case .wrong:
            button.buttonStyle(.glassProminent).tint(.red)
        }
    }

    private enum ChoiceState: Equatable {
        case idle, faded, correct, wrong
        var icon: String? {
            switch self {
            case .correct: "checkmark"
            case .wrong: "xmark"
            default: nil
            }
        }
    }

    private func state(of index: Int) -> ChoiceState {
        guard let selected else { return .idle }
        if index == correctIndex { return .correct }
        return index == selected ? .wrong : .faded
    }
}

/// Yanlış cevaptan sonra beliren tam genişlik "Devam" düğmesi.
struct ContinueButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Devam", systemImage: "arrow.right")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }
}
