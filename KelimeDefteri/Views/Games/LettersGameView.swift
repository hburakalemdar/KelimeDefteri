import SwiftData
import SwiftUI

/// Harfleri Diz: Türkçe anlamlar üstte, altında cevap yuvaları, en altta karışık harf taşları.
/// Yuvalar dolunca kendiliğinden kontrol edilir; yanlışta yuvalar sallanır, harfler yerinde kalır.
struct LettersGameView: View {
    static let questionCount = 8

    @Query private var words: [Word]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var round = GameRound(mode: .letters)
    @State private var puzzles: [LetterPuzzle] = []
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
        .pausesClock { round.pauseClock() } resume: { round.resumeClock() }
        .onAppear { if !didStart { startRound() } }
        .onChange(of: words.aliveIDs) { skipDeletedWords() }
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
        } else if puzzles.indices.contains(round.index), let word = round.current, !word.isGone(from: words.aliveIDs) {
            let index = round.index
            LettersQuestionView(
                word: word,
                puzzle: puzzles[round.index],
                onAnswer: { round.record(word, grade: $0) },
                onNext: { advance(from: index) }
            )
            .id(round.index)
        }
    }

    private func startRound() {
        let playable = words.filter { (1...GameDeck.maxLetters).contains(GameDeck.letterCount($0.english)) }
        round.start(with: playable, count: Self.questionCount)
        puzzles = round.words.map { word in round.random { LetterPuzzle(word: word.english, using: &$0) } }
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
        dismiss()
    }
}

/// Tek bir Harfleri Diz sorusu. Harfleri Diz ve karışık Hızlı Tur kullanır; soru değişince `.id` ile yenilenmeli.
struct LettersQuestionView: View {
    let word: Word
    /// Sorunun başlangıç hâli (karışık taşlar).
    let puzzle: LetterPuzzle
    /// Çözülünce ya da cevap açılınca bir kez, notla çağrılır.
    var onAnswer: (AnswerGrade) -> Void
    var onNext: () -> Void

    @State private var state: LetterPuzzle?
    @State private var solved = false
    @State private var shakes = 0

    var body: some View {
        let puzzle = state ?? self.puzzle
        ScrollView {
            VStack(spacing: 28) {
                meaningCard(word)
                slotsView(puzzle)
                    .modifier(ShakeEffect(trigger: shakes))
                tilesView(puzzle)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if puzzle.isRevealed {
                    ContinueButton(action: onNext)
                } else {
                    Button {
                        reveal()
                    } label: {
                        Label("Göster", systemImage: "eye")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .disabled(solved)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .animation(.snappy(duration: 0.2), value: puzzle)
        .sensoryFeedback(.warning, trigger: shakes)
        .sensoryFeedback(.success, trigger: solved) { _, new in new }
    }

    private func meaningCard(_ word: Word) -> some View {
        Text(word.turkish)
            .font(.title2.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26, style: .continuous))
    }

    // MARK: - Yuvalar ve taşlar

    /// Yuva genişliği harf sayısına göre küçülür; 14 harf de tek satıra sığar.
    private func slotWidth(_ puzzle: LetterPuzzle) -> CGFloat {
        let cells = CGFloat(puzzle.layout.count)
        return min(38, (340 - (cells - 1) * 4) / cells)
    }

    private func slotsView(_ puzzle: LetterPuzzle) -> some View {
        let width = slotWidth(puzzle)
        return HStack(spacing: 4) {
            ForEach(Array(puzzle.layout.enumerated()), id: \.offset) { _, cell in
                switch cell {
                case .fixed(let character):
                    Text(character == " " ? "" : String(character))
                        .font(.system(size: width * 0.7, weight: .semibold, design: .serif))
                        .frame(width: width * 0.6, height: width * 1.3)
                case .slot(let slot):
                    slotView(slot, puzzle: puzzle, width: width)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cevap: " + puzzle.slots.map { $0.map { String(puzzle.tiles[$0]) } ?? "boş" }.joined(separator: " "))
    }

    private func slotView(_ slot: Int, puzzle: LetterPuzzle, width: CGFloat) -> some View {
        let tile = puzzle.slots[slot]
        // Doluyken yanlışsa kırmızı kalır; kullanıcı bir harfi çıkarınca normale döner.
        let color: Color = solved ? .green
            : puzzle.isRevealed ? .accentColor
            : (puzzle.isFull && !puzzle.isCorrect) ? .red
            : .primary
        return Button {
            update { $0.remove(slot: slot) }
        } label: {
            Text(tile.map { String(puzzle.tiles[$0]) } ?? "")
                .font(.system(size: width * 0.7, weight: .semibold, design: .serif))
                .foregroundStyle(color)
                .frame(width: width, height: width * 1.3)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(tile == nil ? Color.secondary.opacity(0.5) : color)
                        .frame(height: 2.5)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // `disabled` yazıyı soldurur; açılan cevap ve doğru dizilişin rengi korunmalı.
        .allowsHitTesting(tile != nil && !solved && !puzzle.isRevealed)
    }

    private func tilesView(_ puzzle: LetterPuzzle) -> some View {
        let free = Set(puzzle.freeTiles)
        return FlowLayout(spacing: 10, centered: true) {
            ForEach(puzzle.tiles.indices, id: \.self) { index in
                Button {
                    place(index)
                } label: {
                    Text(String(puzzle.tiles[index]))
                        .font(.system(.title2, design: .serif, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .opacity(free.contains(index) ? 1 : 0)
                .disabled(!free.contains(index) || solved || puzzle.isRevealed)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Akış

    private func update(_ change: (inout LetterPuzzle) -> Void) {
        var puzzle = state ?? self.puzzle
        change(&puzzle)
        state = puzzle
    }

    private func place(_ tile: Int) {
        update { $0.place(tile: tile) }
        guard var puzzle = state, puzzle.isFull else { return }
        let correct = puzzle.check()
        state = puzzle
        if correct {
            solved = true
            onAnswer(puzzle.grade)
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                onNext()
            }
        } else {
            shakes += 1
        }
    }

    private func reveal() {
        update { $0.reveal() }
        onAnswer(.again)
    }
}

/// Yanlış cevapta yuvaların kısa yatay sallanması.
struct ShakeEffect: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, offset in
            view.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(-10, duration: 0.06)
                SpringKeyframe(10, duration: 0.08)
                SpringKeyframe(-7, duration: 0.08)
                SpringKeyframe(4, duration: 0.08)
                SpringKeyframe(0, duration: 0.1)
            }
        }
    }
}

