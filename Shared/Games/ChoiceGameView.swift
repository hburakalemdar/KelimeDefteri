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

    /// Mac'te oyun merkezine dönüş; iOS'ta `nil` (tam ekran kapanır).
    var onClose: (() -> Void)? = nil

    @Query private var words: [Word]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var round = GameRound(mode: .multipleChoice)
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
                onAnswer: { round.record(question.word, grade: .recognition(correct: $0)) },
                onNext: { advance(from: index) }
            ) { revealed in
                GameWordCard(word: question.word, showsMeanings: revealed)
            }
            .id(round.index)
        }
    }

    private func startRound() {
        round.start(with: words, count: Self.questionCount)
        questions = round.words.map { word in
            let others = words.filter { $0 !== word }.map { ChoiceQuiz.Candidate(turkish: $0.turkish) }
            let answer = word.askedCandidate
            let result = round.random { ChoiceQuiz.options(answer: answer, others: others, using: &$0) }
            return Question(word: word, options: result.options, correctIndex: result.correctIndex)
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

// MARK: - Ortak parçalar

/// Tek bir seçmeli soru: üstte soru kartı, altında seçenekler. Doğru seçim 0,8 sn sonra kendiliğinden
/// geçer; yanlışta doğrusu gösterilir ve "Devam" belirir. Çoktan Seçmeli, Boşluğu Doldur ve karışık
/// Hızlı Tur kullanır; soru değişince `.id` ile yenilenmeli.
struct ChoiceQuestionView<Prompt: View>: View {
    let options: [String]
    let correctIndex: Int
    var optionFont: Font = .body.weight(.semibold)
    /// Seçim yapılınca bir kez, doğru olup olmadığıyla çağrılır.
    var onAnswer: (Bool) -> Void
    var onNext: () -> Void
    /// Soru kartı; parametre cevabın açılıp açılmadığı.
    @ViewBuilder var prompt: (Bool) -> Prompt

    @State private var selected: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                prompt(selected != nil)
                ChoiceButtons(options: options, correctIndex: correctIndex, selected: selected, font: optionFont) { index in
                    choose(index)
                }
            }
            .gamePagePadding()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let selected, selected != correctIndex {
                ContinueButton(action: onNext)
                    .gameBarPadding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selected)
    }

    private func choose(_ index: Int) {
        guard selected == nil else { return }
        selected = index
        let correct = index == correctIndex
        onAnswer(correct)
        if correct {
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                onNext()
            }
        }
    }
}

/// Oyunlarda sorulan İngilizce kelimenin kartı: serif kelime, telaffuz, varsa kitaptaki cümle.
struct GameWordCard: View {
    let word: Word
    var showsSentence = true
    /// Cevaptan sonra birden çok anlamlı kelimenin bütün anlamları (şıkta yalnızca biri soruldu).
    var showsMeanings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(word.english)
                    .font(GameStyle.headline)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                Spacer(minLength: 12)
                Button("Telaffuzu dinle", systemImage: "speaker.wave.2.fill") {
                    Speaker.shared.speak(word.english)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                #if os(macOS)
                .help("Telaffuzu dinle")
                #endif
            }
            if showsMeanings, case let meanings = ChoiceQuiz.displayMeanings(word.turkish), meanings.count > 1 {
                Text(meanings.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            if showsSentence && !word.example.isEmpty {
                Text(AttributedString(quoting: word.example, highlighting: word.english))
                    .font(.system(.subheadline, design: .serif).italic())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .gameCard()
    }
}

/// Tam genişlik cam seçenek düğmeleri. Seçimden sonra doğru yeşil, yanlış seçilen kırmızı olur.
/// Mac'te 1–4 tuşlarıyla seçilir; her düğmenin başında tuşu yazar.
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
            #if os(macOS)
            Text("\(index + 1)")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            #endif
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
            #if os(macOS)
            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
            #endif
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
        #if os(macOS)
        .keyboardShortcut(.defaultAction)
        .help("Devam (↩)")
        #endif
    }
}
