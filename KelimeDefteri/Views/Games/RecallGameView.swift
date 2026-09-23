import SwiftData
import SwiftUI

/// Hatırlama oyunu: Günlük Tekrar ve Hızlı Tur. Kart ve cevap çubuğu eski Çalış ekranıyla aynı;
/// tur bitince özet gösterilir. Oyun merkezinden tam ekran açılır.
struct RecallGameView: View {
    let plan: StudySession.Plan
    let mode: GameMode

    @Query(sort: \Word.dueDate) private var words: [Word]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var session = StudySession()
    @State private var answer = ""
    @State private var didStart = false
    @FocusState private var answerFocused: Bool
    @Namespace private var glassNamespace

    private var hasAnswer: Bool { !answer.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            content
                .background(Color(.systemGroupedBackground))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if session.current != nil {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(role: .close) { close() }
                                .accessibilityLabel("Kapat")
                        }
                        ToolbarItem(placement: .principal) {
                            GameProgressHeader(done: session.reviewedCount, total: total)
                        }
                    }
                }
                .sensoryFeedback(.selection, trigger: session.reviewedCount)
        }
        .onAppear {
            if !didStart { startRound() }
        }
        .onChange(of: words.count) {
            session.sync(with: words)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let word = session.current {
            ScrollView {
                card(for: word)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
                    .padding(.horizontal)
                    .padding(.vertical, 12)
            }
            .animation(.snappy, value: session.phase)
        } else if didStart {
            RoundSummaryView(
                entries: session.roundEntries.map {
                    RoundSummaryView.Entry(word: $0.word, before: $0.memoryBefore, correct: $0.firstCorrect)
                },
                duration: session.finishedAt.timeIntervalSince(session.startedAt),
                onAgain: startRound,
                onDone: close
            )
        }
    }

    /// Turdaki toplam kart; bilinmeyen kelime sıraya yeniden girdiği için tur içinde büyüyebilir.
    private var total: Int { session.reviewedCount + session.remaining + (session.current == nil ? 0 : 1) }

    private func startRound() {
        answer = ""
        session.mode = mode
        session.start(with: words, plan: plan)
        // Günlük Tekrar'dan sonra zayıf kelime kalmadıysa "Bir Tur Daha" en zayıflarla devam eder.
        if session.current == nil && plan == .daily {
            session.start(with: words, plan: .extraPractice)
        }
        didStart = true
    }

    private func close() {
        try? context.save()
        dismiss()
    }

    // MARK: - Kart

    private func card(for word: Word) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                if !word.source.isEmpty {
                    Image(systemName: "book.closed")
                    Text(word.source)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                MemoryRing(memory: word.memory(), size: 12, text: .trailing)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

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

            if !word.example.isEmpty {
                Text(AttributedString(quoting: word.example, highlighting: word.english))
                    .font(.system(.body, design: .serif).italic())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .revealed(let verdict) = session.phase {
                answerReveal(for: word, verdict: verdict)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26, style: .continuous))
        .contentShape(.rect(cornerRadius: 26, style: .continuous))
        .onTapGesture {
            if session.phase == .asking { reveal(withAnswer: false) }
        }
        .accessibilityAddTraits(session.phase == .asking ? .isButton : [])
        .accessibilityHint(session.phase == .asking ? "Türkçesini göster" : "")
    }

    private func answerReveal(for word: Word, verdict: StudySession.Verdict) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.bottom, 4)
            verdictLabel(verdict)
            Text(word.turkish)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tint)
                .fixedSize(horizontal: false, vertical: true)
            if !word.definition.isEmpty {
                Text(word.definition)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if verdict == .incorrect {
                Text("Senin cevabın: “\(answer)”. Anlamca aynıysa Doğru Say'a bas.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            let related = word.related(in: words)
            if !related.isEmpty {
                Label {
                    Text("İlişkili: ") + Text(related.prefix(3).map(\.english).joined(separator: ", ")).fontWeight(.medium)
                } icon: {
                    Image(systemName: "link")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func verdictLabel(_ verdict: StudySession.Verdict) -> some View {
        let (text, icon, color): (String, String, Color) = switch verdict {
        case .correct: ("Doğru", "checkmark.circle.fill", .green)
        case .incorrect: ("Tam tutmadı", "xmark.circle.fill", .red)
        case .peeked: ("Cevaba baktın. Biliyor muydun?", "eye.fill", .secondary)
        }
        return Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
    }

    // MARK: - Alt çubuk

    @ViewBuilder
    private var bottomBar: some View {
        switch session.phase {
        case .asking:
            // Mesajlar'daki gibi tek eylem düğmesi: alan boşken "Göster", yazınca "Kontrol et".
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    TextField("Türkçesi", text: $answer)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($answerFocused)
                        .onSubmit { reveal(withAnswer: true) }
                        .padding(.horizontal, 18)
                        .frame(height: 48)
                        .glassEffect(.regular.interactive(), in: .capsule)

                    if hasAnswer {
                        Button("Kontrol et", systemImage: "arrow.up") { reveal(withAnswer: true) }
                            .labelStyle(.iconOnly)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .glassEffect(.regular.tint(.accentColor).interactive(), in: .circle)
                            .glassEffectID("action", in: glassNamespace)
                    } else {
                        Button("Göster") { reveal(withAnswer: false) }
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 18)
                            .frame(height: 48)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .glassEffectID("action", in: glassNamespace)
                            .accessibilityHint("Türkçesini gösterir")
                    }
                }
            }
            .animation(.snappy(duration: 0.25), value: hasAnswer)
        case .revealed(let verdict):
            HStack(spacing: 12) {
                ForEach(verdict.gradeOptions) { gradeButton($0) }
            }
            .sensoryFeedback(verdict == .correct ? .success : .warning, trigger: verdict)
        }
    }

    @ViewBuilder
    private func gradeButton(_ option: GradeOption) -> some View {
        let button = Button {
            session.grade(known: option.known)
            answer = ""
        } label: {
            Label(option.title, systemImage: option.systemImage)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .controlSize(.large)
        if option.isPrimary {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass).foregroundStyle(option.known ? .green : .red)
        }
    }

    private func reveal(withAnswer: Bool) {
        if !withAnswer { answer = "" }
        answerFocused = false
        session.reveal(answer: withAnswer ? answer : nil)
    }

}

/// Oyunların üstündeki ince ilerleme çubuğu ve "3/10".
struct GameProgressHeader: View {
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 10) {
            ProgressView(value: Double(done), total: Double(max(total, 1)))
                .frame(width: 150)
            Text("\(min(done + 1, total))/\(total)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(total) kelimeden \(min(done + 1, total)). kelime")
    }
}
