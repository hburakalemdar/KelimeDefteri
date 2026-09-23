import SwiftData
import SwiftUI

/// Eşleştir: solda İngilizce kelimeler, sağda karışık Türkçe anlamlar. Bir soldan bir sağdan seçilir;
/// doğru çift yeşil olup kaybolur, yanlış çift sallanıp kırmızı yanıp söner.
/// Mac'te bir kutu öbür sütundaki kutunun üstüne sürüklenerek de eşlenir.
struct MatchGameView: View {
    static let pairCount = 5

    /// Mac'te oyun merkezine dönüş; iOS'ta `nil` (tam ekran kapanır).
    var onClose: (() -> Void)? = nil

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
    #if os(macOS)
    /// Sürüklenen kutunun üstünde durduğu kutu (vurgulanır).
    @State private var dropTarget: String?
    #endif

    #if os(iOS)
    private let tileHeight: CGFloat = 64
    private let tileSpacing: CGFloat = 10
    #else
    private let tileHeight: CGFloat = 50
    private let tileSpacing: CGFloat = 8
    #endif

    var body: some View {
        GameScaffold(showsBar: !round.isFinished, onClose: close) {
            let gone = goneIDs
            GameProgressHeader(
                done: board?.matched.subtracting(gone).count ?? 0,
                total: round.count - gone.count,
                showsCount: false
            )
        } content: {
            content
        }
        .sensoryFeedback(.success, trigger: board?.matched.count ?? 0)
        .sensoryFeedback(.warning, trigger: shakes)
        .sensoryFeedback(.selection, trigger: selectionKey)
        .pausesClock { round.pauseClock() } resume: { round.resumeClock() }
        .onAppear { if !didStart { startRound() } }
        .onChange(of: words.aliveIDs) { removeDeletedWords() }
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
            let gone = goneIDs
            ScrollView {
                VStack(spacing: 16) {
                    statusRow(board)
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: tileSpacing) {
                            columnHeader("İngilizce")
                            ForEach(board.left.filter { !gone.contains($0) }, id: \.self) { id in
                                tile(id: id, isLeft: true, board: board)
                            }
                        }
                        VStack(spacing: tileSpacing) {
                            columnHeader("Türkçe")
                            ForEach(board.right.filter { !gone.contains($0) }, id: \.self) { id in
                                tile(id: id, isLeft: false, board: board)
                            }
                        }
                    }
                    .animation(.snappy, value: gone)
                }
                .gamePagePadding()
            }
        }
    }

    /// Sütunun dilini söyleyen başlık (liste bölüm başlığı gibi); kartlar arasında sıra zorunlu değil.
    private func columnHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
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
        let radius = GameStyle.tileRadius
        #if os(macOS)
        let isTargeted = dropTarget == Self.dragKey(id: id, isLeft: isLeft)
        #else
        let isTargeted = false
        #endif

        let button = Button {
            tap(id: id, isLeft: isLeft)
        } label: {
            Text(text)
                .font(isLeft ? .system(.body, design: .serif, weight: .semibold) : .body)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .lineLimit(3)
                .foregroundStyle(isRight || isWrong ? Color.white : .primary)
                .frame(maxWidth: .infinity, minHeight: tileHeight)
                .padding(.horizontal, 10)
                .background(background(selected: isSelected || isTargeted, wrong: isWrong, right: isRight),
                            in: .rect(cornerRadius: radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: (isSelected || isTargeted) && !isWrong ? 2 : 0)
                }
                .contentShape(.rect(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(.plain)

        #if os(macOS)
        // Sürükle-bırak: kutu öbür sütundaki bir kutunun üstüne bırakılınca o çift denenir.
        button
            .draggable(Self.dragKey(id: id, isLeft: isLeft)) {
                Text(text)
                    .font(isLeft ? .system(.body, design: .serif, weight: .semibold) : .body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: .rect(cornerRadius: radius, style: .continuous))
            }
            .dropDestination(for: String.self) { items, _ in
                guard let key = items.first else { return false }
                return drop(key, onto: id, isLeft: isLeft)
            } isTargeted: { targeted in
                let key = Self.dragKey(id: id, isLeft: isLeft)
                if targeted { dropTarget = key } else if dropTarget == key { dropTarget = nil }
            }
            .modifier(Shake(amount: isWrong ? 1 : 0, trigger: shakes))
            .opacity(isMatched ? 0 : 1)
            .scaleEffect(isMatched ? 0.9 : 1)
            .allowsHitTesting(!board.matched.contains(id) && wrongPair == nil)
            .accessibilityHidden(isMatched)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        #else
        button
        .modifier(Shake(amount: isWrong ? 1 : 0, trigger: shakes))
        .opacity(isMatched ? 0 : 1)
        .scaleEffect(isMatched ? 0.9 : 1)
        .allowsHitTesting(!board.matched.contains(id) && wrongPair == nil)
        .accessibilityHidden(isMatched)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        #endif
    }

    private func background(selected: Bool, wrong: Bool, right: Bool) -> AnyShapeStyle {
        if right { return AnyShapeStyle(Color.green) }
        if wrong { return AnyShapeStyle(Color.red) }
        if selected { return AnyShapeStyle(Color.accentColor.opacity(0.15)) }
        return AnyShapeStyle(GameStyle.cardFill)
    }

    // MARK: - Akış

    private func startRound() {
        round.start(with: words, count: Self.pairCount, conflicts: { ChoiceQuiz.shareMeaning($0.turkish, $1.turkish) })
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
        guard let left = selectedLeft, let right = selectedRight else { return }
        pick(left: left, right: right)
    }

    /// Bir soldan bir sağdan kutu seçilince çifti dener: doğruysa kaydeder, yanlışsa sallar.
    private func pick(left: Int, right: Int) {
        guard var board else { return }
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
                if isComplete(board) {
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

    #if os(macOS)
    /// Sürüklenen kutunun kimliği: "L3" (İngilizce) ya da "R2" (Türkçe).
    private static func dragKey(id: Int, isLeft: Bool) -> String { (isLeft ? "L" : "R") + String(id) }

    /// Sürüklenen kutu öbür sütundaki kutuya bırakıldı; aynı sütuna bırakmak bir şey yapmaz.
    private func drop(_ key: String, onto id: Int, isLeft: Bool) -> Bool {
        dropTarget = nil
        guard let side = key.first, let source = Int(key.dropFirst()), (side == "L") != isLeft,
              let board, wrongPair == nil,
              !board.matched.contains(source), !board.matched.contains(id)
        else { return false }
        selectedLeft = nil
        selectedRight = nil
        if isLeft { pick(left: id, right: source) } else { pick(left: source, right: id) }
        return true
    }
    #endif

    /// Tur sürerken silinen kelimelerin turdaki kimlikleri; iki kutusu da tahtadan kalkar.
    private var goneIDs: Set<Int> {
        let alive = words.aliveIDs
        return Set(round.words.indices.filter { round.words[$0].isGone(from: alive) })
    }

    /// Silinenler dışındaki bütün çiftler eşleşti mi.
    private func isComplete(_ board: MatchBoard) -> Bool {
        board.matched.union(goneIDs).count == board.left.count
    }

    private func removeDeletedWords() {
        guard let board, !round.isFinished else { return }
        let gone = goneIDs
        guard !gone.isEmpty else { return }
        if let selectedLeft, gone.contains(selectedLeft) { self.selectedLeft = nil }
        if let selectedRight, gone.contains(selectedRight) { self.selectedRight = nil }
        if let wrongPair, gone.contains(wrongPair.left) || gone.contains(wrongPair.right) { self.wrongPair = nil }
        // Kalan çiftler zaten eşleşmişse tur kalanlarla biter.
        if isComplete(board) { round.finish() }
    }

    private func close() {
        context.saveLogging()
        if let onClose { onClose() } else { dismiss() }
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
