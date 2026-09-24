import SwiftData
import SwiftUI

/// Harfleri Diz: Türkçe anlamlar üstte, altında cevap yuvaları, en altta karışık harf taşları.
/// Yuvalar dolunca kendiliğinden kontrol edilir; yanlışta yuvalar sallanır, harfler yerinde kalır.
struct LettersGameView: View {
    static let questionCount = 8

    /// Mac'te oyun merkezine dönüş; iOS'ta `nil` (tam ekran kapanır).
    var onClose: (() -> Void)? = nil

    @Query private var words: [Word]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var round = GameRound(mode: .letters)
    @State private var puzzles: [LetterPuzzle] = []
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
        if let onClose { onClose() } else { dismiss() }
    }
}

/// Tek bir Harfleri Diz sorusu. Harfleri Diz ve karışık Hızlı Tur kullanır; soru değişince `.id` ile yenilenmeli.
/// Mac'te harfler klavyeden yazılır: harf uyan taşı yerleştirir, ⌫ son harfi geri alır, ⌘↩ gösterir, ↩ devam eder.
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
    #if os(macOS)
    @FocusState private var keyboardFocused: Bool
    #endif

    var body: some View {
        let puzzle = state ?? self.puzzle
        ScrollView {
            VStack(spacing: 28) {
                meaningCard(word)
                slotsView(puzzle)
                    .modifier(ShakeEffect(trigger: shakes))
                if solved && !puzzle.grade.isCorrect {
                    // Özetteki ✗ ile tutarlı: 3+ hatayla bulunan kelime bilinmemiş sayılır.
                    Label("Çok denemeyle bulundu, bilemedin sayıldı", systemImage: "xmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                tilesView(puzzle)
            }
            .gamePagePadding()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if puzzle.isRevealed || (solved && !puzzle.grade.isCorrect) {
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
                    #if os(macOS)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Cevabı göster (⌘↩)")
                    #endif
                }
            }
            .gameBarPadding()
        }
        .animation(.snappy(duration: 0.2), value: puzzle)
        .sensoryFeedback(.warning, trigger: shakes)
        .sensoryFeedback(.success, trigger: solved) { _, new in new && puzzle.grade.isCorrect }
        #if os(macOS)
        .focusable()
        .focusEffectDisabled()
        .focused($keyboardFocused)
        .onKeyPress(phases: .down) { press in type(press) }
        .onAppear { keyboardFocused = true }
        #endif
    }

    #if os(macOS)
    /// Klavyeden yazılan harf uyan serbest taşı yerleştirir; ⌫ son yerleştirilen harfi geri alır.
    private func type(_ press: KeyPress) -> KeyPress.Result {
        let current = state ?? puzzle
        guard !solved, !current.isRevealed, press.modifiers.subtracting(.shift).isEmpty else { return .ignored }
        if press.key == .delete {
            guard let slot = current.lastFilledSlot else { return .ignored }
            update { $0.remove(slot: slot) }
            return .handled
        }
        guard press.characters.count == 1, let character = press.characters.first, character.isLetter else {
            return .ignored
        }
        if let tile = current.freeTile(matching: character) {
            place(tile)
        } else {
            // Uyan taş yok (harf yok ya da hepsi kullanıldı): yuvalar kısaca sallanır.
            shakes += 1
        }
        return .handled
    }
    #endif

    private func meaningCard(_ word: Word) -> some View {
        Text(word.turkish)
            .font(.title2.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
        .gameCard()
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
        .accessibilityLabel("Cevap: " + puzzle.slots.map { $0.map { LetterPuzzle.display(puzzle.tiles[$0]) } ?? "boş" }.joined(separator: " "))
    }

    private func slotView(_ slot: Int, puzzle: LetterPuzzle, width: CGFloat) -> some View {
        let tile = puzzle.slots[slot]
        // Doluyken yanlışsa kırmızı kalır; kullanıcı bir harfi çıkarınca normale döner.
        // 3+ hatadan sonra bulunan kelime özette ✗ sayılır; ekranda da yeşil kutlanmaz (turuncu).
        let color: Color = solved ? (puzzle.grade.isCorrect ? .green : .orange)
            : puzzle.isRevealed ? .accentColor
            : (puzzle.isFull && !puzzle.isCorrect) ? .red
            : .primary
        return Button {
            update { $0.remove(slot: slot) }
        } label: {
            Text(tile.map { LetterPuzzle.display(puzzle.tiles[$0]) } ?? "")
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
                    Text(LetterPuzzle.display(puzzle.tiles[index]))
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
            // Bilemedin sayılan çözümde kendiliğinden geçilmez; kullanıcı notu görüp Devam'a basar.
            guard puzzle.grade.isCorrect else { return }
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

