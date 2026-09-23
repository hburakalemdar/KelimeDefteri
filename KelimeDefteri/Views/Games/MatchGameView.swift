import SwiftData
import SwiftUI

/// Eşleştir: solda İngilizce kelimeler, sağda karışık Türkçe anlamlar. Bir soldan bir sağdan seçilir;
/// doğru çift yeşil olup kaybolur, yanlış çift sallanıp kırmızı yanıp söner.
struct MatchGameView: View {
    static let pairCount = 5

    @Query private var words: [Word]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var round = GameRound(mode: .match)
    @State private var board: MatchBoard?
    @State private var meanings: [String] = []
    @State private var selectedLeft: Int?
    @State private var selectedRight: Int?
    @State private var justMatched: Int?
    @State private var wrongPair: (left: Int, right: Int)?
    @State private var shakes = 0
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
                            GameProgressHeader(done: board?.matched.count ?? 0, total: round.count, showsCount: false)
                        }
                    }
                }
                .sensoryFeedback(.success, trigger: board?.matched.count ?? 0)
                .sensoryFeedback(.warning, trigger: shakes)
                .sensoryFeedback(.selection, trigger: selectionKey)
        }
        .onAppear { if !didStart { startRound() } }
    }

    private var selectionKey: String { "\(selectedLeft ?? -1)-\(selectedRight ?? -1)" }

    @ViewBuilder
    private var content: some View {
        if round.isFinished {
            RoundSummaryView(
                entries: round.entries.map { .init(word: $0.word, before: $0.memoryBefore, correct: $0.firstCorrect) },
                duration: round.finishedAt.timeIntervalSince(round.startedAt),
                onAgain: startRound,
                onDone: close
            )
        } else if let board {
            ScrollView {
                VStack(spacing: 16) {
                    statusRow(board)
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 10) {
                            ForEach(board.left, id: \.self) { id in
                                tile(id: id, isLeft: true, board: board)
                            }
                        }
                        VStack(spacing: 10) {
                            ForEach(board.right, id: \.self) { id in
                                tile(id: id, isLeft: false, board: board)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
    }

    /// Süre (mm:ss) ve hata sayısı.
    private func statusRow(_ board: MatchBoard) -> some View {
        HStack {
            TimelineView(.periodic(from: round.startedAt, by: 1)) { context in
                Label(Self.clock(context.date.timeIntervalSince(round.startedAt)), systemImage: "timer")
            }
            Spacer()
            Label(board.errors == 0 ? "Hata yok" : "\(board.errors) hata", systemImage: "xmark.circle")
                .foregroundStyle(board.errors == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
        }
        .font(.subheadline.weight(.medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @ViewBuilder
    private func tile(id: Int, isLeft: Bool, board: MatchBoard) -> some View {
        let isMatched = board.matched.contains(id) && justMatched != id
        let isSelected = isLeft ? selectedLeft == id : selectedRight == id
        let isWrong = wrongPair.map { isLeft ? $0.left == id : $0.right == id } ?? false
        let isRight = justMatched == id
        let text = isLeft ? round.words[id].english : meanings[id]

        Button {
            tap(id: id, isLeft: isLeft)
        } label: {
            Text(text)
                .font(isLeft ? .system(.body, design: .serif, weight: .semibold) : .body)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .lineLimit(3)
                .foregroundStyle(isRight || isWrong ? Color.white : .primary)
                .frame(maxWidth: .infinity, minHeight: 64)
                .padding(.horizontal, 10)
                .background(background(selected: isSelected, wrong: isWrong, right: isRight),
                            in: .rect(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected && !isWrong ? 2 : 0)
                }
                .contentShape(.rect(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .modifier(Shake(amount: isWrong ? 1 : 0, trigger: shakes))
        .opacity(isMatched ? 0 : 1)
        .scaleEffect(isMatched ? 0.9 : 1)
        .allowsHitTesting(!board.matched.contains(id) && wrongPair == nil)
        .accessibilityHidden(isMatched)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func background(selected: Bool, wrong: Bool, right: Bool) -> Color {
        if right { return .green }
        if wrong { return .red }
        if selected { return Color.accentColor.opacity(0.15) }
        return Color(.secondarySystemGroupedBackground)
    }

    // MARK: - Akış

    private func startRound() {
        round.start(with: words, count: Self.pairCount, distinctBy: { AnswerChecker.fold(ChoiceQuiz.firstMeaning($0.turkish)) })
        meanings = round.words.map { ChoiceQuiz.firstMeaning($0.turkish) }
        board = round.random { MatchBoard(count: round.count, using: &$0) }
        selectedLeft = nil
        selectedRight = nil
        justMatched = nil
        wrongPair = nil
        didStart = true
    }

    private func tap(id: Int, isLeft: Bool) {
        if isLeft {
            selectedLeft = selectedLeft == id ? nil : id
        } else {
            selectedRight = selectedRight == id ? nil : id
        }
        guard let left = selectedLeft, let right = selectedRight, var board else { return }
        let result = board.pick(left: left, right: right)
        self.board = board
        selectedLeft = nil
        selectedRight = nil

        switch result {
        case .matched(let id):
            round.record(round.words[id], grade: board.grade(for: id), timed: false)
            justMatched = id
            Task {
                try? await Task.sleep(for: .seconds(0.35))
                withAnimation(.snappy) { justMatched = nil }
                if board.isComplete {
                    try? await Task.sleep(for: .seconds(0.3))
                    round.finish()
                }
            }
        case .mismatched(let left, let right):
            wrongPair = (left, right)
            shakes += 1
            Task {
                try? await Task.sleep(for: .seconds(0.45))
                withAnimation(.snappy) { wrongPair = nil }
            }
        }
    }

    private func close() {
        try? context.save()
        dismiss()
    }
}

/// Yanlış seçimde kutunun kısa yatay sallanması.
private struct Shake: ViewModifier {
    let amount: CGFloat
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, offset in
            view.offset(x: offset * amount)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(-8, duration: 0.06)
                SpringKeyframe(8, duration: 0.08)
                SpringKeyframe(-6, duration: 0.08)
                SpringKeyframe(4, duration: 0.08)
                SpringKeyframe(0, duration: 0.1)
            }
        }
    }
}
